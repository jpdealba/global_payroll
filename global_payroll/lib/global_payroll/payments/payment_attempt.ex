defmodule GlobalPayroll.Payments.PaymentAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payment_attempts" do
    belongs_to(:payroll_intent, GlobalPayroll.Payrolls.PayrollIntent)
    field(:attempt_number, :integer)
    field(:status, :string)
    field(:error, :string)
    field(:attempted_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment_attempt, attrs) do
    payment_attempt
    |> cast(attrs, [:payroll_intent_id, :attempt_number, :status, :error, :attempted_at])
    |> validate_required([:payroll_intent_id, :attempt_number, :status, :attempted_at])
    |> validate_inclusion(:status, ["succeeded", "failed"])
    |> validate_number(:attempt_number, greater_than_or_equal_to: 1, less_than_or_equal_to: 3)
    |> unique_constraint([:payroll_intent_id, :attempt_number])
  end
end
