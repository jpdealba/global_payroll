defmodule GlobalPayrollWeb.EmployeeController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.{Employees, Payrolls}

  def index(conn, %{"company_id" => company_id} = params) do
    {employees, next_cursor} = Employees.list_employees_by_company(company_id, params["cursor"])
    render(conn, :index, employees: employees, next_cursor: next_cursor)
  end

  def index(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "company_id is required"})
  end

  def create(conn, params) do
    case Employees.create_employee(params) do
      {:ok, employee} ->
        conn |> put_status(:created) |> render(:show, employee: employee)

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Employees.update_employee(id, Map.drop(params, ["id"])) do
      {:ok, employee} ->
        render(conn, :show, employee: employee)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  def list_payslips(conn, %{"id" => employee_id}) do
    payslips = Payrolls.list_payslips_by_employee(employee_id)
    render(conn, :payslips, payslips: payslips)
  end
end
