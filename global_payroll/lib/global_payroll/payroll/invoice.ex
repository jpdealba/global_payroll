defmodule GlobalPayroll.Payroll.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invoices" do
    field(:total_gross_salaries, :decimal)
    field(:total_taxes_withheld, :decimal)
    field(:total_platform_fees, :decimal)
    field(:total_amount, :decimal)
    field(:status, :string, default: "unpaid")
    field(:issued_at, :utc_datetime)
    field(:paid_at, :utc_datetime)
    belongs_to(:company, GlobalPayroll.Companies.Company)
    belongs_to(:payroll_run, GlobalPayroll.Payroll.PayrollRun)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :company_id,
      :payroll_run_id,
      :total_gross_salaries,
      :total_taxes_withheld,
      :total_platform_fees,
      :total_amount,
      :status,
      :issued_at,
      :paid_at
    ])
    |> validate_required([
      :company_id,
      :payroll_run_id,
      :total_gross_salaries,
      :total_taxes_withheld,
      :total_platform_fees,
      :total_amount
    ])
    |> validate_inclusion(:status, ["unpaid", "paid"])
    |> validate_number(:total_gross_salaries, greater_than_or_equal_to: 0)
    |> validate_number(:total_taxes_withheld, greater_than_or_equal_to: 0)
    |> validate_number(:total_platform_fees, greater_than_or_equal_to: 0)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> unique_constraint([:payroll_run_id])
  end
end
