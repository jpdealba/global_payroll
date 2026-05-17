defmodule GlobalPayroll.Workers.PaymentResultsWorker do
  use Broadway

  alias GlobalPayroll.Payments

  @queue_url Application.compile_env(:global_payroll, [:queues, :payment_results])

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {BroadwaySQS.Producer,
           queue_url: @queue_url,
           config: [
             access_key_id: "local",
             secret_access_key: "local",
             region: "us-east-1",
             sqs: [scheme: "http://", host: "localhost", port: 9324]
           ]}
      ],
      processors: [
        default: [concurrency: 10]
      ]
    )
  end

  @impl Broadway
  def handle_message(_, message, _) do
    case Jason.decode!(message.data) do
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
end
