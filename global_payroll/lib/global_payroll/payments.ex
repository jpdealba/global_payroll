defmodule GlobalPayroll.Payments do
  import Ecto.Query

  alias Ecto.Multi
  alias GlobalPayroll.Payments.PaymentAttempt
  alias GlobalPayroll.Payrolls.{PayrollIntent, PayrollRun, Payslip}
  alias GlobalPayroll.{Repo, Ledger, Queue}

  @max_retries 3
  @reconcile_after_seconds 300

  def reconcile_stuck_intents do
    reconcile_processing_with_attempts()
    reconcile_processing_without_attempts()
    reconcile_pending_without_attempts()
    :ok
  end

  def execute_payment(intent_id) do
    with {:ok, intent} <- fetch_intent(intent_id),
         :ok <- guard_already_settled(intent),
         :ok <- guard_run_paying(intent) do
      attempt_payment(intent)
    end
  end

  def handle_webhook_event(%{"payment_id" => payment_id, "status" => status} = event) do
    with {:ok, intent} <- fetch_by_provider_id(payment_id),
         :ok <- guard_already_settled(intent) do
      case status do
        "succeeded" -> on_success(intent)
        "failed" -> on_failure(intent, intent.retry_count + 1, provider_error(event))
        _ -> {:error, :unknown_status}
      end
    end
  end

  def process_result(%{"intent_id" => intent_id, "status" => "succeeded"}) do
    with {:ok, intent} <- fetch_intent(intent_id),
         :ok <- guard_already_settled(intent) do
      on_success(intent)
    end
  end

  def process_result(%{"intent_id" => intent_id, "status" => "failed"} = event) do
    error = Map.get(event, "error", "unknown failure")

    with {:ok, intent} <- fetch_intent(intent_id),
         :ok <- guard_already_settled(intent) do
      on_failure(intent, intent.retry_count + 1, error)
    end
  end

  # --- Fetch / guards ---

  defp fetch_intent(id) do
    case Repo.get(PayrollIntent, id) do
      nil -> {:error, :not_found}
      intent -> {:ok, intent}
    end
  end

  defp fetch_by_provider_id(payment_id) do
    case Repo.get_by(PayrollIntent, provider_payment_id: payment_id) do
      nil -> {:error, :not_found}
      intent -> {:ok, intent}
    end
  end

  defp lock_intent(id) do
    from(i in PayrollIntent, where: i.id == ^id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  defp guard_already_settled(%{status: status}) when status in ["completed", "failed"],
    do: {:error, :already_settled}

  defp guard_already_settled(_), do: :ok

  defp guard_run_paying(intent) do
    case Repo.get(PayrollRun, intent.payroll_run_id) do
      %{status: "paying"} -> :ok
      %{status: status} -> {:error, {:run_not_paying, status}}
      nil -> {:error, :not_found}
    end
  end

  # --- Execute payment ---

  defp attempt_payment(%{status: "processing"} = intent) do
    attempt_number = intent.retry_count + 1

    case get_attempt(intent.id, attempt_number) do
      %PaymentAttempt{status: "succeeded"} ->
        resume_after_provider_success(intent, attempt_number)

      %PaymentAttempt{status: "failed"} = attempt ->
        resume_after_provider_failure(intent, attempt.error)

      nil ->
        {:ok, :already_processing}
    end
  end

  defp attempt_payment(%{status: "pending"} = intent) do
    attempt_number = intent.retry_count + 1

    case get_attempt(intent.id, attempt_number) do
      %PaymentAttempt{status: "succeeded"} ->
        resume_after_provider_success(intent, attempt_number)

      %PaymentAttempt{status: "failed"} = attempt ->
        resume_after_provider_failure(intent, attempt.error)

      nil ->
        case claim_pending_intent(intent, attempt_number) do
          {:ok, claimed} -> perform_payment_attempt(claimed, attempt_number)
          {:error, :already_claimed} -> {:ok, :already_processing}
        end
    end
  end

  defp attempt_payment(intent), do: {:error, {:invalid_status, intent.status}}

  defp claim_pending_intent(intent, attempt_number) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    key = idempotency_key(intent.id, attempt_number)

    {claimed_count, _} =
      PayrollIntent
      |> where([i], i.id == ^intent.id and i.status == "pending")
      |> Repo.update_all(
        set: [
          idempotency_key: key,
          status: "processing",
          updated_at: now
        ]
      )

    case claimed_count do
      1 -> {:ok, Repo.get!(PayrollIntent, intent.id)}
      0 -> {:error, :already_claimed}
    end
  end

  defp perform_payment_attempt(intent, attempt_number) do
    result = GlobalPayroll.Payments.MockPaymentProvider.call(intent)

    with {:ok, _} <- record_attempt(intent, attempt_number, result),
         {:ok, intent} <- persist_provider_result(intent, result) do
      dispatch_provider_result(intent, result)
    end
  end

  defp persist_provider_result(intent, {:ok, provider_id}) do
    intent
    |> PayrollIntent.changeset(%{provider_payment_id: provider_id})
    |> Repo.update()
  end

  defp persist_provider_result(intent, {:error, _}), do: {:ok, intent}

  defp dispatch_provider_result(intent, {:ok, _}) do
    dispatch_success_result(intent)
  end

  defp dispatch_provider_result(intent, {:error, reason}) do
    dispatch_failure_result(intent, reason)
  end

  defp dispatch_success_result(intent) do
    enqueue_result(%{"intent_id" => intent.id, "status" => "succeeded"})
  end

  defp dispatch_failure_result(intent, reason) do
    enqueue_result(%{
      "intent_id" => intent.id,
      "status" => "failed",
      "error" => to_string(reason)
    })
  end

  defp enqueue_result(payload) do
    case Queue.enqueue_payment_result(payload) do
      :ok -> {:ok, :dispatched}
      {:error, reason} -> {:error, {:sqs_enqueue_failed, reason}}
    end
  end

  # --- Resume after redelivery / reconciliation ---

  defp resume_after_provider_success(intent, attempt_number) do
    intent = Repo.get!(PayrollIntent, intent.id)
    provider_id = intent.provider_payment_id || mock_provider_id(intent, attempt_number)

    intent =
      if intent.provider_payment_id do
        intent
      else
        Repo.update!(PayrollIntent.changeset(intent, %{provider_payment_id: provider_id}))
      end

    dispatch_success_result(intent)
  end

  defp resume_after_provider_failure(intent, error) do
    dispatch_failure_result(intent, error || "payment provider timeout")
  end

  defp mock_provider_id(intent, attempt_number) do
    key = intent.idempotency_key || idempotency_key(intent.id, attempt_number)
    "mock-provider-#{key}"
  end

  defp idempotency_key(intent_id, attempt_number), do: "intent-#{intent_id}-attempt-#{attempt_number}"

  # --- Attempts ---

  defp record_attempt(intent, attempt_number, result) do
    status = if match?({:ok, _}, result), do: "succeeded", else: "failed"
    error = if match?({:error, _}, result), do: elem(result, 1), else: nil

    %PaymentAttempt{}
    |> PaymentAttempt.changeset(%{
      payroll_intent_id: intent.id,
      attempt_number: attempt_number,
      status: status,
      error: error,
      attempted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
    |> case do
      {:ok, attempt} ->
        {:ok, attempt}

      {:error, %Ecto.Changeset{}} ->
        case get_attempt(intent.id, attempt_number) do
          %PaymentAttempt{} = attempt -> {:ok, attempt}
          nil -> {:error, :attempt_insert_failed}
        end
    end
  end

  defp get_attempt(intent_id, attempt_number) do
    Repo.get_by(PaymentAttempt, payroll_intent_id: intent_id, attempt_number: attempt_number)
  end

  # --- Result handling ---

  defp on_success(intent) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.run(:lock, fn _repo, _ ->
      locked = lock_intent(intent.id)

      case guard_already_settled(locked) do
        :ok -> {:ok, locked}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Multi.run(:run, fn _repo, %{lock: locked} ->
      {:ok, Repo.get!(PayrollRun, locked.payroll_run_id)}
    end)
    |> Multi.update(:intent, fn %{lock: locked} ->
      PayrollIntent.changeset(locked, %{status: "completed"})
    end)
    |> Multi.run(:ledger, fn _repo, %{lock: locked} ->
      Ledger.payroll_deduction(
        locked.company_id,
        Decimal.add(locked.net_salary, locked.platform_fee),
        locked.id,
        "Payroll payment for employee #{locked.employee_id}"
      )
    end)
    |> Multi.insert(:payslip, fn %{lock: locked, run: run} ->
      Payslip.changeset(%Payslip{}, %{
        payroll_intent_id: locked.id,
        employee_id: locked.employee_id,
        pay_period: run.pay_period,
        gross_salary: locked.gross_salary,
        income_tax: locked.income_tax,
        social_security: locked.social_security,
        net_salary: locked.net_salary,
        generated_at: now
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        {:ok, :completed}

      {:error, :lock, :already_settled, _} ->
        {:error, :already_settled}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp on_failure(intent, attempt_number, reason) do
    Repo.transaction(fn ->
      intent = lock_intent(intent.id)

      case guard_already_settled(intent) do
        {:error, :already_settled} ->
          :already_settled

        :ok ->
          if attempt_number < @max_retries do
            intent
            |> PayrollIntent.changeset(%{retry_count: attempt_number, status: "pending"})
            |> Repo.update!()

            case Queue.enqueue_execute_payment(intent.id) do
              :ok -> :retrying
              {:error, reason} -> Repo.rollback(reason)
            end
          else
            Repo.rollback({:max_retries, reason})
          end
      end
    end)
    |> case do
      {:ok, :retrying} ->
        {:ok, :retrying}

      {:ok, :already_settled} ->
        {:error, :already_settled}

      {:error, {:max_retries, reason}} ->
        on_max_retries(intent, reason)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp on_max_retries(intent, reason) do
    Multi.new()
    |> Multi.run(:lock, fn _repo, _ ->
      locked = lock_intent(intent.id)

      case guard_already_settled(locked) do
        :ok -> {:ok, locked}
        {:error, err} -> {:error, err}
      end
    end)
    |> Multi.update(:intent, fn %{lock: locked} ->
      PayrollIntent.changeset(locked, %{
        status: "failed",
        error: reason,
        retry_count: @max_retries
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        {:error, :failed}

      {:error, :lock, :already_settled, _} ->
        {:error, :already_settled}

      {:error, _step, err, _} ->
        {:error, err}
    end
  end

  defp provider_error(event), do: Map.get(event, "error", "provider reported failure")

  # --- Reconciliation ---

  defp stuck_cutoff do
    DateTime.utc_now() |> DateTime.add(-@reconcile_after_seconds, :second)
  end

  defp reconcile_processing_with_attempts do
    cutoff = stuck_cutoff()

    from(pi in PayrollIntent,
      join: r in PayrollRun,
      on: r.id == pi.payroll_run_id,
      join: pa in PaymentAttempt,
      on: pa.payroll_intent_id == pi.id and pa.attempt_number == pi.retry_count + 1,
      where: r.status == "paying" and pi.status in ["processing", "pending"],
      where: pi.updated_at < ^cutoff,
      select: {pi, pa}
    )
    |> Repo.all()
    |> Enum.each(fn {intent, attempt} ->
      intent = Repo.get!(PayrollIntent, intent.id)

      case attempt.status do
        "succeeded" -> resume_after_provider_success(intent, attempt.attempt_number)
        "failed" -> resume_after_provider_failure(intent, attempt.error)
      end
    end)
  end

  defp reconcile_processing_without_attempts do
    cutoff = stuck_cutoff()

    from(pi in PayrollIntent,
      join: r in PayrollRun,
      on: r.id == pi.payroll_run_id,
      left_join: pa in PaymentAttempt,
      on: pa.payroll_intent_id == pi.id,
      where: r.status == "paying" and pi.status == "processing" and is_nil(pa.id),
      where: pi.updated_at < ^cutoff,
      select: pi.id
    )
    |> Repo.all()
    |> Enum.each(fn intent_id ->
      intent =
        intent_id
        |> Repo.get!(PayrollIntent)

      intent
      |> PayrollIntent.changeset(%{status: "pending"})
      |> Repo.update!()

      Queue.enqueue_execute_payment(intent_id)
    end)
  end

  defp reconcile_pending_without_attempts do
    cutoff = stuck_cutoff()

    from(pi in PayrollIntent,
      join: r in PayrollRun,
      on: r.id == pi.payroll_run_id,
      left_join: pa in PaymentAttempt,
      on: pa.payroll_intent_id == pi.id,
      where: r.status == "paying" and pi.status == "pending" and is_nil(pa.id),
      where: pi.updated_at < ^cutoff,
      select: pi.id
    )
    |> Repo.all()
    |> Enum.each(&Queue.enqueue_execute_payment/1)
  end
end

defmodule GlobalPayroll.Payments.MockPaymentProvider do
  def call(intent) do
    if :rand.uniform(100) > 1 do
      {:ok, "mock-provider-#{intent.idempotency_key}"}
    else
      {:error, "payment provider timeout"}
    end
  end
end
