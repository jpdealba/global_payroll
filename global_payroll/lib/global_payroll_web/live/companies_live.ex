defmodule GlobalPayrollWeb.Live.CompaniesLive do
  use GlobalPayrollWeb, :live_view
  alias GlobalPayroll.Companies

  def mount(_params, _session, socket) do
    {companies, _} = Companies.list_companies()
    {:ok, assign(socket, companies: companies, alert: nil)}
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

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold mb-6">Companies</h1>

      <%= if @alert do %>
        <div class={["mb-4 p-3 rounded text-sm border", flash_class(elem(@alert, 0))]}>
          <%= elem(@alert, 1) %>
        </div>
      <% end %>

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

  defp status_badge("active"), do: "bg-green-100 text-green-700"
  defp status_badge("pending"), do: "bg-yellow-100 text-yellow-700"
  defp status_badge(_), do: "bg-gray-100 text-gray-600"

  defp flash_class(:ok), do: "bg-green-50 text-green-700 border-green-200"
  defp flash_class(:error), do: "bg-red-50 text-red-700 border-red-200"
end
