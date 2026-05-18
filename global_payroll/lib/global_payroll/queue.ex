defmodule GlobalPayroll.Queue do
  @payroll_jobs Application.compile_env(:global_payroll, [:queues, :payroll_jobs])
  @payment_results Application.compile_env(:global_payroll, [:queues, :payment_results])
  @max_send_retries 5

  def enqueue_calculate_payroll(run_id) do
    send_message(@payroll_jobs, %{job: "calculate_payroll", run_id: run_id})
  end

  def enqueue_payment_result(event) do
    send_message(@payment_results, event)
  end

  def enqueue_execute_payment(intent_id) do
    send_message(@payroll_jobs, %{job: "execute_payment", intent_id: intent_id})
  end

  def enqueue_execute_payments(intent_ids) do
    results =
      intent_ids
      |> Enum.map(fn id ->
        [id: id, message_body: Jason.encode!(%{job: "execute_payment", intent_id: id})]
      end)
      |> Enum.chunk_every(10)
      |> Task.async_stream(
        fn chunk ->
          ExAws.SQS.send_message_batch(@payroll_jobs, chunk)
          |> request_with_retry()
        end,
        max_concurrency: 10,
        ordered: false,
        timeout: 30_000
      )
      |> Enum.to_list()

    case Enum.filter(results, &batch_failed?/1) do
      [] -> :ok
      failures -> {:error, {:batch_failures, failures}}
    end
  end

  defp batch_failed?({:ok, :ok}), do: false
  defp batch_failed?({:ok, {:error, _}}), do: true
  defp batch_failed?({:exit, _}), do: true
  defp batch_failed?(_), do: true

  defp send_message(queue_url, payload, attempt \\ 1) do
    case queue_url |> ExAws.SQS.send_message(Jason.encode!(payload)) |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, _reason} when attempt < @max_send_retries ->
        Process.sleep(send_backoff_ms(attempt))
        send_message(queue_url, payload, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_with_retry(request, attempt \\ 1) do
    case ExAws.request(request) do
      {:ok, _} -> :ok
      {:error, _reason} when attempt < @max_send_retries ->
        Process.sleep(send_backoff_ms(attempt))
        request_with_retry(request, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_backoff_ms(attempt), do: min(200 * attempt * attempt, 2_000)
end
