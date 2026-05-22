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

  # In case of failure or reconciliation job
  def enqueue_execute_payment(intent_id) do
    send_message(@payroll_jobs, %{job: "execute_payment", intent_id: intent_id})
  end

  # In case of approval job
  def enqueue_execute_payments(intent_ids) do
    results =
      intent_ids
      |> Enum.map(fn id ->
        [id: id, message_body: Jason.encode!(%{job: "execute_payment", intent_id: id})]
      end)
      |> Enum.chunk_every(10) #sqs limit is 10 messages per batch send
      |> Task.async_stream( #use async stream so we know if any batch failed
        fn chunk ->
          ExAws.SQS.send_message_batch(@payroll_jobs, chunk)
          |> request_with_retry()
        end,
        max_concurrency: 10, #10 concurrent batches
        ordered: false,
        timeout: 30_000
      ) #async stream to send messages in parallel, ordered is false because we don't care about the order of the messages
      |> Enum.to_list()

    #check if any batch failed
    case Enum.filter(results, &batch_failed?/1) do
      [] -> :ok
      failures -> {:error, {:batch_failures, failures}}
    end
  end

  defp batch_failed?({:ok, :ok}), do: false #if the batch is successful, return false
  defp batch_failed?(_), do: true #if the batch is anything else, return true

  #send individual message to the queue
  # used in calculate payroll, payment_result, execute_payment
  defp send_message(queue_url, payload, attempt \\ 1) do
    case queue_url |> ExAws.SQS.send_message(Jason.encode!(payload)) |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, _reason} when attempt < @max_send_retries ->
        # If the message fails, wait for a backoff time and try again
        Process.sleep(send_backoff_ms(attempt))
        send_message(queue_url, payload, attempt + 1)

      {:error, reason} ->
        # If the message fails and we have reached the max retries, return the error
        {:error, reason}
    end
  end

  #Used in the batch to send messages (10) to the queue
  # used in execute_payments
  defp request_with_retry(request, attempt \\ 1) do
    #  message is already encoded, so we don't need to encode it again
    case ExAws.request(request) do
      {:ok, _} ->
        :ok

      {:error, _reason} when attempt < @max_send_retries ->
        Process.sleep(send_backoff_ms(attempt))
        request_with_retry(request, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_backoff_ms(attempt), do: min(200 * attempt * attempt, 2_000)
end
