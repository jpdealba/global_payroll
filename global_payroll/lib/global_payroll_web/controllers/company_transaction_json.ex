defmodule GlobalPayrollWeb.CompanyTransactionJSON do
  def index(%{transactions: transactions, next_cursor: next_cursor}) do
    %{data: Enum.map(transactions, &data/1), next_cursor: next_cursor}
  end

  def show(%{transaction: transaction}), do: %{data: data(transaction)}

  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp data(t) do
    %{
      id: t.id,
      company_id: t.company_id,
      amount: t.amount,
      type: t.type,
      reference_id: t.reference_id,
      description: t.description,
      inserted_at: t.inserted_at
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
