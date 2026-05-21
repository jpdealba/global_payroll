defmodule GlobalPayroll.Workers.InvoiceWorker do
  use GenServer

  alias GlobalPayroll.{Payrolls, Payments}

  @interval :timer.minutes(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    schedule()
    {:ok, []}
  end

  @impl true
  def handle_info(:run, state) do
    Payments.reconcile_stuck_intents()
    Payrolls.close_completed_runs()
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :run, @interval)
end
