defmodule GlobalPayrollWeb.Live.RunShowLive do
  use GlobalPayrollWeb, :live_view
  alias GlobalPayroll.{Payrolls, Queue}

  @poll_interval 2000
  @polling_states ~w(calculating approved paying)

  def mount(%{"id" => id}, _session, socket) do
    case Payrolls.get_run(id) do
      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/app/companies")}

      {:ok, run} ->
        if connected?(socket), do: schedule_poll_if_needed(run.status)
        socket = assign(socket, run: run, alert: nil,
                        intent_cursor: nil, intent_cursors: [],
                        payslip_cursor: nil, payslip_cursors: [],
                        status_counts: %{},
                        finished_at: nil)
        {:ok, load_details(socket, run)}
    end
  end

  def handle_info(:poll, socket) do
    case Payrolls.get_run(socket.assigns.run.id) do
      {:ok, run} ->
        schedule_poll_if_needed(run.status)
        {:noreply, load_details(assign(socket, run: run), run)}

      {:error, :not_found} ->
        {:noreply, push_navigate(socket, to: ~p"/app/companies")}
    end
  end

  def handle_event("start", _params, socket) do
    run = socket.assigns.run
    :ok = Queue.enqueue_calculate_payroll(run.id)
    Process.send_after(self(), :poll, 800)
    {:noreply, assign(socket, alert: {:ok, "Calculation queued — status will update shortly"})}
  end

  def handle_event("approve", _params, socket) do
    run = socket.assigns.run

    case Payrolls.approve_run(run.id) do
      {:ok, paying_run} ->
        schedule_poll_if_needed(paying_run.status)
        socket = load_details(assign(socket, run: paying_run), paying_run)
        {:noreply, assign(socket, alert: {:ok, "Approved — payments processing"})}

      {:error, reason} ->
        {:noreply, assign(socket, alert: {:error, inspect(reason)})}
    end
  end

  def handle_event("cancel", _params, socket) do
    run = socket.assigns.run

    if cancellable?(run.status) do
      case Payrolls.cancel_run(run.id) do
        {:ok, run} ->
          {:noreply, assign(socket, run: run, alert: {:ok, "Run cancelled"})}

        {:error, reason} ->
          {:noreply, assign(socket, alert: {:error, inspect(reason)})}
      end
    else
      {:noreply, assign(socket, alert: {:error, "Cannot cancel — payroll is already in progress"})}
    end
  end

  def handle_event("intent_next", _params, socket) do
    prev_stack = [socket.assigns.intent_cursor | socket.assigns.intent_cursors]
    socket = assign(socket, intent_cursor: socket.assigns.intent_next_cursor, intent_cursors: prev_stack)
    {:noreply, load_details(socket, socket.assigns.run)}
  end

  def handle_event("intent_prev", _params, socket) do
    [prev | rest] = socket.assigns.intent_cursors
    socket = assign(socket, intent_cursor: prev, intent_cursors: rest)
    {:noreply, load_details(socket, socket.assigns.run)}
  end

  def handle_event("payslip_next", _params, socket) do
    prev_stack = [socket.assigns.payslip_cursor | socket.assigns.payslip_cursors]
    socket = assign(socket, payslip_cursor: socket.assigns.payslip_next_cursor, payslip_cursors: prev_stack)
    {:noreply, load_details(socket, socket.assigns.run)}
  end

  def handle_event("payslip_prev", _params, socket) do
    [prev | rest] = socket.assigns.payslip_cursors
    socket = assign(socket, payslip_cursor: prev, payslip_cursors: rest)
    {:noreply, load_details(socket, socket.assigns.run)}
  end

  defp load_details(socket, run) do
    if run.status in ~w(pending_approval approved paying completed failed) do
      {intents, intent_next} = Payrolls.list_intents_page(run.id, socket.assigns.intent_cursor)
      status_counts = Payrolls.count_intents_by_status(run.id)

      finished_at =
        if run.status == "paying" and all_settled?(status_counts) and is_nil(socket.assigns.finished_at) do
          DateTime.utc_now()
        else
          socket.assigns.finished_at
        end

      socket = assign(socket, intents: intents, intent_next_cursor: intent_next, status_counts: status_counts, finished_at: finished_at)

      if run.status == "completed" do
        {payslips, payslip_next} = Payrolls.list_payslips_by_run_page(run.id, socket.assigns.payslip_cursor)
        invoices = Payrolls.list_invoices_by_company(run.company_id)
        invoice = Enum.find(invoices, &(&1.payroll_run_id == run.id))
        assign(socket, payslips: payslips, payslip_next_cursor: payslip_next, invoice: invoice)
      else
        assign(socket, payslips: [], payslip_next_cursor: nil, invoice: nil)
      end
    else
      assign(socket, intents: [], intent_next_cursor: nil, payslips: [], payslip_next_cursor: nil, invoice: nil, status_counts: %{})
    end
  end

  defp schedule_poll_if_needed(status) when status in @polling_states do
    Process.send_after(self(), :poll, @poll_interval)
  end
  defp schedule_poll_if_needed(_), do: :ok

  defp cancellable?(status), do: status in ["draft", "pending_approval"]

  defp all_settled?(counts) do
    map_size(counts) > 0 and
      Map.get(counts, "pending", 0) == 0 and
      Map.get(counts, "processing", 0) == 0
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <.link navigate={~p"/app/companies/#{@run.company_id}"}
               class="text-sm text-blue-600 hover:underline">
          ← Company
        </.link>
        <h1 class="text-2xl font-bold mt-1">
          Payroll Run — <span class="text-blue-600"><%= @run.pay_period %></span>
        </h1>
      </div>

      <%= if @alert do %>
        <div class={["mb-4 p-3 rounded text-sm border", flash_class(elem(@alert, 0))]}>
          <%= elem(@alert, 1) %>
        </div>
      <% end %>

      <div class="bg-white rounded-lg border p-6 mb-6">
        <div class="flex items-start justify-between">
          <div>
            <div class="text-xs text-gray-500 uppercase tracking-wide mb-2">Status</div>
            <div class="flex items-center gap-3">
              <span class={["px-3 py-1.5 rounded-full text-sm font-semibold", run_status_badge(@run.status)]}>
                <%= status_label(@run.status) %>
              </span>
              <%= if @run.status in ["calculating", "paying"] do %>
                <span class="text-sm text-gray-400 animate-pulse">processing...</span>
              <% end %>
              <%= if @run.status == "approved" do %>
                <span class="text-sm text-gray-400 animate-pulse">payments in flight...</span>
              <% end %>
            </div>
          </div>
          <%= if @run.total_amount do %>
            <div class="text-right">
              <div class="text-xs text-gray-500 uppercase tracking-wide mb-1">Total Amount</div>
              <div class="text-2xl font-bold"><%= format_money(@run.total_amount) %></div>
            </div>
          <% end %>
        </div>

        <%= if @run.ran_at do %>
          <div class="mt-4 grid grid-cols-3 gap-4 text-sm border-t pt-4">
            <div>
              <div class="text-xs text-gray-400 uppercase tracking-wide mb-1">Started</div>
              <div class="text-gray-700"><%= format_datetime(@run.ran_at) %></div>
            </div>
            <%= if @run.status == "completed" or @finished_at do %>
              <% completed_at = @finished_at || @run.updated_at %>
              <div>
                <div class="text-xs text-gray-400 uppercase tracking-wide mb-1">Completed</div>
                <div class="text-gray-700"><%= format_datetime(completed_at) %></div>
              </div>
              <div>
                <div class="text-xs text-gray-400 uppercase tracking-wide mb-1">Duration</div>
                <div class="text-gray-700"><%= format_duration(@run.ran_at, completed_at) %></div>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @run.error do %>
          <div class="mt-4 p-3 bg-red-50 rounded text-sm text-red-700 border border-red-200">
            Error: <%= @run.error %>
          </div>
        <% end %>

        <div class="flex gap-3 mt-5">
          <%= if @run.status == "draft" do %>
            <button phx-click="start"
                    class="bg-blue-600 text-white px-5 py-2 rounded text-sm font-medium hover:bg-blue-700">
              Start Calculation
            </button>
          <% end %>
          <%= if @run.status == "pending_approval" do %>
            <button phx-click="approve"
                    class="bg-green-600 text-white px-5 py-2 rounded text-sm font-medium hover:bg-green-700">
              Approve & Pay
            </button>
          <% end %>
          <%= if cancellable?(@run.status) do %>
            <button phx-click="cancel"
                    class="border border-red-300 text-red-600 px-4 py-2 rounded text-sm hover:bg-red-50">
              Cancel
            </button>
          <% end %>
        </div>
      </div>

      <%= if map_size(@status_counts) > 0 do %>
        <div class="bg-white rounded-lg border p-4 mb-6">
          <div class="grid grid-cols-4 gap-3 text-center text-sm">
            <div class="p-3 bg-gray-50 rounded">
              <div class="text-2xl font-bold text-gray-700"><%= Map.get(@status_counts, "pending", 0) %></div>
              <div class="text-xs text-gray-400 mt-1 uppercase tracking-wide">Pending</div>
            </div>
            <div class="p-3 bg-blue-50 rounded">
              <div class="text-2xl font-bold text-blue-700"><%= Map.get(@status_counts, "processing", 0) %></div>
              <div class="text-xs text-blue-400 mt-1 uppercase tracking-wide">Processing</div>
            </div>
            <div class="p-3 bg-green-50 rounded">
              <div class="text-2xl font-bold text-green-700"><%= Map.get(@status_counts, "completed", 0) %></div>
              <div class="text-xs text-green-400 mt-1 uppercase tracking-wide">Completed</div>
            </div>
            <div class="p-3 bg-red-50 rounded">
              <div class="text-2xl font-bold text-red-700"><%= Map.get(@status_counts, "failed", 0) %></div>
              <div class="text-xs text-red-400 mt-1 uppercase tracking-wide">Failed</div>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @intents != [] do %>
        <div class="mb-6">
          <h2 class="text-lg font-semibold mb-3">
            Payment Intents (<%= length(@intents) %><%= if @intent_next_cursor, do: "+" %>)
          </h2>
          <div class="bg-white rounded-lg border overflow-hidden">
            <table class="w-full text-sm">
              <thead class="bg-gray-50 text-gray-500 text-left">
                <tr>
                  <th class="px-4 py-3">Employee</th>
                  <th class="px-4 py-3">Gross</th>
                  <th class="px-4 py-3">Taxes</th>
                  <th class="px-4 py-3">Fee</th>
                  <th class="px-4 py-3">Net</th>
                  <th class="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody>
                <%= for intent <- @intents do %>
                  <tr class="border-t">
                    <td class="px-4 py-3 font-mono text-xs text-gray-500">
                      <%= String.slice(intent.employee_id, 0, 8) %>…
                    </td>
                    <td class="px-4 py-3"><%= format_money(intent.gross_salary) %></td>
                    <td class="px-4 py-3 text-gray-500">
                      <%= format_money(Decimal.add(intent.income_tax, intent.social_security)) %>
                    </td>
                    <td class="px-4 py-3 text-gray-500"><%= format_money(intent.platform_fee) %></td>
                    <td class="px-4 py-3 font-semibold"><%= format_money(intent.net_salary) %></td>
                    <td class="px-4 py-3">
                      <span class={["px-2 py-1 rounded-full text-xs font-medium", intent_status_badge(intent.status)]}>
                        <%= intent.status %>
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
            <div class="flex items-center justify-between px-4 py-3 border-t text-sm text-gray-500">
              <span>Showing <%= length(@intents) %> per page</span>
              <div class="flex gap-2">
                <button phx-click="intent_prev" disabled={@intent_cursors == []}
                        class={["px-3 py-1 rounded border text-sm", if(@intent_cursors == [], do: "text-gray-300 border-gray-200 cursor-not-allowed", else: "text-gray-600 hover:bg-gray-50")]}>
                  ← Prev
                </button>
                <button phx-click="intent_next" disabled={is_nil(@intent_next_cursor)}
                        class={["px-3 py-1 rounded border text-sm", if(is_nil(@intent_next_cursor), do: "text-gray-300 border-gray-200 cursor-not-allowed", else: "text-gray-600 hover:bg-gray-50")]}>
                  Next →
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @payslips != [] do %>
        <div class="mb-6">
          <h2 class="text-lg font-semibold mb-3">
            Payslips (<%= length(@payslips) %><%= if @payslip_next_cursor, do: "+" %>)
          </h2>
          <div class="bg-white rounded-lg border overflow-hidden">
            <table class="w-full text-sm">
              <thead class="bg-gray-50 text-gray-500 text-left">
                <tr>
                  <th class="px-4 py-3">Employee</th>
                  <th class="px-4 py-3">Gross</th>
                  <th class="px-4 py-3">Income Tax</th>
                  <th class="px-4 py-3">Social Security</th>
                  <th class="px-4 py-3">Net Paid</th>
                </tr>
              </thead>
              <tbody>
                <%= for slip <- @payslips do %>
                  <tr class="border-t">
                    <td class="px-4 py-3 font-mono text-xs text-gray-500">
                      <%= String.slice(slip.employee_id, 0, 8) %>…
                    </td>
                    <td class="px-4 py-3"><%= format_money(slip.gross_salary) %></td>
                    <td class="px-4 py-3 text-gray-500"><%= format_money(slip.income_tax) %></td>
                    <td class="px-4 py-3 text-gray-500"><%= format_money(slip.social_security) %></td>
                    <td class="px-4 py-3 font-semibold text-green-700"><%= format_money(slip.net_salary) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
            <div class="flex items-center justify-between px-4 py-3 border-t text-sm text-gray-500">
              <span>Showing <%= length(@payslips) %> per page</span>
              <div class="flex gap-2">
                <button phx-click="payslip_prev" disabled={@payslip_cursors == []}
                        class={["px-3 py-1 rounded border text-sm", if(@payslip_cursors == [], do: "text-gray-300 border-gray-200 cursor-not-allowed", else: "text-gray-600 hover:bg-gray-50")]}>
                  ← Prev
                </button>
                <button phx-click="payslip_next" disabled={is_nil(@payslip_next_cursor)}
                        class={["px-3 py-1 rounded border text-sm", if(is_nil(@payslip_next_cursor), do: "text-gray-300 border-gray-200 cursor-not-allowed", else: "text-gray-600 hover:bg-gray-50")]}>
                  Next →
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @invoice do %>
        <div class="bg-white rounded-lg border p-6">
          <h2 class="text-lg font-semibold mb-4">Invoice</h2>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div class="p-3 bg-gray-50 rounded">
              <div class="text-gray-500 text-xs mb-1">Gross Salaries</div>
              <div class="font-semibold"><%= format_money(@invoice.total_gross_salaries) %></div>
            </div>
            <div class="p-3 bg-gray-50 rounded">
              <div class="text-gray-500 text-xs mb-1">Taxes Withheld</div>
              <div class="font-semibold"><%= format_money(@invoice.total_taxes_withheld) %></div>
            </div>
            <div class="p-3 bg-gray-50 rounded">
              <div class="text-gray-500 text-xs mb-1">Platform Fees</div>
              <div class="font-semibold"><%= format_money(@invoice.total_platform_fees) %></div>
            </div>
            <div class="p-3 bg-blue-50 rounded border border-blue-200">
              <div class="text-blue-600 text-xs mb-1 font-medium">Total Amount</div>
              <div class="font-bold text-xl text-blue-700"><%= format_money(@invoice.total_amount) %></div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp run_status_badge("draft"), do: "bg-gray-100 text-gray-600"
  defp run_status_badge("calculating"), do: "bg-blue-100 text-blue-700"
  defp run_status_badge("pending_approval"), do: "bg-yellow-100 text-yellow-800"
  defp run_status_badge("approved"), do: "bg-indigo-100 text-indigo-700"
  defp run_status_badge("paying"), do: "bg-purple-100 text-purple-700"
  defp run_status_badge("completed"), do: "bg-green-100 text-green-700"
  defp run_status_badge("failed"), do: "bg-red-100 text-red-700"
  defp run_status_badge(_), do: "bg-gray-100 text-gray-600"

  defp intent_status_badge("pending"), do: "bg-gray-100 text-gray-600"
  defp intent_status_badge("processing"), do: "bg-blue-100 text-blue-700"
  defp intent_status_badge("completed"), do: "bg-green-100 text-green-700"
  defp intent_status_badge("failed"), do: "bg-red-100 text-red-700"
  defp intent_status_badge(_), do: "bg-gray-100 text-gray-600"

  defp status_label("draft"), do: "Draft"
  defp status_label("calculating"), do: "Calculating"
  defp status_label("pending_approval"), do: "Pending Approval"
  defp status_label("approved"), do: "Approved"
  defp status_label("paying"), do: "Paying"
  defp status_label("completed"), do: "Completed ✓"
  defp status_label("failed"), do: "Failed"
  defp status_label(s), do: s

  defp flash_class(:ok), do: "bg-green-50 text-green-700 border-green-200"
  defp flash_class(:error), do: "bg-red-50 text-red-700 border-red-200"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M:%S UTC")
  end

  defp format_duration(from, to) do
    seconds = DateTime.diff(to, from)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    if minutes > 0, do: "#{minutes}m #{secs}s", else: "#{secs}s"
  end
end
