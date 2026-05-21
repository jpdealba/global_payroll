defmodule GlobalPayroll.Repo.Migrations.CreatePayrollRuns do
  use Ecto.Migration

  def change do
    create table(:payroll_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      # e.g. "2025-05"
      add :pay_period, :string, null: false
      add :status, :string, null: false, default: "draft"
      # draft | calculating | pending_approval | approved | paying | completed | failed
      # nullable — reason the run failed
      add :error, :string
      # set after calculating
      add :total_amount, :decimal, precision: 18, scale: 2
      # nullable — when the run was executed
      add :ran_at, :utc_datetime

      timestamps()
    end

    # prevents duplicate runs for the same company + period
    create unique_index(:payroll_runs, [:company_id, :pay_period])
    create index(:payroll_runs, [:company_id])
  end
end
