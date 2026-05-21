defmodule GlobalPayroll.Ledger do
  alias GlobalPayroll.Ledgers.CompanyTransaction
  alias GlobalPayroll.{Repo}

  defp create_company_transaction(attrs) do
    %CompanyTransaction{} |> CompanyTransaction.changeset(attrs) |> Repo.insert()
  end

  # Credits the company balance — positive amount.
  def deposit(company_id, amount, reference_id, description \\ "Deposit") do
    create_company_transaction(%{
      company_id: company_id,
      amount: amount,
      type: "deposit",
      reference_id: reference_id,
      description: description
    })
  end

  # Credits the company balance — positive amount, returns funds from a failed payment.
  def refund(company_id, amount, reference_id, description \\ "Payment refund") do
    create_company_transaction(%{
      company_id: company_id,
      amount: amount,
      type: "refund",
      reference_id: reference_id,
      description: description
    })
  end

  # Debits the company balance — negative amount, charged when payroll is approved.
  def payroll_deduction(company_id, amount, reference_id, description \\ "Payroll deduction") do
    create_company_transaction(%{
      company_id: company_id,
      amount: Decimal.negate(amount),
      type: "payroll_deduction",
      reference_id: reference_id,
      description: description
    })
  end
end
