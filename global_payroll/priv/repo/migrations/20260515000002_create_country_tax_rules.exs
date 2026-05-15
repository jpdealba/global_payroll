defmodule GlobalPayroll.Repo.Migrations.CreateCountryTaxRules do
  use Ecto.Migration

  def change do
    create table(:country_tax_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :country_code, :string, null: false   # ISO code e.g. "MX", "US", "ES"
      add :country_name, :string, null: false
      add :income_tax_rate, :decimal, null: false, precision: 5, scale: 4   # e.g. 0.2500 = 25%
      add :social_security_rate, :decimal, null: false, precision: 5, scale: 4  # e.g. 0.0650 = 6.5%
      add :currency, :string, null: false       # e.g. "MXN", "USD", "EUR"

      timestamps(updated_at: false)             # rules are never edited, only inserted
    end

    create unique_index(:country_tax_rules, [:country_code])
  end
end
