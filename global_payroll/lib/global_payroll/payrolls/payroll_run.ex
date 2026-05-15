defmodule GlobalPayroll.Payrolls.PayrollRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "payroll_runs" do
    field(:pay_period, :string)
    field(:status, :string, default: "draft")
    field(:error, :string)
    field(:total_amount, :decimal)
    field(:ran_at, :utc_datetime)
    has_many(:payroll_intents, GlobalPayroll.Payrolls.PayrollIntent)
    has_one(:invoice, GlobalPayroll.Payrolls.Invoice)
    belongs_to(:company, GlobalPayroll.Companies.Company)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payroll_run, attrs) do
    payroll_run
    |> cast(attrs, [:company_id, :pay_period, :status, :error, :total_amount, :ran_at])
    |> validate_required([:company_id, :pay_period])
    |> validate_inclusion(:status, [
      "draft",
      "calculating",
      "pending_approval",
      "approved",
      "paying",
      "completed",
      "failed"
    ])
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> unique_constraint([:company_id, :pay_period])
  end
end
