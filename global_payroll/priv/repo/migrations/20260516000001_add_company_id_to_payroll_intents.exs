defmodule GlobalPayroll.Repo.Migrations.AddCompanyIdToPayrollIntents do
  use Ecto.Migration

  def change do
    alter table(:payroll_intents) do
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
    end

    create index(:payroll_intents, [:company_id])
  end
end
