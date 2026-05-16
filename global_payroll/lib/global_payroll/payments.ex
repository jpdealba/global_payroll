defmodule GlobalPayroll.Payments do
  alias Ecto.Multi
  alias GlobalPayroll.Payments.PaymentAttempt
  alias GlobalPayroll.Payrolls.PayrollIntent
  alias GlobalPayroll.{Repo, Ledger}

  @max_retries 3

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

  # If the intent is already completed or failed, there is nothing to do.
  # Broadway may redeliver a message if the worker crashes after processing but before acking.
  defp guard_already_settled(%{status: status}) when status in ["completed", "failed"],
    do: {:error, :already_settled}

  defp guard_already_settled(_), do: :ok

  # Calls the mock provider and records the attempt.
  # On success: marks intent completed and records a ledger deduction.
  # On failure: retries up to @max_retries. After that, marks failed and records a refund.
  defp attempt_payment(intent) do
    attempt_number = intent.retry_count + 1
    key = "intent-#{intent.id}-attempt-#{intent.retry_count}"

    updated_intent =
      intent
      |> PayrollIntent.changeset(%{idempotency_key: key})
      |> Repo.update!()

    result = MockPaymentProvider.call(updated_intent)
    record_attempt(intent, attempt_number, result)

    case result do
      {:ok, provider_id} ->
        intent
        |> PayrollIntent.changeset(%{provider_payment_id: provider_id})
        |> Repo.update!()

        on_success(intent)

      {:error, reason} ->
        on_failure(intent, attempt_number, reason)
    end
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

  # Payment succeeded — mark intent completed and debit the company balance.
  # Both writes happen in one transaction: if the ledger insert fails, the intent stays pending.
  defp on_success(intent) do
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
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, :completed}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  # Payment failed — decide whether to retry or give up.
  defp on_failure(intent, attempt_number, reason) do
    if attempt_number < @max_retries do
      # Increment retry_count and return error so Broadway requeues the message.
      intent
      |> PayrollIntent.changeset(%{retry_count: attempt_number})
      |> Repo.update()

      {:error, :retry}
    else
      on_max_retries(intent, reason)
    end
  end

  # Max retries reached — mark intent failed and refund the company.
  # The refund returns the reserved funds so the company is not charged for a failed payment.
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
      {:ok, _} -> {:error, :failed}
      {:error, _step, reason, _} -> {:error, reason}
    end
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
