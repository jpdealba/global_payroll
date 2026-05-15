defmodule GlobalPayroll.Companies.Company do
  use Ecto.Schema
  import Ecto.Changeset

  schema "companies" do
    field(:name, :string)
    field(:country, :string)
    field(:billing_email, :string)
    field(:status, :string, default: "pending")
    has_many(:employees, GlobalPayroll.Employees.Employee)
    has_many(:company_transactions, GlobalPayroll.Ledger.CompanyTransaction)
    has_many(:payroll_runs, GlobalPayroll.Payroll.PayrollRun)
    has_many(:invoices, GlobalPayroll.Payroll.Invoice)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :country, :billing_email, :status])
    |> validate_required([:name, :country, :billing_email])
    |> validate_inclusion(:status, ["pending", "active", "inactive"])
    |> unique_constraint(:billing_email)
  end
end
