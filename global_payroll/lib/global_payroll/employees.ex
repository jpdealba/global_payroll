defmodule GlobalPayroll.Employees do
  import Ecto.Query
  alias GlobalPayroll.Employees.{Employee, PaymentMethod}
  alias GlobalPayroll.{Query, Repo}

  def create_employee(attrs) do
    %Employee{} |> Employee.changeset(attrs) |> Repo.insert()
  end

  def list_employees_by_company(company_id, cursor \\ nil, per_page \\ 20) do
    Employee
    |> where([e], e.company_id == ^company_id)
    |> Query.paginate(cursor, per_page)
    |> Repo.all()
    |> then(&{&1, Query.next_cursor(&1, per_page)})
  end

  # Returns all active employees for a company — used by payroll to know who gets paid.
  def list_active_employees(company_id) do
    Employee
    |> where([e], e.company_id == ^company_id and e.status == "active")
    |> Repo.all()
  end

  # Adds a payment method to an employee.
  # If is_default is true, unsets the previous default first — both ops run in a transaction.
  def add_payment_method(employee_id, attrs) do
    attrs = Map.put(attrs, "employee_id", employee_id)

    Repo.transaction(fn ->
      if Map.get(attrs, "is_default") || Map.get(attrs, :is_default) do
        from(pm in PaymentMethod, where: pm.employee_id == ^employee_id)
        |> Repo.update_all(set: [is_default: false])
      end

      case %PaymentMethod{} |> PaymentMethod.changeset(attrs) |> Repo.insert() do
        {:ok, method} -> method
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def get_default_payment_method(employee_id) do
    PaymentMethod
    |> where([pm], pm.employee_id == ^employee_id and pm.is_default == true)
    |> Repo.one()
  end
end
