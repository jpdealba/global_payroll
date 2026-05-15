defmodule GlobalPayroll.Taxes.CountryTaxRule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "country_tax_rules" do
    field(:country_code, :string)
    field(:country_name, :string)
    field(:income_tax_rate, :decimal)
    field(:social_security_rate, :decimal)
    field(:currency, :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(country_tax_rule, attrs) do
    country_tax_rule
    |> cast(attrs, [
      :country_code,
      :country_name,
      :income_tax_rate,
      :social_security_rate,
      :currency
    ])
    |> validate_required([
      :country_code,
      :country_name,
      :income_tax_rate,
      :social_security_rate,
      :currency
    ])
    |> unique_constraint(:country_code)
  end
end
