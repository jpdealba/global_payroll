defmodule GlobalPayroll.Repo.Migrations.CreateCompanyTransactions do
  use Ecto.Migration

  # Append-only ledger — rows are never updated or deleted.
  # The company balance is always: SELECT SUM(amount) WHERE company_id = x
  def change do
    create table(:company_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      # positive = credit, negative = debit
      add :amount, :decimal, null: false, precision: 18, scale: 2
      # deposit | payroll_deduction | refund
      add :type, :string, null: false
      # nullable — payroll_run_id or payroll_intent_id
      add :reference_id, :binary_id
      add :description, :string, null: false

      # ledger rows are never updated
      timestamps(updated_at: false)
    end

    create index(:company_transactions, [:company_id])
  end
end
