defmodule GlobalPayroll.Payroll.PayrollIntent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payroll_intents" do
    field(:gross_salary, :decimal)
    field(:income_tax, :decimal)
    field(:social_security, :decimal)
    field(:net_salary, :decimal)
    field(:platform_fee, :decimal)
    field(:status, :string, default: "pending")
    field(:error, :string)
    field(:retry_count, :integer, default: 0)
    belongs_to(:company, GlobalPayroll.Companies.Company)
    belongs_to(:payroll_run, GlobalPayroll.Payroll.PayrollRun)
    belongs_to(:employee, GlobalPayroll.Employees.Employee)
    has_one(:payslip, GlobalPayroll.Payroll.Payslip)
    has_many(:payment_attempts, GlobalPayroll.Payment.PaymentAttempt)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payroll_intent, attrs) do
    payroll_intent
    |> cast(attrs, [
      :company_id,
      :payroll_run_id,
      :employee_id,
      :gross_salary,
      :income_tax,
      :social_security,
      :net_salary,
      :platform_fee,
      :status,
      :error,
      :retry_count
    ])
    |> validate_required([
      :company_id,
      :payroll_run_id,
      :employee_id,
      :gross_salary,
      :income_tax,
      :social_security,
      :net_salary,
      :platform_fee
    ])
    |> validate_inclusion(:status, ["pending", "processing", "completed", "failed"])
    |> validate_number(:retry_count, greater_than_or_equal_to: 0, less_than_or_equal_to: 3)
    |> unique_constraint([:payroll_run_id, :employee_id])
  end
end
