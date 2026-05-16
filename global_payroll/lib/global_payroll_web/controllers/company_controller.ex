defmodule GlobalPayrollWeb.CompanyController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.Companies

  def index(conn, params) do
    {companies, next_cursor} = Companies.list_companies(params["cursor"])
    render(conn, :index, companies: companies, next_cursor: next_cursor)
  end

  def create(conn, params) do
    case Companies.create_company(params) do
      {:ok, company} -> conn |> put_status(:created) |> render(:show, company: company)
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Companies.update_company(id, Map.drop(params, ["id"])) do
      {:ok, company} -> render(conn, :show, company: company)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not found"})
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end
end
