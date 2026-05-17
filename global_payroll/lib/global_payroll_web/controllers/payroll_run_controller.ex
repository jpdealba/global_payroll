defmodule GlobalPayrollWeb.PayrollRunController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.{Payrolls, Queue}

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

  # Enqueues a calculate_payroll job and returns 202 immediately.
  # The Broadway worker picks it up and calls Payrolls.calculate_run/1.
  def start(conn, %{"id" => id}) do
    case Payrolls.get_run(id) do
      {:ok, _run} ->
        {:ok, _} = Queue.enqueue_calculate_payroll(id)
        send_resp(conn, 202, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})
    end
  end

  # Transitions the run to approved synchronously (immediate feedback on invalid state),
  # then fans out one execute_payment message per intent using SQS batch API.
  def approve(conn, %{"id" => id}) do
    with {:ok, run} <- Payrolls.approve_run(id) do
      run.id
      |> Payrolls.list_intents()
      |> Enum.map(fn intent -> intent.id end)
      |> Queue.enqueue_execute_payments()

      send_resp(conn, 202, "")
    else
      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
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

  def list_payslips(conn, %{"id" => run_id}) do
    payslips = Payrolls.list_payslips_by_run(run_id)
    render(conn, :payslips, payslips: payslips)
  end
end
