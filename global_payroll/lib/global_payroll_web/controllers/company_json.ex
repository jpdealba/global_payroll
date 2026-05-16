defmodule GlobalPayrollWeb.CompanyJSON do
  alias GlobalPayroll.Companies

  def index(%{companies: companies, next_cursor: next_cursor}) do
    %{data: Enum.map(companies, &data/1), next_cursor: next_cursor}
  end

  def show(%{company: company}), do: %{data: data(company)}

  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp data(company) do
    %{
      id: company.id,
      name: company.name,
      country: company.country,
      billing_email: company.billing_email,
      status: company.status,
      balance: Companies.get_company_balance(company.id),
      inserted_at: company.inserted_at,
      updated_at: company.updated_at
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
