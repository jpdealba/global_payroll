defmodule GlobalPayrollWeb.CompanyTransactionController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.{Companies, Ledger}

  def index(conn, %{"company_id" => company_id} = params) do
    {transactions, next_cursor} = Companies.list_transactions(company_id, params["cursor"])
    render(conn, :index, transactions: transactions, next_cursor: next_cursor)
  end

  def deposit(conn, %{"company_id" => company_id, "amount" => amount, "description" => description}) do
    reference_id = Ecto.UUID.generate()

    case Ledger.deposit(company_id, amount, reference_id, description) do
      {:ok, transaction} -> conn |> put_status(:created) |> render(:show, transaction: transaction)
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end
end
