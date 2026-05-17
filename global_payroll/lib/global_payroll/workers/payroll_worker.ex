defmodule GlobalPayroll.Workers.PayrollWorker do
  use Broadway

  alias GlobalPayroll.{Payrolls, Payments}

  @queue_url Application.compile_env(:global_payroll, [:queues, :payroll_jobs])

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
      %{"job" => "calculate_payroll", "run_id" => run_id} ->
        case Payrolls.calculate_run(run_id) do
          {:ok, _} -> message
          {:error, reason} -> Broadway.Message.failed(message, inspect(reason))
        end

      %{"job" => "execute_payment", "intent_id" => intent_id} ->
        case Payments.execute_payment(intent_id) do
          {:ok, _} -> message
          {:error, reason} when reason in [:already_settled, :not_found] -> message
          {:error, reason} -> Broadway.Message.failed(message, inspect(reason))
        end

      _ ->
        Broadway.Message.failed(message, "unknown job type")
    end
  end

  # Required when batchers are configured; BroadwaySQS acks messages in batches here.
  @impl Broadway
  def handle_batch(_batcher, messages, _batch_info, _context), do: messages
end
