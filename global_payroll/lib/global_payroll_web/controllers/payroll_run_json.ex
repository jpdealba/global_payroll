defmodule GlobalPayrollWeb.PayrollRunJSON do
  def index(%{runs: runs, next_cursor: next_cursor}) do
    %{data: Enum.map(runs, &run_data/1), next_cursor: next_cursor}
  end

  def show(%{run: run}), do: %{data: run_data(run)}

  def intents(%{intents: intents}), do: %{data: Enum.map(intents, &intent_data/1)}

  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp run_data(run) do
    %{
      id: run.id,
      company_id: run.company_id,
      pay_period: run.pay_period,
      status: run.status,
      error: run.error,
      total_amount: run.total_amount,
      ran_at: run.ran_at,
      inserted_at: run.inserted_at,
      updated_at: run.updated_at
    }
  end

  defp intent_data(intent) do
    %{
      id: intent.id,
      payroll_run_id: intent.payroll_run_id,
      employee_id: intent.employee_id,
      gross_salary: intent.gross_salary,
      income_tax: intent.income_tax,
      social_security: intent.social_security,
      net_salary: intent.net_salary,
      platform_fee: intent.platform_fee,
      status: intent.status,
      error: intent.error,
      retry_count: intent.retry_count,
      provider_payment_id: intent.provider_payment_id,
      inserted_at: intent.inserted_at,
      updated_at: intent.updated_at
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
