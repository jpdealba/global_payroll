defmodule GlobalPayroll.Companies do
  import Ecto.Query
  alias GlobalPayroll.Companies.Company
  alias GlobalPayroll.Ledgers.CompanyTransaction
  alias GlobalPayroll.{Pagination, Repo}

  def list_companies(cursor \\ nil, per_page \\ 20) do
    Company
    |> Pagination.paginate(cursor, per_page)
    |> Repo.all()
    |> then(&{&1, Pagination.next_cursor(&1, per_page)})
  end

  def get_company(id) do
    Company |> Repo.get(id)
  end

  def create_company(attrs) do
    %Company{} |> Company.changeset(attrs) |> Repo.insert()
  end

  def update_company(id, attrs) do
    case Repo.get(Company, id) do
      nil -> {:error, :not_found}
      company -> company |> Company.changeset(attrs) |> Repo.update()
    end
  end

  def get_company_balance(company_id) do
    CompanyTransaction
    |> where([t], t.company_id == ^company_id)
    |> select([t], coalesce(sum(t.amount), ^Decimal.new("0")))
    |> Repo.one()
  end

  def list_transactions(company_id, cursor \\ nil, per_page \\ 20) do
    CompanyTransaction
    |> where([t], t.company_id == ^company_id)
    |> Pagination.paginate(cursor, per_page)
    |> Repo.all()
    |> then(&{&1, Pagination.next_cursor(&1, per_page)})
  end
end
