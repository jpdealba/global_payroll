defmodule GlobalPayroll.Repo.Migrations.AddCompanyIdToPayrollIntents do
  use Ecto.Migration

  def up do
    alter table(:payroll_intents) do
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict)
    end

    execute("""
    UPDATE payroll_intents AS intent
    SET company_id = run.company_id
    FROM payroll_runs AS run
    WHERE intent.payroll_run_id = run.id
      AND intent.company_id IS NULL
    """)

    execute("ALTER TABLE payroll_intents ALTER COLUMN company_id SET NOT NULL")

    create index(:payroll_intents, [:company_id])
  end

  def down do
    drop index(:payroll_intents, [:company_id])

    alter table(:payroll_intents) do
      remove :company_id
    end
  end
end
