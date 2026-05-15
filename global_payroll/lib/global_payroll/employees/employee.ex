defmodule GlobalPayroll.Employees.Employee do
  use Ecto.Schema
  import Ecto.Changeset

  schema "employees" do
    field(:name, :string)
    field(:email, :string)
    field(:gross_salary, :decimal)
    field(:status, :string, default: "pending")
    belongs_to(:company, GlobalPayroll.Companies.Company)
    belongs_to(:country_tax_rule, GlobalPayroll.Taxes.CountryTaxRule)
    has_many(:payment_methods, GlobalPayroll.Employees.PaymentMethod)
    has_many(:payroll_intents, GlobalPayroll.Payroll.PayrollIntent)
    has_many(:payslips, GlobalPayroll.Payroll.Payslip)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(employee, attrs) do
    employee
    |> cast(attrs, [:name, :email, :gross_salary, :status, :company_id, :country_tax_rule_id])
    |> validate_required([:name, :email, :country_tax_rule_id])
    |> validate_inclusion(:status, ["pending", "active", "terminated"])
    |> unique_constraint(:email)
  end
end
