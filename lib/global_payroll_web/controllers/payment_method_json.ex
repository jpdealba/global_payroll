defmodule GlobalPayrollWeb.PaymentMethodJSON do
  def index(%{methods: methods}), do: %{data: Enum.map(methods, &data/1)}

  def show(%{method: method}), do: %{data: data(method)}

  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp data(method) do
    %{
      id: method.id,
      employee_id: method.employee_id,
      bank_name: method.bank_name,
      account_holder: method.account_holder,
      account_number: method.account_number,
      bank_code: method.bank_code,
      is_default: method.is_default,
      inserted_at: method.inserted_at,
      updated_at: method.updated_at
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
