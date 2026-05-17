defmodule GlobalPayrollWeb.PaymentWebhookController do
  use GlobalPayrollWeb, :controller
  alias GlobalPayroll.Queue

  def event(conn, params) do
    Queue.enqueue_payment_result(params)
    send_resp(conn, 200, "")
  end
end
