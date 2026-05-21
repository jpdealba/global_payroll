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

  def list_transactions(company_id, cursor \\ nil, per_page \\ 25, type \\ nil) do
    txs =
      CompanyTransaction
      |> where([t], t.company_id == ^company_id)
      |> then(fn q -> if type, do: where(q, [t], t.type == ^type), else: q end)
      |> apply_tx_cursor(cursor)
      |> order_by([t], desc: t.inserted_at, desc: t.id)
      |> limit(^per_page)
      |> Repo.all()

    {txs, tx_next_cursor(txs, per_page)}
  end

  defp apply_tx_cursor(query, nil), do: query

  defp apply_tx_cursor(query, {ts, id}) do
    where(query, [t], t.inserted_at < ^ts or (t.inserted_at == ^ts and t.id < ^id))
  end

  defp tx_next_cursor(results, per_page) when length(results) < per_page, do: nil

  defp tx_next_cursor(results, _) do
    last = List.last(results)
    {last.inserted_at, last.id}
  end
end
