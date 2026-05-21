defmodule GlobalPayroll.Repo.Migrations.CreatePayslips do
  use Ecto.Migration

  # Immutable once created — the employee-facing pay document.
  def change do
    create table(:payslips, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :payroll_intent_id,
          references(:payroll_intents, type: :binary_id, on_delete: :restrict),
          null: false

      add :employee_id, references(:employees, type: :binary_id, on_delete: :restrict),
        null: false

      # denormalized for easy querying e.g. "2025-05"
      add :pay_period, :string, null: false
      add :gross_salary, :decimal, null: false, precision: 18, scale: 2
      add :income_tax, :decimal, null: false, precision: 18, scale: 2
      add :social_security, :decimal, null: false, precision: 18, scale: 2
      add :net_salary, :decimal, null: false, precision: 18, scale: 2
      add :generated_at, :utc_datetime, null: false

      # immutable — never updated
      timestamps(updated_at: false)
    end

    create index(:payslips, [:employee_id])
    create index(:payslips, [:payroll_intent_id])
  end
end
