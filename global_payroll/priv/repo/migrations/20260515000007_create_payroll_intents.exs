defmodule GlobalPayroll.Repo.Migrations.CreatePayrollIntents do
  use Ecto.Migration

  # One record per employee per run. Represents the individual payment to one employee.
  def change do
    create table(:payroll_intents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payroll_run_id, references(:payroll_runs, type: :binary_id, on_delete: :restrict), null: false
      add :employee_id, references(:employees, type: :binary_id, on_delete: :restrict), null: false
      add :gross_salary, :decimal, null: false, precision: 18, scale: 2   # snapshot — not a live reference
      add :income_tax, :decimal, null: false, precision: 18, scale: 2
      add :social_security, :decimal, null: false, precision: 18, scale: 2
      add :net_salary, :decimal, null: false, precision: 18, scale: 2
      add :platform_fee, :decimal, null: false, precision: 18, scale: 2
      add :status, :string, null: false, default: "pending"  # pending | processing | completed | failed
      add :error, :string                    # nullable — error message if failed
      add :retry_count, :integer, null: false, default: 0

      timestamps()
    end

    # prevents paying the same employee twice in a run
    create unique_index(:payroll_intents, [:payroll_run_id, :employee_id])
    create index(:payroll_intents, [:payroll_run_id])
  end
end
