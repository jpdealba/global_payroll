defmodule GlobalPayroll.Repo.Migrations.CreatePaymentAttempts do
  use Ecto.Migration

  # One record per payment attempt. Tracks the full history of retries per payroll_intent.
  def change do
    create table(:payment_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :payroll_intent_id,
          references(:payroll_intents, type: :binary_id, on_delete: :restrict),
          null: false

      # 1, 2, or 3
      add :attempt_number, :integer, null: false
      # succeeded | failed
      add :status, :string, null: false
      # nullable — provider error message
      add :error, :string
      add :attempted_at, :utc_datetime, null: false

      timestamps()
    end

    # prevents recording the same attempt twice (idempotency)
    create unique_index(:payment_attempts, [:payroll_intent_id, :attempt_number])
    create index(:payment_attempts, [:payroll_intent_id])
  end
end
