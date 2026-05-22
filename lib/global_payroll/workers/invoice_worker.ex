defmodule GlobalPayroll.Workers.InvoiceWorker do
  # This worker is responsible for generating invoices for completed payroll runs
  # It is run every minute and looks for "paying" runs with no intents in pending/processing
  # and aggregates the totals, inserts an invoice, and updates the run to "completed"
  # It also reconciles stuck intents that are in processing but have no payment attempts
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
