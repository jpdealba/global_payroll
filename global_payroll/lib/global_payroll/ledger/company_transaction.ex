defmodule GlobalPayroll.Ledger.CompanyTransaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "company_transactions" do
    belongs_to(:company, GlobalPayroll.Companies.Company)
    field(:amount, :decimal)
    field(:type, :string)
    field(:reference_id, :binary_id)
    field(:description, :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(company_transaction, attrs) do
    company_transaction
    |> cast(attrs, [:company_id, :amount, :type, :reference_id, :description])
    |> validate_required([:company_id, :amount, :type, :description])
    |> validate_inclusion(:type, ["deposit", "payroll_deduction", "refund"])
  end
end
