defmodule GlobalPayroll.PayrollsTest do
  use GlobalPayroll.DataCase, async: true

  alias GlobalPayroll.{Payrolls, Companies, Ledger, Taxes}
  alias GlobalPayroll.Employees

  describe "cancel_run/1" do
    test "allows cancel in draft" do
      run = insert_run("draft")
      assert {:ok, %{status: "failed"}} = Payrolls.cancel_run(run.id)
    end

    test "allows cancel in pending_approval" do
      run = insert_run("pending_approval")
      assert {:ok, %{status: "failed"}} = Payrolls.cancel_run(run.id)
    end

    test "rejects cancel while paying" do
      run = insert_run("paying")
      assert {:error, msg} = Payrolls.cancel_run(run.id)
      assert msg =~ "cannot cancel"
    end
  end

  describe "calculate_run/1" do
    test "fails when the company has no active employees" do
      company = insert_company()
      Ledger.deposit(company.id, Decimal.new("10000"), Ecto.UUID.generate())
      {:ok, run} = Payrolls.create_run(company.id, "2026-05")

      assert {:error, "no active employees found"} = Payrolls.calculate_run(run.id)
    end

    test "fails when the company has insufficient balance" do
      {company, tax_rule} = insert_company_with_tax_rule("MX-INSUF")
      insert_active_employee(company, tax_rule, Decimal.new("5000"))
      # Balance is 0 — not enough to cover net salary + platform fee
      {:ok, run} = Payrolls.create_run(company.id, "2026-06")

      assert {:error, msg} = Payrolls.calculate_run(run.id)
      assert msg =~ "insufficient balance"
    end

    test "creates intents with the correct net pay and transitions run to pending_approval" do
      {company, tax_rule} = insert_company_with_tax_rule("MX-CALC")
      # 10% income tax, 5% social security → net = gross * 0.85
      insert_active_employee(company, tax_rule, Decimal.new("1000"))
      Ledger.deposit(company.id, Decimal.new("10000"), Ecto.UUID.generate())
      {:ok, run} = Payrolls.create_run(company.id, "2026-07")

      assert {:ok, _} = Payrolls.calculate_run(run.id)

      {:ok, run} = Payrolls.get_run(run.id)
      assert run.status == "pending_approval"

      [intent] = Payrolls.list_intents(run.id)
      assert Decimal.equal?(intent.gross_salary, Decimal.new("1000"))
      assert Decimal.equal?(intent.income_tax, Decimal.new("100"))
      assert Decimal.equal?(intent.social_security, Decimal.new("50"))
      assert Decimal.equal?(intent.net_salary, Decimal.new("850"))
    end
  end

  # --- Helpers ---

  defp insert_company do
    {:ok, company} =
      Companies.create_company(%{
        name: "Test Co #{System.unique_integer()}",
        country: "MX",
        billing_email: "billing-#{System.unique_integer()}@test.com",
        status: "active"
      })

    company
  end

  defp insert_company_with_tax_rule(country_code) do
    {:ok, tax_rule} =
      Taxes.create_country_tax_rule(%{
        country_code: country_code,
        country_name: "Mexico #{country_code}",
        income_tax_rate: Decimal.new("0.10"),
        social_security_rate: Decimal.new("0.05"),
        currency: "MXN"
      })

    {:ok, company} =
      Companies.create_company(%{
        name: "Company #{country_code}",
        country: country_code,
        billing_email: "billing-#{country_code}@test.com",
        status: "active"
      })

    {company, tax_rule}
  end

  defp insert_active_employee(company, tax_rule, gross_salary) do
    {:ok, employee} =
      Employees.create_employee(%{
        name: "Employee #{System.unique_integer()}",
        email: "emp-#{System.unique_integer()}@test.com",
        gross_salary: gross_salary,
        status: "active",
        company_id: company.id,
        country_tax_id: tax_rule.id
      })

    employee
  end

  defp insert_run(status) do
    {:ok, company} =
      Companies.create_company(%{
        name: "Test Co #{System.unique_integer()}",
        country: "MX",
        billing_email: "billing-#{System.unique_integer()}@test.com",
        status: "active"
      })

    {:ok, run} =
      %GlobalPayroll.Payrolls.PayrollRun{}
      |> GlobalPayroll.Payrolls.PayrollRun.changeset(%{
        company_id: company.id,
        pay_period: "2026-05",
        status: status
      })
      |> Repo.insert()

    run
  end
end
