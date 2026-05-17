defmodule GlobalPayroll.Workers.PaymentResultsWorker do
  use Broadway

  alias GlobalPayroll.Payments

  @queue_url Application.compile_env(:global_payroll, [:queues, :payment_results])

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
          module: {BroadwaySQS.Producer, queue_url: @queue_url, receive_interval: 100},
          concurrency: 50
        ],
        processors: [
          default: [concurrency: 50]
        ],
        batchers: [
          default: [batch_size: 500, batch_timeout: 5_000, concurrency: 10]
        ]
    )
  end

  @impl Broadway
  def handle_message(_, message, _) do
    case Jason.decode!(message.data) do
      %{"intent_id" => _} = event ->
        case Payments.process_result(event) do
          {:ok, _} -> message
          {:error, reason} when reason in [:not_found, :already_settled] -> message
          {:error, reason} -> Broadway.Message.failed(message, inspect(reason))
        end

      %{"payment_id" => _, "status" => _} = event ->
        case Payments.handle_webhook_event(event) do
          {:ok, _} -> message
          {:error, reason} when reason in [:not_found, :already_settled] -> message
          {:error, reason} -> Broadway.Message.failed(message, inspect(reason))
        end

      _ ->
        Broadway.Message.failed(message, "unknown event format")
    end
  end

  # Required when batchers are configured; BroadwaySQS acks messages in batches here.
  @impl Broadway
  def handle_batch(_batcher, messages, _batch_info, _context), do: messages
end
