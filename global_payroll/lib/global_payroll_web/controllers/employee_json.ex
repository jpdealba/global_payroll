defmodule GlobalPayrollWeb.EmployeeJSON do
  def index(%{employees: employees, next_cursor: next_cursor}) do
    %{data: Enum.map(employees, &data/1), next_cursor: next_cursor}
  end

  def show(%{employee: employee}), do: %{data: data(employee)}

  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp data(employee) do
    %{
      id: employee.id,
      company_id: employee.company_id,
      country_tax_id: employee.country_tax_id,
      name: employee.name,
      email: employee.email,
      gross_salary: employee.gross_salary,
      status: employee.status,
      inserted_at: employee.inserted_at,
      updated_at: employee.updated_at
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
