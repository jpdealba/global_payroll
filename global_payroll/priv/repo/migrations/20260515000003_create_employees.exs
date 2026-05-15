defmodule GlobalPayroll.Repo.Migrations.CreateEmployees do
  use Ecto.Migration

  def change do
    create table(:employees, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      add :country_tax_id, references(:country_tax_rules, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :email, :string, null: false
      add :gross_salary, :decimal, null: false, precision: 18, scale: 2  # monthly gross in local currency
      add :status, :string, null: false, default: "pending"  # pending | active | terminated

      timestamps()
    end

    create unique_index(:employees, [:email])
    create index(:employees, [:company_id])
  end
end
