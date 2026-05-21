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
         :ok <- guard_already_settled(intent) do #guard clause to avoid already settled intents (we don't want to try to execute a payment for an already settled intent)
      attempt_payment(intent)
    end
  end

  # Webhook from a real payment provider — not used with mock, kept for when we integrate a real provider
  # Almost the same as process_result,but we fetch by provider_id instead of intent_id
  def handle_webhook_event(%{"payment_id" => payment_id, "status" => status} = event) do
    with {:ok, intent} <- fetch_by_provider_id(payment_id),
         :ok <- guard_already_settled(intent) do
      case status do
        "succeeded" -> on_success(intent)
        "failed" -> on_max_retries(intent, Map.get(event, "error", "provider reported failure"))
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

  # Lock the intent for update to avoid race conditions
  defp lock_intent(id) do
    # We use it in the on_success and on_failure functions
    from(i in PayrollIntent, where: i.id == ^id, lock: "FOR UPDATE")
    |> Repo.one()
  end

  # Guard clause to avoid already settled intents
  defp guard_already_settled(%{status: status}) when status in ["completed", "failed"],
    do: {:error, :already_settled}

  # If the intent is not already settled, return :ok
  defp guard_already_settled(_), do: :ok

  # --- Execute payment ---
  defp attempt_payment(intent) do
    attempt_number = intent.retry_count + 1
    # Check if the attempt already exists
    # If it exists, check if it succeeded or failed
    # If it didn't exist, perform the payment attempt
    case get_attempt(intent.id, attempt_number) do
      %PaymentAttempt{status: "succeeded"} ->
        resume_after_provider_success(intent, attempt_number)

      %PaymentAttempt{status: "failed"} = attempt ->
        resume_after_provider_failure(intent, attempt.error)

      nil ->
        perform_payment_attempt(intent, attempt_number)
    end
  end

  defp perform_payment_attempt(intent, attempt_number) do
    # Generate an idempotency key to avoid duplicate attempts
    key = "intent-#{intent.id}-attempt-#{attempt_number}"

    intent =
      # Update the intent status to processing
      intent
      |> PayrollIntent.changeset(%{idempotency_key: key, status: "processing"})
      |> Repo.update!()


    result = GlobalPayroll.Payments.MockPaymentProvider.call(intent)
    # Save the result of the payment attempt, update the intent with the provider_payment_id and dispatch the result to the payment-results queue
    with {:ok, _} <- record_attempt(intent, attempt_number, result),
         {:ok, intent} <- persist_provider_result(intent, result) do
      dispatch_provider_result(intent, result)
    end
  end

  # If the payment provider succeeds, update the intent with the provider_payment_id
  defp persist_provider_result(intent, {:ok, provider_id}) do
    intent
    |> PayrollIntent.changeset(%{provider_payment_id: provider_id})
    |> Repo.update()
  end

  # If the payment provider fails, do nothing so we can retry the payment
  defp persist_provider_result(intent, {:error, _}), do: {:ok, intent}

  # If the payment provider succeeds, dispatch the success result to the payment-results queue
  defp dispatch_provider_result(intent, {:ok, _}) do
    dispatch_success_result(intent)
  end

  # If the payment provider fails, dispatch the failure result to the payment-results queue
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
    # If the intent has a provider_payment_id, use it, otherwise generate a mock provider_id
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
    key = intent.idempotency_key || "intent-#{intent.id}-attempt-#{attempt_number}"
    "mock-provider-#{key}"
  end

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
              {:error, reason} -> Repo.rollback(reason)  # undo the pending/retry_count update because the retry message was not enqueued
            end
          else
            Repo.rollback({:max_retries, reason}) # abort this retry flow so the caller can mark the intent as failed
          end
      end
    end)
    |> case do
      {:ok, :retrying} ->
        {:ok, :retrying}

      {:ok, :already_settled} ->
        {:error, :already_settled}

      {:error, {:max_retries, reason}} ->
        on_max_retries(intent, reason) # mark the intent as failed

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

  # --- Reconciliation ---
  # Calculate the cutoff time used to determine which intents are considered stuck
  defp stuck_cutoff do
    DateTime.utc_now() |> DateTime.add(-@reconcile_after_seconds, :second)
  end

  # Worker died after the provider responded but before the result was enqueued.
  # The attempt exists in DB — resume from its result instead of calling the provider again.
  defp reconcile_processing_with_attempts do
    cutoff = stuck_cutoff()

    from(pi in PayrollIntent,
      join: r in PayrollRun,
      on: r.id == pi.payroll_run_id,
      # join only the attempt for the current retry number
      join: pa in PaymentAttempt,
      on: pa.payroll_intent_id == pi.id and pa.attempt_number == pi.retry_count + 1,
      where: r.status == "paying" and pi.status in ["processing", "pending"],
      where: pi.updated_at < ^cutoff,
      select: {pi, pa}
    )
    |> Repo.all()
    |> Enum.each(fn {intent, attempt} ->
      # reload to get the freshest state in case another process touched it
      intent = Repo.get!(PayrollIntent, intent.id)
      case attempt.status do
        "succeeded" -> resume_after_provider_success(intent, attempt.attempt_number)
        "failed" -> resume_after_provider_failure(intent, attempt.error)
      end
    end)
  end

  # Worker died before calling the provider — no attempt exists.
  # Reset to "pending" and re-enqueue so it starts fresh.
  defp reconcile_processing_without_attempts do
    cutoff = stuck_cutoff()

    from(pi in PayrollIntent,
      join: r in PayrollRun,
      on: r.id == pi.payroll_run_id,
      # left_join + is_nil means no attempt exists for this intent
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

  # The SQS message was lost before the worker picked it up — intent never moved from "pending".
  # Re-enqueue directly, no status reset needed.
  defp reconcile_pending_without_attempts do
    cutoff = stuck_cutoff()

    from(pi in PayrollIntent,
      join: r in PayrollRun,
      on: r.id == pi.payroll_run_id,
      # left_join + is_nil means no attempt exists for this intent
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
