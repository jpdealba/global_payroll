defmodule GlobalPayrollWeb.Live.CompanyShowLive do
  use GlobalPayrollWeb, :live_view
  alias GlobalPayroll.{Companies, Employees, Taxes, Payrolls, Ledger}

  def mount(%{"id" => id}, _session, socket) do
    case Companies.get_company(id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/app/companies")}

      company ->
        {tax_rules, _} = Taxes.list_country_tax_rules()

        socket =
          assign(socket,
            tax_rules: tax_rules,
            alert: nil,
            emp_cursor: nil,
            emp_cursors: [],
            emp_next_cursor: nil,
            emp_total: 0,
            emp_page: 1,
            transactions: [],
            tx_cursor: nil,
            tx_cursors: [],
            tx_next_cursor: nil,
            tx_type_filter: nil
          )

        {:ok, load_data(socket, company)}
    end
  end

  defp load_data(socket, company) do
    {runs, _} = Payrolls.list_runs(company.id)
    balance = Companies.get_company_balance(company.id)

    socket
    |> assign(company: company, balance: balance, runs: runs)
    |> load_employees(company.id, nil, [])
    |> load_transactions(company.id, nil, [], nil)
  end

  defp load_transactions(socket, company_id, cursor, prev_cursors, type) do
    {txs, next} = Companies.list_transactions(company_id, cursor, 25, type)

    assign(socket,
      transactions: txs,
      tx_cursor: cursor,
      tx_cursors: prev_cursors,
      tx_next_cursor: next,
      tx_type_filter: type
    )
  end

  defp load_employees(socket, company_id, cursor, prev_cursors) do
    {employees, next_cursor} = Employees.list_employees_by_company(company_id, cursor)
    employees = GlobalPayroll.Repo.preload(employees, :country_tax_rule)
    total = Employees.count_employees_by_company(company_id)

    assign(socket,
      employees: employees,
      emp_total: total,
      emp_cursor: cursor,
      emp_cursors: prev_cursors,
      emp_next_cursor: next_cursor,
      emp_page: length(prev_cursors) + 1
    )
  end

  def handle_event("deposit", %{"amount" => amount}, socket) do
    company = socket.assigns.company

    case Decimal.parse(amount) do
      {amount_d, ""} ->
        ref = Ecto.UUID.generate()
        {:ok, _} = Ledger.deposit(company.id, amount_d, ref, "Manual deposit via platform")
        balance = Companies.get_company_balance(company.id)
        {:noreply, assign(socket, balance: balance, alert: {:ok, "Deposited $#{amount}"})}

      _ ->
        {:noreply, assign(socket, alert: {:error, "Invalid amount"})}
    end
  end

  def handle_event("create_employee", params, socket) do
    company = socket.assigns.company

    employee_attrs = %{
      "name" => params["name"],
      "email" => params["email"],
      "gross_salary" => params["gross_salary"],
      "company_id" => company.id,
      "country_tax_id" => params["country_tax_id"],
      "status" => "active"
    }

    payment_method_attrs = %{
      "bank_name" => params["bank_name"],
      "bank_code" => params["bank_code"],
      "account_holder" => params["account_holder"],
      "account_number" => params["account_number"],
      "is_default" => true
    }

    with {:ok, employee} <- Employees.create_employee(employee_attrs),
         {:ok, _} <- Employees.add_payment_method(employee.id, payment_method_attrs) do
      socket = load_employees(socket, company.id, nil, [])
      {:noreply, assign(socket, alert: {:ok, "Employee added"})}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, alert: {:error, changeset_errors(cs)})}

      {:error, reason} ->
        {:noreply, assign(socket, alert: {:error, inspect(reason)})}
    end
  end

  def handle_event("create_run", %{"pay_period" => period}, socket) do
    company = socket.assigns.company

    case Payrolls.create_run(company.id, period) do
      {:ok, _} ->
        {runs, _} = Payrolls.list_runs(company.id)
        {:noreply, assign(socket, runs: runs, alert: {:ok, "Payroll run created"})}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, alert: {:error, changeset_errors(cs)})}
    end
  end

  def handle_event("emp_next", _params, socket) do
    next = socket.assigns.emp_next_cursor
    prev_stack = [socket.assigns.emp_cursor | socket.assigns.emp_cursors]
    {:noreply, load_employees(socket, socket.assigns.company.id, next, prev_stack)}
  end

  def handle_event("emp_prev", _params, socket) do
    [prev | rest] = socket.assigns.emp_cursors
    {:noreply, load_employees(socket, socket.assigns.company.id, prev, rest)}
  end

  def handle_event("tx_next", _params, socket) do
    prev_stack = [socket.assigns.tx_cursor | socket.assigns.tx_cursors]
    {:noreply, load_transactions(socket, socket.assigns.company.id, socket.assigns.tx_next_cursor, prev_stack, socket.assigns.tx_type_filter)}
  end

  def handle_event("tx_prev", _params, socket) do
    [prev | rest] = socket.assigns.tx_cursors
    {:noreply, load_transactions(socket, socket.assigns.company.id, prev, rest, socket.assigns.tx_type_filter)}
  end

  def handle_event("filter_tx_type", %{"type" => type}, socket) do
    new_filter = if socket.assigns.tx_type_filter == type, do: nil, else: type
    {:noreply, load_transactions(socket, socket.assigns.company.id, nil, [], new_filter)}
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-6">
        <.link navigate={~p"/app/companies"} class="text-sm text-blue-600 hover:underline">← Companies</.link>
        <div class="flex items-center gap-3 mt-1">
          <h1 class="text-2xl font-bold"><%= @company.name %></h1>
          <span class={["px-2 py-1 rounded-full text-xs font-medium", status_badge(@company.status)]}>
            <%= @company.status %>
          </span>
        </div>
      </div>
    
      <%= if @alert do %>
        <div class={["mb-4 p-3 rounded text-sm border", flash_class(elem(@alert, 0))]}>
          <%= elem(@alert, 1) %>
        </div>
      <% end %>
    
      <div class="grid grid-cols-2 gap-6 mb-8">
        <div class="bg-white rounded-lg border p-5">
          <div class="text-xs text-gray-500 uppercase tracking-wide mb-1">Balance</div>
          <div class="text-3xl font-bold"><%= format_money(@balance) %></div>
        </div>
        <div class="bg-white rounded-lg border p-5">
          <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Deposit Funds</div>
          <form phx-submit="deposit" class="flex gap-2">
            <input name="amount" type="number" step="0.01" min="0.01" placeholder="0.00" required
                   class="flex-1 border rounded px-3 py-2 text-sm" />
            <button type="submit" class="bg-green-600 text-white px-4 py-2 rounded text-sm hover:bg-green-700">
              Deposit
            </button>
          </form>
        </div>
      </div>
    
      <div class="mb-8">
        <h2 class="text-lg font-semibold mb-3">
          Employees (<%= format_number(@emp_total) %>)
        </h2>
    
        <details class="mb-3 bg-white rounded-lg border">
          <summary class="px-4 py-3 cursor-pointer text-sm font-medium text-blue-600 hover:bg-gray-50">
            + Add Employee
          </summary>
          <form phx-submit="create_employee" class="p-4 border-t grid grid-cols-2 gap-3">
            <input name="name" placeholder="Full name" required
                   class="border rounded px-3 py-2 text-sm" />
            <input name="email" type="email" placeholder="Email" required
                   class="border rounded px-3 py-2 text-sm" />
            <input name="gross_salary" type="number" step="0.01" placeholder="Gross salary" required
                   class="border rounded px-3 py-2 text-sm" />
            <select name="country_tax_id" required class="border rounded px-3 py-2 text-sm">
              <option value="">Select country / tax rule</option>
              <%= for rule <- @tax_rules do %>
                <option value={rule.id}>
                  <%= rule.country_code %> — income: <%= rule.income_tax_rate %>, SS: <%= rule.social_security_rate %>
                </option>
              <% end %>
            </select>
            <div class="col-span-2 pt-2 border-t">
              <div class="text-xs font-medium text-gray-500 uppercase tracking-wide mb-2">Payment Method</div>
              <div class="grid grid-cols-2 gap-3">
                <input name="bank_name" placeholder="Bank name" required
                       class="border rounded px-3 py-2 text-sm" />
                <input name="bank_code" placeholder="Bank code (e.g. SWIFT)" required
                       class="border rounded px-3 py-2 text-sm" />
                <input name="account_holder" placeholder="Account holder" required
                       class="border rounded px-3 py-2 text-sm" />
                <input name="account_number" placeholder="Account number" required
                       class="border rounded px-3 py-2 text-sm" />
              </div>
            </div>
            <div class="col-span-2">
              <button type="submit"
                      class="bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700">
                Add Employee
              </button>
            </div>
          </form>
        </details>
    
        <div class="bg-white rounded-lg border overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-gray-50 text-gray-500 text-left">
              <tr>
                <th class="px-4 py-3">Name</th>
                <th class="px-4 py-3">Email</th>
                <th class="px-4 py-3">Country</th>
                <th class="px-4 py-3">Gross Salary</th>
                <th class="px-4 py-3">Status</th>
              </tr>
            </thead>
            <tbody>
              <%= if @employees == [] do %>
                <tr>
                  <td colspan="5" class="px-4 py-6 text-center text-gray-400">No employees yet</td>
                </tr>
              <% end %>
              <%= for emp <- @employees do %>
                <tr class="border-t">
                  <td class="px-4 py-3 font-medium"><%= emp.name %></td>
                  <td class="px-4 py-3 text-gray-600"><%= emp.email %></td>
                  <td class="px-4 py-3 text-gray-600"><%= emp.country_tax_rule && emp.country_tax_rule.country_code %></td>
                  <td class="px-4 py-3"><%= format_money(emp.gross_salary) %></td>
                  <td class="px-4 py-3">
                    <span class={["px-2 py-1 rounded-full text-xs font-medium", emp_status_badge(emp.status)]}>
                      <%= emp.status %>
                    </span>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <div class="flex items-center justify-between px-4 py-3 border-t text-sm text-gray-500">
            <% per_page = 20 %>
            <% from = (@emp_page - 1) * per_page + 1 %>
            <% to = (@emp_page - 1) * per_page + length(@employees) %>
            <% total_pages = ceil(@emp_total / per_page) %>
            <span>
              <%= format_number(from) %>–<%= format_number(to) %> of <%= format_number(@emp_total) %>
              · Page <%= @emp_page %> of <%= total_pages %>
            </span>
            <div class="flex gap-2">
              <button phx-click="emp_prev" disabled={@emp_cursors == []}
                      class={["px-3 py-1 rounded border text-sm", if(@emp_cursors == [], do: "text-gray-300 border-gray-200 cursor-not-allowed", else: "text-gray-600 hover:bg-gray-50")]}>
                ← Prev
              </button>
              <button phx-click="emp_next" disabled={is_nil(@emp_next_cursor)}
                      class={["px-3 py-1 rounded border text-sm", if(is_nil(@emp_next_cursor), do: "text-gray-300 border-gray-200 cursor-not-allowed", else: "text-gray-600 hover:bg-gray-50")]}>
                Next →
              </button>
            </div>
          </div>
        </div>
      </div>
    
      <div>
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-lg font-semibold">Payroll Runs</h2>
          <form phx-submit="create_run" class="flex gap-2">
            <input name="pay_period" placeholder="e.g. 2025-01" required
                   class="border rounded px-3 py-2 text-sm" />
            <button type="submit"
                    class="bg-blue-600 text-white px-3 py-2 rounded text-sm hover:bg-blue-700">
              New Run
            </button>
          </form>
        </div>
    
        <div class="bg-white rounded-lg border overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-gray-50 text-gray-500 text-left">
              <tr>
                <th class="px-4 py-3">Pay Period</th>
                <th class="px-4 py-3">Status</th>
                <th class="px-4 py-3">Total</th>
                <th class="px-4 py-3">Ran At</th>
                <th class="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              <%= if @runs == [] do %>
                <tr>
                  <td colspan="5" class="px-4 py-6 text-center text-gray-400">No runs yet</td>
                </tr>
              <% end %>
              <%= for run <- @runs do %>
                <tr class="border-t hover:bg-gray-50">
                  <td class="px-4 py-3 font-medium"><%= run.pay_period %></td>
                  <td class="px-4 py-3">
                    <span class={["px-2 py-1 rounded-full text-xs font-medium", run_status_badge(run.status)]}>
                      <%= run.status %>
                    </span>
                  </td>
                  <td class="px-4 py-3"><%= if run.total_amount, do: format_money(run.total_amount) %></td>
                  <td class="px-4 py-3 text-gray-400 text-xs">
                    <%= if run.ran_at, do: Calendar.strftime(run.ran_at, "%b %d %H:%M") %>
                  </td>
                  <td class="px-4 py-3">
                    <.link navigate={~p"/app/runs/#{run.id}"}
                           class="text-blue-600 hover:underline text-xs font-medium">
                      View →
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
      <div class="mt-8">
        <h2 class="text-lg font-semibold mb-3">Ledger</h2>

        <div class="flex gap-2 mb-3">
          <%= for {label, type, color} <- [{"All", nil, "gray"}, {"Deposits", "deposit", "green"}, {"Deductions", "payroll_deduction", "red"}, {"Refunds", "refund", "blue"}] do %>
            <button phx-click="filter_tx_type" phx-value-type={type}
                    class={["px-3 py-1.5 rounded-full text-xs font-medium border transition-all",
                      if(@tx_type_filter == type,
                        do: "bg-#{color}-100 border-#{color}-400 text-#{color}-700 ring-2 ring-#{color}-300",
                        else: "bg-white border-gray-200 text-gray-600 hover:bg-gray-50")]}>
              <%= label %>
            </button>
          <% end %>
        </div>

        <div class="bg-white rounded-lg border overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-gray-50 text-gray-500 text-left">
              <tr>
                <th class="px-4 py-3">Type</th>
                <th class="px-4 py-3">Amount</th>
                <th class="px-4 py-3">Description</th>
                <th class="px-4 py-3">Date</th>
              </tr>
            </thead>
            <tbody>
              <%= if @transactions == [] do %>
                <tr>
                  <td colspan="4" class="px-4 py-6 text-center text-gray-400">No transactions</td>
                </tr>
              <% end %>
              <%= for tx <- @transactions do %>
                <tr class="border-t">
                  <td class="px-4 py-3">
                    <span class={["px-2 py-1 rounded-full text-xs font-medium", tx_type_badge(tx.type)]}>
                      <%= tx_type_label(tx.type) %>
                    </span>
                  </td>
                  <td class={["px-4 py-3 font-semibold tabular-nums", tx_amount_class(tx.amount)]}>
                    <%= tx_amount(tx.amount) %>
                  </td>
                  <td class="px-4 py-3 text-gray-500 text-xs"><%= tx.description %></td>
                  <td class="px-4 py-3 text-gray-400 text-xs whitespace-nowrap">
                    <%= Calendar.strftime(tx.inserted_at, "%b %d, %Y %H:%M") %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <div class="flex items-center justify-between px-4 py-3 border-t text-sm text-gray-500">
            <span>Showing <%= length(@transactions) %> per page · newest first</span>
            <div class="flex gap-2">
              <button phx-click="tx_prev" disabled={@tx_cursors == []}
                      class={["px-3 py-1 rounded border text-sm", if(@tx_cursors == [], do: "text-gray-300 border-gray-200 cursor-not-allowed", else: "text-gray-600 hover:bg-gray-50")]}>
                ← Prev
              </button>
              <button phx-click="tx_next" disabled={is_nil(@tx_next_cursor)}
                      class={["px-3 py-1 rounded border text-sm", if(is_nil(@tx_next_cursor), do: "text-gray-300 border-gray-200 cursor-not-allowed", else: "text-gray-600 hover:bg-gray-50")]}>
                Next →
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge("active"), do: "bg-green-100 text-green-700"
  defp status_badge("pending"), do: "bg-yellow-100 text-yellow-700"
  defp status_badge(_), do: "bg-gray-100 text-gray-600"

  defp emp_status_badge("active"), do: "bg-green-100 text-green-700"
  defp emp_status_badge("pending"), do: "bg-yellow-100 text-yellow-700"
  defp emp_status_badge("terminated"), do: "bg-red-100 text-red-700"
  defp emp_status_badge(_), do: "bg-gray-100 text-gray-600"

  defp run_status_badge("draft"), do: "bg-gray-100 text-gray-600"
  defp run_status_badge("calculating"), do: "bg-blue-100 text-blue-700"
  defp run_status_badge("pending_approval"), do: "bg-yellow-100 text-yellow-800"
  defp run_status_badge("approved"), do: "bg-indigo-100 text-indigo-700"
  defp run_status_badge("paying"), do: "bg-purple-100 text-purple-700"
  defp run_status_badge("completed"), do: "bg-green-100 text-green-700"
  defp run_status_badge("failed"), do: "bg-red-100 text-red-700"
  defp run_status_badge(_), do: "bg-gray-100 text-gray-600"

  defp flash_class(:ok), do: "bg-green-50 text-green-700 border-green-200"
  defp flash_class(:error), do: "bg-red-50 text-red-700 border-red-200"

  defp tx_type_badge("deposit"), do: "bg-green-100 text-green-700"
  defp tx_type_badge("refund"), do: "bg-blue-100 text-blue-700"
  defp tx_type_badge("payroll_deduction"), do: "bg-red-100 text-red-700"
  defp tx_type_badge(_), do: "bg-gray-100 text-gray-600"

  defp tx_type_label("deposit"), do: "Deposit"
  defp tx_type_label("refund"), do: "Refund"
  defp tx_type_label("payroll_deduction"), do: "Deduction"
  defp tx_type_label(t), do: t

  defp tx_amount_class(amount) do
    if Decimal.positive?(amount), do: "text-green-700", else: "text-red-600"
  end

  defp tx_amount(amount) do
    if Decimal.positive?(amount) do
      "+ #{format_money(amount)}"
    else
      "− #{format_money(Decimal.abs(amount))}"
    end
  end
end
