defmodule GlobalPayrollWeb.PayrollRunController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.Payrolls

  def index(conn, %{"company_id" => company_id} = params) do
    {runs, next_cursor} = Payrolls.list_runs(company_id, params["cursor"])
    render(conn, :index, runs: runs, next_cursor: next_cursor)
  end

  def show(conn, %{"id" => id}) do
    case Payrolls.get_run(id) do
      {:ok, run} -> render(conn, :show, run: run)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "not found"})
    end
  end

  def create(conn, %{"company_id" => company_id, "pay_period" => pay_period}) do
    case Payrolls.create_run(company_id, pay_period) do
      {:ok, run} -> conn |> put_status(:created) |> render(:show, run: run)
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> render(:error, changeset: changeset)
    end
  end

  # Triggers payroll calculation. Calls calculate_run/1 synchronously —
  # in production this would enqueue a Broadway job instead.
  def start(conn, %{"id" => id}) do
    case Payrolls.calculate_run(id) do
      {:ok, run} -> render(conn, :show, run: run)
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def approve(conn, %{"id" => id}) do
    case Payrolls.approve_run(id) do
      {:ok, run} -> render(conn, :show, run: run)
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def cancel(conn, %{"id" => id}) do
    case Payrolls.cancel_run(id) do
      {:ok, run} -> render(conn, :show, run: run)
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def list_intents(conn, %{"id" => run_id}) do
    intents = Payrolls.list_intents(run_id)
    render(conn, :intents, intents: intents)
  end
end
