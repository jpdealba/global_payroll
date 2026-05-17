defmodule GlobalPayrollWeb.Live.CompaniesLive do
  use GlobalPayrollWeb, :live_view
  alias GlobalPayroll.{Companies, Taxes}

  @chunk_size 5_000

  @preset_templates [
    %{name: "Acme Corporation", country: "US"},
    %{name: "GlobalTech Mexico", country: "MX"},
    %{name: "EuroSoft España", country: "ES"},
    %{name: "Pacific Industries", country: "US"},
    %{name: "Meridian Group", country: "MX"}
  ]

  @first_names ~w(Alice Bob Carlos Diana Erik Fatima Gabriel Helena Ivan Julia
                  Kevin Laura Miguel Nora Omar Priya Quinn Rosa Stefan Tania
                  Uma Victor Wendy Xavier Yara Zoe Ahmed Bianca Chen Diego)
  @last_names ~w(Smith Johnson Williams Brown Jones Garcia Miller Davis Wilson
                 Moore Taylor Anderson Thomas Jackson White Harris Martinez
                 Clark Lewis Lee Walker Hall Allen Young Hernandez King)
  @banks [
    {"Chase", "CHASUS33"},
    {"BBVA", "BBVAESMM"},
    {"Santander", "BSCHESMM"},
    {"HSBC", "HSBCUS33"},
    {"Citi", "CITIUS33"}
  ]

  def mount(_params, _session, socket) do
    {companies, _} = Companies.list_companies()
    {:ok, assign(socket, companies: companies, alert: nil, seed_progress: nil)}
  end

  def handle_event("create_company", params, socket) do
    case Companies.create_company(params) do
      {:ok, _} ->
        {companies, _} = Companies.list_companies()
        {:noreply, assign(socket, companies: companies, alert: {:ok, "Company created"})}

      {:error, changeset} ->
        {:noreply, assign(socket, alert: {:error, changeset_errors(changeset)})}
    end
  end

  def handle_event("activate", %{"id" => id}, socket) do
    Companies.update_company(id, %{"status" => "active"})
    {companies, _} = Companies.list_companies()
    {:noreply, assign(socket, companies: companies, alert: {:ok, "Company activated"})}
  end

  def handle_event("seed", %{"preset" => preset_idx, "count" => count_str}, socket) do
    template = Enum.at(@preset_templates, String.to_integer(preset_idx))
    count = count_str |> String.to_integer() |> max(1) |> min(100_000)
    lv_pid = self()

    Task.start(fn -> run_seed(lv_pid, template, count) end)

    {:noreply, assign(socket, seed_progress: {0, count})}
  end

  def handle_info({:seed_progress, inserted, total}, socket) do
    {:noreply, assign(socket, seed_progress: {inserted, total})}
  end

  def handle_info({:seed_done, company_id}, socket) do
    {:noreply, socket |> assign(seed_progress: nil) |> push_navigate(to: ~p"/app/companies/#{company_id}")}
  end

  # --- Seed helpers ---

  defp run_seed(lv_pid, template, total_count) do
    n = :rand.uniform(99_999)
    slug = template.name |> String.downcase() |> String.replace(~r/[^a-z]/, "")

    {:ok, company} = Companies.create_company(%{
      name: template.name,
      country: template.country,
      billing_email: "billing.#{n}@#{slug}.com",
      registration_number: "REG-#{n}"
    })
    Companies.update_company(company.id, %{"status" => "active"})

    {tax_rules, _} = Taxes.list_country_tax_rules()
    tax_ids = Enum.map(tax_rules, & &1.id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    total_count
    |> into_chunks(@chunk_size)
    |> Enum.reduce(0, fn chunk_count, inserted ->
      emp_rows = Enum.map(1..chunk_count, fn _ -> build_employee_row(company.id, tax_ids, now) end)

      {_, employees} =
        GlobalPayroll.Repo.insert_all(
          GlobalPayroll.Employees.Employee,
          emp_rows,
          returning: [:id]
        )

      pm_rows = Enum.map(employees, fn e -> build_payment_method_row(e.id, now) end)
      GlobalPayroll.Repo.insert_all(GlobalPayroll.Employees.PaymentMethod, pm_rows)

      new_total = inserted + chunk_count
      send(lv_pid, {:seed_progress, new_total, total_count})
      new_total
    end)

    send(lv_pid, {:seed_done, company.id})
  end

  defp build_employee_row(company_id, tax_ids, now) do
    id = Ecto.UUID.generate()
    first = Enum.random(@first_names)
    last = Enum.random(@last_names)
    gross = (50 + :rand.uniform(100)) * 100

    %{
      id: id,
      name: "#{first} #{last}",
      email: "#{String.downcase(first)}.#{String.replace(id, "-", "")}@demo.com",
      gross_salary: Decimal.new(gross),
      status: "active",
      company_id: company_id,
      country_tax_id: Enum.random(tax_ids),
      inserted_at: now,
      updated_at: now
    }
  end

  defp build_payment_method_row(employee_id, now) do
    {bank_name, bank_code} = Enum.random(@banks)

    %{
      id: Ecto.UUID.generate(),
      employee_id: employee_id,
      bank_name: bank_name,
      account_holder: "Employee Account",
      account_number: "ACC-#{employee_id}",
      bank_code: bank_code,
      is_default: true,
      inserted_at: now,
      updated_at: now
    }
  end

  defp into_chunks(total, chunk_size) do
    full = div(total, chunk_size)
    remainder = rem(total, chunk_size)
    chunks = List.duplicate(chunk_size, full)
    if remainder > 0, do: chunks ++ [remainder], else: chunks
  end

  # --- Render ---

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold mb-6">Companies</h1>

      <%= if @alert do %>
        <div class={["mb-4 p-3 rounded text-sm border", flash_class(elem(@alert, 0))]}>
          <%= elem(@alert, 1) %>
        </div>
      <% end %>

      <div class="mb-6 p-4 bg-indigo-50 rounded-lg border border-indigo-200">
        <h2 class="font-semibold mb-3 text-indigo-800">Generate Demo Data</h2>
        <%= if @seed_progress do %>
          <% {inserted, total} = @seed_progress %>
          <div class="text-sm text-indigo-700 mb-2">
            Generating employees… <span class="font-semibold"><%= inserted %></span> / <%= total %>
          </div>
          <div class="w-full bg-indigo-200 rounded-full h-2.5">
            <div class="bg-indigo-600 h-2.5 rounded-full transition-all duration-300"
                 style={"width: #{if total > 0, do: trunc(inserted / total * 100), else: 0}%"}>
            </div>
          </div>
        <% else %>
          <form phx-submit="seed" class="flex flex-wrap gap-3 items-end">
            <div>
              <div class="text-xs text-indigo-600 mb-1">Company</div>
              <select name="preset" class="border rounded px-3 py-2 text-sm bg-white">
                <option value="0">Acme Corporation (US)</option>
                <option value="1">GlobalTech Mexico (MX)</option>
                <option value="2">EuroSoft España (ES)</option>
                <option value="3">Pacific Industries (US)</option>
                <option value="4">Meridian Group (MX)</option>
              </select>
            </div>
            <div>
              <div class="text-xs text-indigo-600 mb-1">Employees (max 100k)</div>
              <input name="count" type="number" value="500" min="1" max="100000"
                     class="border rounded px-3 py-2 text-sm w-32" />
            </div>
            <button type="submit"
                    class="bg-indigo-600 text-white px-4 py-2 rounded text-sm hover:bg-indigo-700 font-medium">
              Generate →
            </button>
          </form>
        <% end %>
      </div>

      <form phx-submit="create_company" class="mb-8 p-4 bg-white rounded-lg border">
        <h2 class="font-semibold mb-3">New Company</h2>
        <div class="grid grid-cols-2 gap-3">
          <input name="name" placeholder="Company name" required
                 class="border rounded px-3 py-2 text-sm" />
          <input name="registration_number" placeholder="Registration number" required
                 class="border rounded px-3 py-2 text-sm" />
          <input name="billing_email" type="email" placeholder="Billing email" required
                 class="border rounded px-3 py-2 text-sm" />
          <input name="country" placeholder="Country (e.g. MX, US)" required
                 class="border rounded px-3 py-2 text-sm" />
          <div class="col-span-2">
            <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700">
              Create
            </button>
          </div>
        </div>
      </form>

      <div class="bg-white rounded-lg border overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-gray-50 text-gray-500 text-left">
            <tr>
              <th class="px-4 py-3">Name</th>
              <th class="px-4 py-3">Country</th>
              <th class="px-4 py-3">Billing Email</th>
              <th class="px-4 py-3">Status</th>
              <th class="px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            <%= if @companies == [] do %>
              <tr>
                <td colspan="5" class="px-4 py-8 text-center text-gray-400">No companies yet</td>
              </tr>
            <% end %>
            <%= for company <- @companies do %>
              <tr class="border-t hover:bg-gray-50">
                <td class="px-4 py-3">
                  <.link navigate={~p"/app/companies/#{company.id}"}
                         class="text-blue-600 hover:underline font-medium">
                    <%= company.name %>
                  </.link>
                </td>
                <td class="px-4 py-3 text-gray-600"><%= company.country %></td>
                <td class="px-4 py-3 text-gray-600"><%= company.billing_email %></td>
                <td class="px-4 py-3">
                  <span class={["px-2 py-1 rounded-full text-xs font-medium", status_badge(company.status)]}>
                    <%= company.status %>
                  </span>
                </td>
                <td class="px-4 py-3">
                  <%= if company.status == "pending" do %>
                    <button phx-click="activate" phx-value-id={company.id}
                            class="text-sm text-green-600 hover:text-green-800 font-medium">
                      Activate →
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  defp status_badge("active"), do: "bg-green-100 text-green-700"
  defp status_badge("pending"), do: "bg-yellow-100 text-yellow-700"
  defp status_badge(_), do: "bg-gray-100 text-gray-600"

  defp flash_class(:ok), do: "bg-green-50 text-green-700 border-green-200"
  defp flash_class(:error), do: "bg-red-50 text-red-700 border-red-200"
end
