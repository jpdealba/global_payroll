defmodule GlobalPayrollWeb.CompanyJSON do
  alias GlobalPayroll.Companies

  def index(%{companies: companies, next_cursor: next_cursor}) do
    %{data: Enum.map(companies, &data/1), next_cursor: next_cursor}
  end

  def show(%{company: company}), do: %{data: data(company)}

  def invoices(%{invoices: invoices}), do: %{data: Enum.map(invoices, &invoice_data/1)}

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

  defp invoice_data(invoice) do
    %{
      id: invoice.id,
      company_id: invoice.company_id,
      payroll_run_id: invoice.payroll_run_id,
      total_gross_salaries: invoice.total_gross_salaries,
      total_taxes_withheld: invoice.total_taxes_withheld,
      total_platform_fees: invoice.total_platform_fees,
      total_amount: invoice.total_amount,
      status: invoice.status,
      issued_at: invoice.issued_at,
      paid_at: invoice.paid_at,
      inserted_at: invoice.inserted_at
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
