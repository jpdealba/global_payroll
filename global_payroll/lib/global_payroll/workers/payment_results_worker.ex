defmodule GlobalPayroll.Workers.PaymentResultsWorker do
  use Broadway

  alias Broadway.Message
  alias GlobalPayroll.Payments

  @queue_url Application.compile_env!(
               :global_payroll,
               [:queues, :payment_results]
             )

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          BroadwaySQS.Producer,
          queue_url: @queue_url, receive_interval: 200, visibility_timeout: 120
        },
        concurrency: 5
      ],
      processors: [
        default: [
          concurrency: 25
        ]
      ]
    )
  end

  @impl true
  def handle_message(_, message, _) do
    case Jason.decode(message.data) do
      {:ok, %{"intent_id" => _} = event} ->
        case Payments.process_result(event) do
          {:ok, _} ->
            message

          {:error, reason} when reason in [:not_found, :already_settled] ->
            message

          {:error, reason} ->
            Message.failed(message, inspect(reason))
        end

      {:ok, %{"payment_id" => _, "status" => _} = event} ->
        case Payments.handle_webhook_event(event) do
          {:ok, _} ->
            message

          {:error, reason} when reason in [:not_found, :already_settled] ->
            message

          {:error, reason} ->
            Message.failed(message, inspect(reason))
        end

      {:ok, _} ->
        Message.failed(message, "unknown_event_format")

      {:error, _} ->
        Message.failed(message, "invalid_json")
    end
  end
end
