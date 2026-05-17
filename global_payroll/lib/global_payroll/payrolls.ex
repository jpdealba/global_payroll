defmodule GlobalPayroll.Payrolls do
  import Ecto.Query
  alias GlobalPayroll.Payrolls.{PayrollRun, PayrollIntent}
  alias GlobalPayroll.Employees.Employee
  alias GlobalPayroll.Taxes.CountryTaxRule
  alias GlobalPayroll.{Pagination, Repo, Companies}

  @chunk_size 500

  # Flat fee charged to the company per employee on every payroll run.
  @platform_fee Decimal.new("29")

  # The state machine — each state can only move forward to the next one.
  # Any other transition is rejected before touching the database.
  #
  #   draft → calculating → pending_approval → approved → paying → completed
  #                                                                    ↑
  #                                            (failed is a special terminal state,
  #                                             reachable from any state on error)
  @valid_transitions %{
    "draft" => "calculating",
    "calculating" => "pending_approval",
    "pending_approval" => "approved",
    "approved" => "paying",
    "paying" => "completed"
  }

  # Creates a new payroll run in draft status.
  # A company can only have one run per pay_period (enforced by unique constraint).
  def create_run(company_id, pay_period) do
    %PayrollRun{}
    |> PayrollRun.changeset(%{company_id: company_id, pay_period: pay_period})
    |> Repo.insert()
  end

  def list_runs(company_id, cursor \\ nil, per_page \\ 20) do
    PayrollRun
    |> where([r], r.company_id == ^company_id)
    |> Pagination.paginate(cursor, per_page)
    |> Repo.all()
    |> then(&{&1, Pagination.next_cursor(&1, per_page)})
  end

  def get_run(id) do
    case Repo.get(PayrollRun, id) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  def list_intents(run_id) do
    PayrollIntent
    |> where([i], i.payroll_run_id == ^run_id)
    |> Repo.all()
  end

  def list_payslips_by_run(run_id) do
    alias GlobalPayroll.Payrolls.{Payslip, PayrollIntent}
    Payslip
    |> join(:inner, [s], i in PayrollIntent, on: s.payroll_intent_id == i.id)
    |> where([s, i], i.payroll_run_id == ^run_id)
    |> Repo.all()
  end

  def list_payslips_by_employee(employee_id) do
    alias GlobalPayroll.Payrolls.Payslip
    Payslip
    |> where([s], s.employee_id == ^employee_id)
    |> Repo.all()
  end

  def list_invoices_by_company(company_id) do
    alias GlobalPayroll.Payrolls.Invoice
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> Repo.all()
  end

  def approve_run(run_id) do
    with {:ok, run} <- get_run(run_id),
         :ok <- validate_transition(run.status, "approved") do
      transition(run, "approved")
    end
  end

  def cancel_run(run_id) do
    with {:ok, run} <- get_run(run_id) do
      mark_failed(run, "cancelled")
    end
  end

  # Entry point called by the Broadway worker after dequeuing a calculate_payroll job.
  # Validates the state machine first — if the run is not in draft, it rejects immediately.
  # Delegates the real work to do_calculate/1 so we always have access to `run` if something fails.
  def calculate_run(run_id) do
    with {:ok, run} <- get_run(run_id),
         :ok <- validate_calculable(run.status) do
      do_calculate(run)
    end
  end

  # --- Private ---

  defp do_calculate(run) do
    with {:ok, total} <- compute_expected_total(run.company_id),
         :ok <- check_balance(run.company_id, total),
         {:ok, run} <- maybe_transition_to_calculating(run) do
      insert_intents_in_chunks(run, total)
    else
      {:error, reason} -> mark_failed(run, reason)
    end
  end

  # Computes the total expected cost via one aggregate DB query — no employee rows loaded.
  # Total = SUM(net_salary + platform_fee) per active employee.
  defp compute_expected_total(company_id) do
    result =
      from(e in Employee,
        join: t in CountryTaxRule, on: e.country_tax_id == t.id,
        where: e.company_id == ^company_id and e.status == "active",
        select: %{
          count: count(e.id),
          net_sum: sum(fragment("? * (1 - ? - ?)", e.gross_salary, t.income_tax_rate, t.social_security_rate))
        }
      )
      |> Repo.one()

    case result do
      %{count: 0} -> {:error, "no active employees found"}
      %{count: n, net_sum: net} ->
        {:ok, Decimal.add(net, Decimal.mult(@platform_fee, Decimal.new(n)))}
    end
  end

  # Streams employees @chunk_size at a time — memory stays bounded regardless of run size.
  # Each chunk is calculated and inserted independently, avoiding PostgreSQL's bind parameter limit.
  # Everything runs in one transaction so a mid-run failure rolls all inserts back.
  # Inserts intents in chunks and transitions to pending_approval atomically.
  # calculating was already committed before this — if this transaction fails,
  # the run stays in calculating and Broadway retries safely (see validate_calculable).
  defp insert_intents_in_chunks(run, total) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      tax_rules =
        from(t in CountryTaxRule,
          where:
            t.id in subquery(
              from e in Employee,
                where: e.company_id == ^run.company_id and e.status == "active",
                select: e.country_tax_id
            )
        )
        |> Repo.all()
        |> Map.new(fn t -> {t.id, t} end)

      Employee
      |> where([e], e.company_id == ^run.company_id and e.status == "active")
      |> Repo.stream()
      |> Stream.chunk_every(@chunk_size)
      |> Enum.each(fn chunk ->
        rows =
          Task.async_stream(
            chunk,
            fn e -> build_intent_row(%{e | country_tax_rule: Map.fetch!(tax_rules, e.country_tax_id)}, run, now) end,
            ordered: false
          )
          |> Enum.map(fn {:ok, row} -> row end)

        Repo.insert_all(PayrollIntent, rows)
      end)

      run
      |> PayrollRun.changeset(%{status: "pending_approval", total_amount: total, ran_at: now})
      |> Repo.update!()
    end)
    |> case do
      {:ok, _} -> {:ok, run}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_intent_row(employee, run, now) do
    tax = employee.country_tax_rule
    gross = employee.gross_salary
    income_tax = Decimal.mult(gross, tax.income_tax_rate)
    social_security = Decimal.mult(gross, tax.social_security_rate)
    net_salary = gross |> Decimal.sub(income_tax) |> Decimal.sub(social_security)

    %{
      id: Ecto.UUID.generate(),
      payroll_run_id: run.id,
      company_id: run.company_id,
      employee_id: employee.id,
      gross_salary: gross,
      income_tax: income_tax,
      social_security: social_security,
      net_salary: net_salary,
      platform_fee: @platform_fee,
      status: "pending",
      retry_count: 0,
      inserted_at: now,
      updated_at: now
    }
  end

  defp check_balance(company_id, total) do
    balance = Companies.get_company_balance(company_id)

    if Decimal.compare(balance, total) == :lt do
      {:error, "insufficient balance: required #{total}, available #{balance}"}
    else
      :ok
    end
  end

  # Allows starting calculation from draft (normal) or calculating (Broadway retry after failure).
  # On retry, calculating was already committed so we skip that transition and go straight
  # to inserting intents — safe because the chunk transaction is atomic and left no partial state.
  defp validate_calculable(status) when status in ["draft", "calculating"], do: :ok
  defp validate_calculable(status), do: {:error, "cannot calculate from status: #{status}"}

  # No-op if already calculating (retry path) — avoids a redundant DB write.
  defp maybe_transition_to_calculating(%{status: "calculating"} = run), do: {:ok, run}
  defp maybe_transition_to_calculating(run), do: transition(run, "calculating")

  defp validate_transition(from, to) do
    if @valid_transitions[from] == to do
      :ok
    else
      {:error, "invalid transition: #{from} → #{to}"}
    end
  end

  defp transition(run, status) do
    run |> PayrollRun.changeset(%{status: status}) |> Repo.update()
  end

  defp mark_failed(run, reason) do
    run |> PayrollRun.changeset(%{status: "failed", error: reason}) |> Repo.update()
    {:error, reason}
  end
end
