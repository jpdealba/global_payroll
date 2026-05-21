defmodule GlobalPayrollWeb.CountryTaxRuleController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.Taxes

  def index(conn, params) do
    {rules, next_cursor} = Taxes.list_country_tax_rules(params["cursor"])
    render(conn, :index, rules: rules, next_cursor: next_cursor)
  end

  def update(conn, %{"id" => id} = params) do
    case Taxes.update_country_tax_rule(id, Map.drop(params, ["id"])) do
      {:ok, rule} ->
        render(conn, :show, rule: rule)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end
end
