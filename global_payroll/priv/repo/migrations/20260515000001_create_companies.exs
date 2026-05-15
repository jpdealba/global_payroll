defmodule GlobalPayroll.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def change do
    create table(:companies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :country, :string, null: false        # ISO code e.g. "MX"
      add :billing_email, :string, null: false
      add :status, :string, null: false, default: "pending"  # pending | active | inactive

      timestamps()
    end

    create unique_index(:companies, [:billing_email])
    create index(:companies, [:inserted_at, :id])
  end
end
