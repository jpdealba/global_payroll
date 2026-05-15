defmodule GlobalPayroll.Payroll.Payslip do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payslips" do
    field(:gross_salary, :decimal)
    field(:income_tax, :decimal)
    field(:social_security, :decimal)
    field(:net_salary, :decimal)
    field(:pay_period, :string)
    field(:generated_at, :utc_datetime)
    belongs_to(:payroll_intent, GlobalPayroll.Payroll.PayrollIntent)
    belongs_to(:employee, GlobalPayroll.Employees.Employee)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payslip, attrs) do
    payslip
    |> cast(attrs, [
      :payroll_intent_id,
      :employee_id,
      :pay_period,
      :gross_salary,
      :income_tax,
      :social_security,
      :net_salary,
      :generated_at
    ])
    |> validate_required([
      :payroll_intent_id,
      :employee_id,
      :pay_period,
      :gross_salary,
      :income_tax,
      :social_security,
      :net_salary,
      :generated_at
    ])
    |> validate_number(:gross_salary, greater_than_or_equal_to: 0)
    |> validate_number(:income_tax, greater_than_or_equal_to: 0)
    |> validate_number(:social_security, greater_than_or_equal_to: 0)
    |> validate_number(:net_salary, greater_than_or_equal_to: 0)
    |> unique_constraint([:payroll_intent_id, :employee_id])
  end
end
