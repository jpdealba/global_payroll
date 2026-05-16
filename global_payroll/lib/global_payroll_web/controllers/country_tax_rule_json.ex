defmodule GlobalPayrollWeb.CountryTaxRuleJSON do
  def index(%{rules: rules, next_cursor: next_cursor}) do
    %{data: Enum.map(rules, &data/1), next_cursor: next_cursor}
  end

  def show(%{rule: rule}), do: %{data: data(rule)}

  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp data(rule) do
    %{
      id: rule.id,
      country_code: rule.country_code,
      country_name: rule.country_name,
      income_tax_rate: rule.income_tax_rate,
      social_security_rate: rule.social_security_rate,
      currency: rule.currency,
      inserted_at: rule.inserted_at
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
