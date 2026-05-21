defmodule GlobalPayrollWeb.PaymentWebhookController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.Queue

  def event(conn, params) do
    case Queue.enqueue_payment_result(params) do
      :ok ->
        send_resp(conn, 200, "")

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "queue unavailable", detail: inspect(reason)})
    end
  end
end
