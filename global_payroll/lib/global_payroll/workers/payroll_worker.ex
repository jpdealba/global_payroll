defmodule GlobalPayroll.Workers.PayrollWorker do
  use Broadway

  alias Broadway.Message
  alias GlobalPayroll.{Payrolls, Payments}

  @queue_url Application.compile_env!(
               :global_payroll,
               [:queues, :payroll_jobs]
             )

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        concurrency: 5,
        module:
          {BroadwaySQS.Producer,
           queue_url: @queue_url,
           receive_interval: 50,
           max_number_of_messages: 10,
           visibility_timeout: 120,
           wait_time_seconds: 10}
      ],
      processors: [
        default: [
          concurrency: 50,
          max_demand: 20,
          min_demand: 10
        ]
      ]
    )
  end

  @impl true
  def handle_message(_, message, _) do
    case Jason.decode(message.data) do
      {:ok, %{"job" => "calculate_payroll", "run_id" => run_id}} ->
        case Payrolls.calculate_run(run_id) do
          {:ok, _} ->
            message

          {:error, reason} ->
            Message.failed(message, inspect(reason))
        end

      {:ok, %{"job" => "execute_payment", "intent_id" => intent_id}} ->
        case Payments.execute_payment(intent_id) do
          {:ok, _} ->
            message

          {:error, reason} when reason in [:already_settled, :not_found] ->
            message

          {:error, reason} ->
            Message.failed(message, inspect(reason))
        end

      {:ok, _} ->
        Message.failed(message, "unknown_job")

      {:error, _} ->
        Message.failed(message, "invalid_json")
    end
  end
end
