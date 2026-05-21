defmodule GlobalPayroll.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  # One invoice per payroll run. Immutable once issued.
  def change do
    create table(:invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false

      add :payroll_run_id, references(:payroll_runs, type: :binary_id, on_delete: :restrict),
        null: false

      add :total_gross_salaries, :decimal, null: false, precision: 18, scale: 2
      add :total_taxes_withheld, :decimal, null: false, precision: 18, scale: 2
      add :total_platform_fees, :decimal, null: false, precision: 18, scale: 2
      add :total_amount, :decimal, null: false, precision: 18, scale: 2
      # unpaid | paid
      add :status, :string, null: false, default: "unpaid"
      add :issued_at, :utc_datetime, null: false
      # nullable — set when payment is confirmed
      add :paid_at, :utc_datetime

      timestamps()
    end

    # one invoice per run — enforced at the DB level
    create unique_index(:invoices, [:payroll_run_id])
    create index(:invoices, [:company_id])
  end
end
