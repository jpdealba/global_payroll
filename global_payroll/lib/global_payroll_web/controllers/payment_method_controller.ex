defmodule GlobalPayrollWeb.PaymentMethodController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.Employees

  def index(conn, %{"employee_id" => employee_id}) do
    methods = Employees.list_payment_methods(employee_id)
    render(conn, :index, methods: methods)
  end

  def create(conn, %{"employee_id" => employee_id} = params) do
    case Employees.add_payment_method(employee_id, Map.drop(params, ["employee_id"])) do
      {:ok, method} -> conn |> put_status(:created) |> render(:show, method: method)
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Employees.update_payment_method(id, Map.drop(params, ["id"])) do
      {:ok, method} -> render(conn, :show, method: method)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not found"})
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Employees.delete_payment_method(id) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not found"})
    end
  end
end
