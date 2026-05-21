defmodule GlobalPayroll.Taxes do
  alias GlobalPayroll.Taxes.CountryTaxRule
  alias GlobalPayroll.{Pagination, Repo}

  def list_country_tax_rules(cursor \\ nil, per_page \\ 20) do
    CountryTaxRule
    |> Pagination.paginate(cursor, per_page)
    |> Repo.all()
    |> then(&{&1, Pagination.next_cursor(&1, per_page)})
  end

  def get_country_tax_rule(country_code) do
    CountryTaxRule |> Repo.get_by(country_code: country_code)
  end

  def create_country_tax_rule(attrs) do
    %CountryTaxRule{} |> CountryTaxRule.changeset(attrs) |> Repo.insert()
  end

  def update_country_tax_rule(id, attrs) do
    case Repo.get(CountryTaxRule, id) do
      nil -> {:error, :not_found}
      rule -> rule |> CountryTaxRule.changeset(attrs) |> Repo.update()
    end
  end
end
