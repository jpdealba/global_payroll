defmodule GlobalPayroll.Employees.PaymentMethod do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payment_methods" do
    belongs_to(:employee, GlobalPayroll.Employees.Employee)
    field(:bank_name, :string)
    field(:account_holder, :string)
    field(:account_number, :string)
    field(:bank_code, :string)
    field(:is_default, :boolean)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment_method, attrs) do
    payment_method
    |> cast(attrs, [
      :employee_id,
      :bank_name,
      :account_holder,
      :account_number,
      :bank_code,
      :is_default
    ])
    |> validate_required([
      :employee_id,
      :bank_name,
      :account_holder,
      :account_number,
      :bank_code,
      :is_default
    ])
    |> unique_constraint(:account_number)
  end
end
