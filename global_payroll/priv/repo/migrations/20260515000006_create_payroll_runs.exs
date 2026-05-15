defmodule GlobalPayroll.Repo.Migrations.CreatePayrollRuns do
  use Ecto.Migration

  def change do
    create table(:payroll_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      add :pay_period, :string, null: false  # e.g. "2025-05"
      add :status, :string, null: false, default: "draft"
      # draft | calculating | pending_approval | approved | paying | completed | failed
      add :error, :string                    # nullable — reason the run failed
      add :total_amount, :decimal, precision: 18, scale: 2  # set after calculating
      add :ran_at, :utc_datetime             # nullable — when the run was executed

      timestamps()
    end

    # prevents duplicate runs for the same company + period
    create unique_index(:payroll_runs, [:company_id, :pay_period])
    create index(:payroll_runs, [:company_id])
  end
end
