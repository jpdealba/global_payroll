defmodule GlobalPayroll.PaymentsTest do
  use GlobalPayroll.DataCase, async: true

  alias GlobalPayroll.{Payments, Companies, Ledger, Taxes, Payrolls}
  alias GlobalPayroll.Employees

  describe "process_result/1 — success" do
    test "marks intent as completed and creates a payslip" do
      {_company, _run, intent} = setup_paying_intent()

      assert {:ok, :completed} = Payments.process_result(%{"intent_id" => intent.id, "status" => "succeeded"})

      {:ok, result} = Payrolls.get_intent_with_preloads(intent.id)
      assert result.status == "completed"
      assert result.payslip != nil
      assert Decimal.equal?(result.payslip.net_salary, intent.net_salary)
    end

    test "deducts net salary from the company ledger" do
      {company, _run, intent} = setup_paying_intent()
      Ledger.deposit(company.id, Decimal.new("10000"), Ecto.UUID.generate())
      balance_before = Companies.get_company_balance(company.id)

      Payments.process_result(%{"intent_id" => intent.id, "status" => "succeeded"})

      balance_after = Companies.get_company_balance(company.id)
      expected = Decimal.sub(balance_before, intent.net_salary)
      assert Decimal.equal?(balance_after, expected)
    end

    test "is idempotent: returns already_settled if intent is already completed" do
      {_company, _run, intent} = setup_paying_intent()
      Payments.process_result(%{"intent_id" => intent.id, "status" => "succeeded"})

      assert {:error, :already_settled} =
               Payments.process_result(%{"intent_id" => intent.id, "status" => "succeeded"})
    end
  end

  describe "process_result/1 — failure at max retries" do
    test "marks intent as failed and issues a refund to the company ledger" do
      {company, _run, intent} = setup_paying_intent(retry_count: 2)
      balance_before = Companies.get_company_balance(company.id)

      # retry_count 2 means this is the 3rd attempt — at the limit, so no more retries
      Payments.process_result(%{"intent_id" => intent.id, "status" => "failed", "error" => "timeout"})

      {:ok, result} = Payrolls.get_intent_with_preloads(intent.id)
      assert result.status == "failed"

      balance_after = Companies.get_company_balance(company.id)
      assert Decimal.compare(balance_after, balance_before) == :gt
    end

    test "is idempotent: returns already_settled if intent is already failed" do
      {_company, _run, intent} = setup_paying_intent(retry_count: 2)
      Payments.process_result(%{"intent_id" => intent.id, "status" => "failed", "error" => "timeout"})

      assert {:error, :already_settled} =
               Payments.process_result(%{"intent_id" => intent.id, "status" => "failed", "error" => "timeout"})
    end
  end

  # --- Helpers ---

  defp setup_paying_intent(opts \\ []) do
    retry_count = Keyword.get(opts, :retry_count, 0)

    {:ok, tax_rule} =
      Taxes.create_country_tax_rule(%{
        country_code: "PM-#{System.unique_integer()}",
        country_name: "Test Country",
        income_tax_rate: Decimal.new("0.10"),
        social_security_rate: Decimal.new("0.05"),
        currency: "USD"
      })

    {:ok, company} =
      Companies.create_company(%{
        name: "Pay Co #{System.unique_integer()}",
        country: "US",
        billing_email: "pay-#{System.unique_integer()}@test.com",
        status: "active"
      })

    {:ok, employee} =
      Employees.create_employee(%{
        name: "Employee #{System.unique_integer()}",
        email: "emp-#{System.unique_integer()}@test.com",
        gross_salary: Decimal.new("1000"),
        status: "active",
        company_id: company.id,
        country_tax_id: tax_rule.id
      })

    {:ok, run} =
      %GlobalPayroll.Payrolls.PayrollRun{}
      |> GlobalPayroll.Payrolls.PayrollRun.changeset(%{
        company_id: company.id,
        pay_period: "2026-05",
        status: "paying"
      })
      |> GlobalPayroll.Repo.insert()

    {:ok, intent} =
      %GlobalPayroll.Payrolls.PayrollIntent{}
      |> GlobalPayroll.Payrolls.PayrollIntent.changeset(%{
        payroll_run_id: run.id,
        company_id: company.id,
        employee_id: employee.id,
        gross_salary: Decimal.new("1000"),
        income_tax: Decimal.new("100"),
        social_security: Decimal.new("50"),
        net_salary: Decimal.new("850"),
        platform_fee: Decimal.new("29"),
        retry_count: retry_count
      })
      |> GlobalPayroll.Repo.insert()

    {company, run, intent}
  end
end
