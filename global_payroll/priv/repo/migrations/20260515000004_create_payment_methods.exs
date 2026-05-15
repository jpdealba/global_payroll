defmodule GlobalPayroll.Repo.Migrations.CreatePaymentMethods do
  use Ecto.Migration

  def change do
    create table(:payment_methods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :employee_id, references(:employees, type: :binary_id, on_delete: :restrict), null: false
      add :bank_name, :string, null: false
      add :account_holder, :string, null: false
      add :account_number, :string, null: false
      add :bank_code, :string, null: false      # routing number, CLABE, IBAN, etc.
      add :is_default, :boolean, null: false, default: false

      timestamps()
    end

    create index(:payment_methods, [:employee_id])
  end
end
