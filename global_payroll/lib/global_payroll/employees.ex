defmodule GlobalPayroll.Employees do
  import Ecto.Query
  alias GlobalPayroll.Employees.{Employee, PaymentMethod}
  alias GlobalPayroll.{Pagination, Repo}

  def get_employee(id) do
    case Repo.get(Employee, id) do
      nil -> {:error, :not_found}
      employee -> {:ok, employee}
    end
  end

  def create_employee(attrs) do
    %Employee{} |> Employee.changeset(attrs) |> Repo.insert()
  end

  def update_employee(id, attrs) do
    case Repo.get(Employee, id) do
      nil -> {:error, :not_found}
      employee -> employee |> Employee.changeset(attrs) |> Repo.update()
    end
  end

  def list_employees_by_company(company_id, cursor \\ nil, per_page \\ 20) do
    Employee
    |> where([e], e.company_id == ^company_id)
    |> Pagination.paginate(cursor, per_page)
    |> Repo.all()
    |> then(&{&1, Pagination.next_cursor(&1, per_page)})
  end

  # Returns all active employees for a company — used by payroll to know who gets paid.
  def list_active_employees(company_id) do
    Employee
    |> where([e], e.company_id == ^company_id and e.status == "active")
    |> Repo.all()
  end

  def list_payment_methods(employee_id) do
    PaymentMethod
    |> where([pm], pm.employee_id == ^employee_id)
    |> Repo.all()
  end

  def get_payment_method(id) do
    case Repo.get(PaymentMethod, id) do
      nil -> {:error, :not_found}
      method -> {:ok, method}
    end
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

  def update_payment_method(id, attrs) do
    case Repo.get(PaymentMethod, id) do
      nil -> {:error, :not_found}
      method -> method |> PaymentMethod.changeset(attrs) |> Repo.update()
    end
  end

  def delete_payment_method(id) do
    case Repo.get(PaymentMethod, id) do
      nil -> {:error, :not_found}
      method -> Repo.delete(method)
    end
  end

  def get_default_payment_method(employee_id) do
    PaymentMethod
    |> where([pm], pm.employee_id == ^employee_id and pm.is_default == true)
    |> Repo.one()
  end
end
