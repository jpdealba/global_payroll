defmodule GlobalPayroll.Payments do
  import Ecto.Query
  alias Ecto.Multi
  alias GlobalPayroll.Payments.PaymentAttempt
  alias GlobalPayroll.Payrolls.{PayrollIntent, PayrollRun, Payslip, Invoice}
  alias GlobalPayroll.{Repo, Ledger, Queue}

  @max_retries 3

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

  def execute_payment(intent_id) do
    with {:ok, intent} <- fetch_intent(intent_id),
         :ok <- guard_already_settled(intent) do
      attempt_payment(intent)
    end
  end

  # --- Private ---

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

  # If the intent is already completed or failed, there is nothing to do.
  # Broadway may redeliver a message if the worker crashes after processing but before acking.
  defp guard_already_settled(%{status: status}) when status in ["completed", "failed"],
    do: {:error, :already_settled}

  defp guard_already_settled(_), do: :ok

  # Calls the mock provider and records the attempt.
  # On success: marks intent completed and records a ledger deduction.
  # On failure: retries up to @max_retries. After that, marks failed and records a refund.
  # Called by ResultsWorker after dequeuing from payment-results.
  def process_result(%{"intent_id" => intent_id, "status" => "succeeded"}) do
    with {:ok, intent} <- fetch_intent(intent_id),
         :ok <- guard_already_settled(intent) do
      on_success(intent)
    end
  end

  def process_result(%{"intent_id" => intent_id, "status" => "failed", "error" => error}) do
    with {:ok, intent} <- fetch_intent(intent_id),
         :ok <- guard_already_settled(intent) do
      on_failure(intent, intent.retry_count + 1, error)
    end
  end

  defp attempt_payment(intent) do
    attempt_number = intent.retry_count + 1
    key = "intent-#{intent.id}-attempt-#{intent.retry_count}"

    updated_intent =
      intent
      |> PayrollIntent.changeset(%{idempotency_key: key})
      |> Repo.update!()

    result = GlobalPayroll.Payments.MockPaymentProvider.call(updated_intent)
    record_attempt(intent, attempt_number, result)

    case result do
      {:ok, provider_id} ->
        intent
        |> PayrollIntent.changeset(%{provider_payment_id: provider_id})
        |> Repo.update!()

        Queue.enqueue_payment_result(%{"intent_id" => intent.id, "status" => "succeeded"})

      {:error, reason} ->
        Queue.enqueue_payment_result(%{"intent_id" => intent.id, "status" => "failed", "error" => reason})
    end

    {:ok, :dispatched}
  end

  # Records every attempt in payment_attempts for full audit trail.
  # unique_constraint on (payroll_intent_id, attempt_number) prevents duplicate records.
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
  end

  # Payment succeeded — mark intent completed, debit the company balance, and generate payslip.
  # All three writes happen in one transaction. After it commits, check if the run is fully settled.
  defp on_success(intent) do
    run = Repo.get!(PayrollRun, intent.payroll_run_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.update(:intent, PayrollIntent.changeset(intent, %{status: "completed"}))
    |> Multi.run(:ledger, fn _repo, _changes ->
      Ledger.payroll_deduction(
        intent.company_id,
        intent.net_salary,
        intent.id,
        "Payroll payment for employee #{intent.employee_id}"
      )
    end)
    |> Multi.insert(:payslip, Payslip.changeset(%Payslip{}, %{
      payroll_intent_id: intent.id,
      employee_id: intent.employee_id,
      pay_period: run.pay_period,
      gross_salary: intent.gross_salary,
      income_tax: intent.income_tax,
      social_security: intent.social_security,
      net_salary: intent.net_salary,
      generated_at: now
    }))
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        maybe_close_run(run)
        {:ok, :completed}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  # Payment failed — decide whether to retry or give up.
  defp on_failure(intent, attempt_number, reason) do
    if attempt_number < @max_retries do
      intent
      |> PayrollIntent.changeset(%{retry_count: attempt_number})
      |> Repo.update()

      Queue.enqueue_execute_payment(intent.id)
      {:ok, :retrying}
    else
      on_max_retries(intent, reason)
    end
  end

  # Max retries reached — mark intent failed and refund the company.
  # After committing, check if the run is fully settled (other employees may still be in flight).
  defp on_max_retries(intent, reason) do
    Multi.new()
    |> Multi.update(
      :intent,
      PayrollIntent.changeset(intent, %{
        status: "failed",
        error: reason,
        retry_count: @max_retries
      })
    )
    |> Multi.run(:ledger, fn _repo, _changes ->
      Ledger.refund(
        intent.company_id,
        intent.net_salary,
        intent.id,
        "Refund for failed payment to employee #{intent.employee_id}"
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        run = Repo.get!(PayrollRun, intent.payroll_run_id)
        maybe_close_run(run)
        {:error, :failed}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  # Checks if every intent in the run has reached a terminal state using a COUNT query —
  # avoids loading all intents into memory, which is critical at scale.
  defp maybe_close_run(run) do
    pending_count =
      Repo.one(
        from i in PayrollIntent,
          where: i.payroll_run_id == ^run.id and i.status not in ["completed", "failed"],
          select: count(i.id)
      )

    if pending_count == 0, do: generate_invoice(run)
  end

  # Computes all invoice totals with a single aggregate query on the DB side —
  # never loads individual intent rows into memory regardless of employee count.
  defp generate_invoice(run) do
    agg =
      Repo.one(
        from i in PayrollIntent,
          where: i.payroll_run_id == ^run.id and i.status == "completed",
          select: %{
            total_gross: sum(i.gross_salary),
            total_taxes: sum(i.income_tax) + sum(i.social_security),
            total_fees: sum(i.platform_fee)
          }
      )

    total_gross = agg.total_gross || Decimal.new(0)
    total_taxes = agg.total_taxes || Decimal.new(0)
    total_fees = agg.total_fees || Decimal.new(0)

    Multi.new()
    |> Multi.insert(:invoice, Invoice.changeset(%Invoice{}, %{
      company_id: run.company_id,
      payroll_run_id: run.id,
      total_gross_salaries: total_gross,
      total_taxes_withheld: total_taxes,
      total_platform_fees: total_fees,
      total_amount: Decimal.add(total_gross, total_fees),
      issued_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }))
    |> Multi.update(:run, PayrollRun.changeset(run, %{status: "completed"}))
    |> Repo.transaction()
  end
end

# Mock payment provider — simulates a real provider with random success/failure.
# Replace this module with a real HTTP client when integrating with Wise or a bank.
defmodule GlobalPayroll.Payments.MockPaymentProvider do
  def call(intent) do
    if :rand.uniform(10) > 1 do
      {:ok, "mock-provider-#{intent.idempotency_key}"}
    else
      {:error, "payment provider timeout"}
    end
  end
end
