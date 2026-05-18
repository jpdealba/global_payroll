defmodule GlobalPayroll.Repo.Migrations.RemovePendingCountFromPayrollRuns do
  use Ecto.Migration

  def change do
    alter table(:payroll_runs) do
      remove :pending_count, :integer
    end
  end
end
