defmodule GlobalPayroll.PayrollsTest do
  use GlobalPayroll.DataCase, async: true

  alias GlobalPayroll.Payrolls

  describe "cancel_run/1" do
    test "allows cancel in draft" do
      run = insert_run("draft")
      assert {:ok, %{status: "failed"}} = Payrolls.cancel_run(run.id)
    end

    test "rejects cancel while paying" do
      run = insert_run("paying")
      assert {:error, msg} = Payrolls.cancel_run(run.id)
      assert msg =~ "cannot cancel"
    end
  end

  defp insert_run(status) do
    company_id = Ecto.UUID.generate()

    {:ok, company} =
      %GlobalPayroll.Companies.Company{}
      |> GlobalPayroll.Companies.Company.changeset(%{
        name: "Test Co",
        country: "MX",
        billing_email: "billing-#{company_id}@test.com",
        status: "active"
      })
      |> Repo.insert()

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
