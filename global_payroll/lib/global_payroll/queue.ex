defmodule GlobalPayroll.Queue do
  @payroll_jobs Application.compile_env(:global_payroll, [:queues, :payroll_jobs])

  def enqueue_calculate_payroll(run_id) do
    send_message(@payroll_jobs, %{job: "calculate_payroll", run_id: run_id})
  end

  def enqueue_execute_payments(intent_ids) do
    intent_ids
    |> Enum.map(fn id ->
      [id: id, message_body: Jason.encode!(%{job: "execute_payment", intent_id: id})]
    end)
    |> Enum.chunk_every(10)
    |> Task.async_stream(
      fn chunk ->
        ExAws.SQS.send_message_batch(@payroll_jobs, chunk)
        |> ExAws.request!()
      end,
      max_concurrency: 50,
      ordered: false
    )
    |> Stream.run()
  end

  defp send_message(queue_url, payload) do
    queue_url
    |> ExAws.SQS.send_message(Jason.encode!(payload))
    |> ExAws.request()
  end
end
