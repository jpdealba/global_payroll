defmodule GlobalPayrollWeb.EmployeeJSON do
  def index(%{employees: employees, next_cursor: next_cursor}) do
    %{data: Enum.map(employees, &data/1), next_cursor: next_cursor}
  end

  def show(%{employee: employee}), do: %{data: data(employee)}

  def payslips(%{payslips: payslips}), do: %{data: Enum.map(payslips, &payslip_data/1)}

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

  defp payslip_data(payslip) do
    %{
      id: payslip.id,
      payroll_intent_id: payslip.payroll_intent_id,
      employee_id: payslip.employee_id,
      pay_period: payslip.pay_period,
      gross_salary: payslip.gross_salary,
      income_tax: payslip.income_tax,
      social_security: payslip.social_security,
      net_salary: payslip.net_salary,
      generated_at: payslip.generated_at,
      inserted_at: payslip.inserted_at
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
