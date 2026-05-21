defmodule GlobalPayroll.Repo.Migrations.AddPendingCountAndIndexToPayroll do
  use Ecto.Migration

  def change do
    alter table(:payroll_runs) do
      add :pending_count, :integer
    end

    create index(:payroll_intents, [:payroll_run_id, :status])
  end
end
