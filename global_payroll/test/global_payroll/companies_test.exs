defmodule GlobalPayroll.CompaniesTest do
  use GlobalPayroll.DataCase, async: true

  alias GlobalPayroll.{Companies, Ledger}

  describe "get_company_balance/1" do
    test "returns zero when the company has no transactions" do
      {:ok, company} =
        Companies.create_company(%{
          name: "Empty Co",
          country: "MX",
          billing_email: "empty@example.com",
          status: "active"
        })

      assert Decimal.equal?(Companies.get_company_balance(company.id), Decimal.new("0"))
    end

    test "sums deposits, deductions, and refunds correctly" do
      {:ok, company} =
        Companies.create_company(%{
          name: "Balance Co",
          country: "MX",
          billing_email: "balance@example.com",
          status: "active"
        })

      Ledger.deposit(company.id, Decimal.new("1000"), Ecto.UUID.generate())
      Ledger.payroll_deduction(company.id, Decimal.new("300"), Ecto.UUID.generate())
      Ledger.refund(company.id, Decimal.new("50"), Ecto.UUID.generate())

      # 1000 - 300 + 50 = 750
      assert Decimal.equal?(Companies.get_company_balance(company.id), Decimal.new("750"))
    end
  end
end
