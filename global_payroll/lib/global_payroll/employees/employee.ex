defmodule GlobalPayroll.Employees.Employee do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "employees" do
    field(:name, :string)
    field(:email, :string)
    field(:gross_salary, :decimal)
    field(:status, :string, default: "pending")
    belongs_to(:company, GlobalPayroll.Companies.Company)
    belongs_to(:country_tax_rule, GlobalPayroll.Taxes.CountryTaxRule, foreign_key: :country_tax_id)
    has_many(:payment_methods, GlobalPayroll.Employees.PaymentMethod)
    has_many(:payroll_intents, GlobalPayroll.Payrolls.PayrollIntent)
    has_many(:payslips, GlobalPayroll.Payrolls.Payslip)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(employee, attrs) do
    employee
    |> cast(attrs, [:name, :email, :gross_salary, :status, :company_id, :country_tax_id])
    |> validate_required([:name, :email, :country_tax_id])
    |> validate_inclusion(:status, ["pending", "active", "terminated"])
    |> unique_constraint(:email)
  end
end
