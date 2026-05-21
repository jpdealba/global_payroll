# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Safe to run multiple times — uses on_conflict: :nothing.

alias GlobalPayroll.Taxes.CountryTaxRule
alias GlobalPayroll.Repo

countries = [
  %{
    country_code: "MX",
    country_name: "Mexico",
    income_tax_rate: "0.18",
    social_security_rate: "0.03",
    currency: "MXN"
  },
  %{
    country_code: "US",
    country_name: "United States",
    income_tax_rate: "0.22",
    social_security_rate: "0.0765",
    currency: "USD"
  },
  %{
    country_code: "ES",
    country_name: "Spain",
    income_tax_rate: "0.24",
    social_security_rate: "0.07",
    currency: "EUR"
  }
]

Enum.each(countries, fn attrs ->
  %CountryTaxRule{}
  |> CountryTaxRule.changeset(attrs)
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :country_code)
end)
