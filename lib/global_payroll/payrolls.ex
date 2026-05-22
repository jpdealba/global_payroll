defmodule GlobalPayroll.Payrolls do
  import Ecto.Query

  alias GlobalPayroll.Payrolls.{PayrollRun, PayrollIntent, Invoice, Payslip}
  alias GlobalPayroll.Employees.Employee
  alias GlobalPayroll.Taxes.CountryTaxRule
  alias GlobalPayroll.{Pagination, Repo, Companies, Queue}

  @chunk_size 500
  @platform_fee Decimal.new("29")

  # Valid status progressions for a PayrollRun — any other transition is rejected
  @valid_transitions %{
    "draft" => "calculating",
    "calculating" => "pending_approval",
    "pending_approval" => "approved",
    "approved" => "paying",
    "paying" => "completed"
  }

  # Creates a new payroll run in "draft" status for a given company and pay period
  def create_run(company_id, pay_period) do
    %PayrollRun{}
    |> PayrollRun.changeset(%{company_id: company_id, pay_period: pay_period})
    |> Repo.insert()
  end

  # Returns a paginated list of runs for a company, ordered by cursor
  def list_runs(company_id, cursor \\ nil, per_page \\ 20) do
    PayrollRun
    |> where([r], r.company_id == ^company_id)
    |> Pagination.paginate(cursor, per_page)
    |> Repo.all()
    |> then(&{&1, Pagination.next_cursor(&1, per_page)})
  end

  # Fetches a single run by id
  def get_run(id) do
    case Repo.get(PayrollRun, id) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  # Returns all intents for a run — used internally, not paginated
  def list_intents(run_id) do
    PayrollIntent
    |> where([i], i.payroll_run_id == ^run_id)
    |> Repo.all()
  end

  # Returns intent counts grouped by status — used to show progress in the run detail view (LiveView)
  def count_intents_by_status(run_id) do
    PayrollIntent
    |> where([i], i.payroll_run_id == ^run_id)
    |> group_by([i], i.status)
    |> select([i], {i.status, count(i.id)})
    |> Repo.all()
    |> Map.new() # converts [{status, count}] list into %{status => count} for easy lookup
  end

  # Returns only the ids of all intents for a run — used by enqueue_payments to batch-enqueue without loading full structs
  def list_intent_ids(run_id) do
    PayrollIntent
    |> where([i], i.payroll_run_id == ^run_id)
    |> select([i], i.id)
    |> Repo.all()
  end

  # Returns a paginated list of intents, optionally filtered by status, with employee preloaded (LiveView)
  def list_intents_page(run_id, cursor \\ nil, per_page \\ 50, status \\ nil) do
    intents =
      PayrollIntent
      |> where([i], i.payroll_run_id == ^run_id)
      |> then(fn q -> if status, do: where(q, [i], i.status == ^status), else: q end)
      |> Pagination.paginate(cursor, per_page)
      |> Repo.all()

    {Repo.preload(intents, :employee), Pagination.next_cursor(intents, per_page)}
  end

  # Fetches a single intent with all associations needed for display (employee, payslip, attempts) (LiveView)
  def get_intent_with_preloads(id) do
    case Repo.get(PayrollIntent, id) do
      nil -> {:error, :not_found}
      intent -> {:ok, Repo.preload(intent, [:employee, :payslip, :payment_attempts])}
    end
  end

  # Returns all payslips for a run — used for bulk export, not paginated
  def list_payslips_by_run(run_id) do
    Payslip
    |> join(:inner, [s], i in PayrollIntent, on: s.payroll_intent_id == i.id)
    |> where([s, i], i.payroll_run_id == ^run_id)
    |> Repo.all()
  end

  # Returns a paginated list of payslips for a run with employee preloaded (LiveView)
  def list_payslips_by_run_page(run_id, cursor \\ nil, per_page \\ 50) do
    payslips =
      Payslip
      |> join(:inner, [s], i in PayrollIntent, on: s.payroll_intent_id == i.id)
      |> join(:inner, [s, _i], e in Employee, on: s.employee_id == e.id)
      |> where([_s, i], i.payroll_run_id == ^run_id)
      |> preload([s, _i, e], employee: e) # avoids a second query — employee is already loaded from the join above
      |> Pagination.paginate(cursor, per_page)
      |> Repo.all()

    {payslips, Pagination.next_cursor(payslips, per_page)}
  end

  # Returns all payslips for a specific employee across all runs
  def list_payslips_by_employee(employee_id) do
    Payslip
    |> where([s], s.employee_id == ^employee_id)
    |> Repo.all()
  end

  # Returns all invoices for a company
  def list_invoices_by_company(company_id) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> Repo.all()
  end

  # Approves the run and immediately starts paying — skips the manual start_paying step.
  # Enqueues all payments in a background Task so the HTTP response is not blocked.
  def approve_run(run_id) do
    with {:ok, run} <- get_run(run_id),
         :ok <- validate_transition(run.status, "approved"),
         {:ok, run} <- transition(run, "approved"),
         :ok <- validate_transition(run.status, "paying"),
         {:ok, run} <- transition(run, "paying") do
      Task.start(fn -> enqueue_payments(run.id) end)
      {:ok, run}
    end
  end

  # Transitions a run to "paying" — only valid from "approved"
  def start_paying(run_id) do
    with {:ok, run} <- get_run(run_id),
         :ok <- validate_transition(run.status, "paying") do
      transition(run, "paying")
    end
  end

  # Cancels a run — only allowed from "draft" or "pending_approval"
  def cancel_run(run_id) do
    with {:ok, run} <- get_run(run_id),
         :ok <- validate_cancellable(run.status) do
      run
      |> PayrollRun.changeset(%{status: "failed", error: "cancelled"})
      |> Repo.update()
    end
  end

  # Entry point for payroll calculation — called by PayrollWorker when it consumes a calculate_payroll message
  def calculate_run(run_id) do
    with {:ok, run} <- get_run(run_id),
         :ok <- validate_calculable(run.status) do
      do_calculate(run)
    end
  end

  # Orchestrates the full calculation: checks balance, transitions run, inserts intents.
  # On any failure, marks the run as failed with the error reason.
  defp do_calculate(run) do
    with {:ok, total} <- compute_expected_total(run.company_id),
         :ok <- check_balance(run.company_id, total),
         {:ok, run} <- maybe_transition_to_calculating(run) do
      insert_intents_in_chunks(run, total)
    else
      {:error, reason} -> mark_failed(run, reason)
    end
  end

  # Calculates the total amount needed to pay all active employees including platform fees.
  # Uses a SQL fragment to compute net salary directly in the DB to avoid loading all employee records.
  defp compute_expected_total(company_id) do
    result =
      from(e in Employee,
        join: t in CountryTaxRule,
        on: e.country_tax_id == t.id,
        where: e.company_id == ^company_id and e.status == "active",
        select: %{
          count: count(e.id),
          net_sum:
            sum(
              fragment(
                "? * (1 - ? - ?)",
                e.gross_salary,
                t.income_tax_rate,
                t.social_security_rate
              )
            )
        }
      )
      |> Repo.one()

    case result do
      %{count: 0} ->
        {:error, "no active employees found"}

      %{count: n, net_sum: net} ->
        {:ok, Decimal.add(net, Decimal.mult(@platform_fee, Decimal.new(n)))}
    end
  end

  # Deletes any previous intents for this run (idempotent recalculation), then inserts new ones in chunks.
  # Tax rules are preloaded into a map to avoid N+1 queries per employee.
  # Employees are processed in async_stream within each chunk for parallelism.
  defp insert_intents_in_chunks(run, total) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.delete_all(from(i in PayrollIntent, where: i.payroll_run_id == ^run.id))

    tax_rules =
      from(t in CountryTaxRule,
        where:
          t.id in subquery(
            from(e in Employee,
              where: e.company_id == ^run.company_id and e.status == "active",
              select: e.country_tax_id
            )
          )
      )
      |> Repo.all()
      |> Map.new(fn t -> {t.id, t} end)

    employee_ids =
      Employee
      |> where([e], e.company_id == ^run.company_id and e.status == "active")
      |> select([e], e.id)
      |> Repo.all()

    employee_ids
    |> Enum.chunk_every(@chunk_size)
    |> Enum.each(fn chunk_ids ->
      rows =
        Employee
        |> where([e], e.id in ^chunk_ids)
        |> Repo.all()
        # max_concurrency defaults to System.schedulers_online() (number of cores)
        |> Task.async_stream(
          fn e ->
            build_intent_row(
              %{e | country_tax_rule: Map.fetch!(tax_rules, e.country_tax_id)},
              run,
              now
            )
          end,
          ordered: false
        )
        |> Enum.map(fn {:ok, row} -> row end) # unwraps {:ok, row} tuples from async_stream into a flat list

      Repo.insert_all(PayrollIntent, rows)
    end)

    run
    |> PayrollRun.changeset(%{
      status: "pending_approval",
      total_amount: total,
      ran_at: now
    })
    |> Repo.update()
    |> case do
      {:ok, _} -> {:ok, run}
      {:error, reason} -> {:error, reason}
    end
  end

  # Builds the raw map for insert_all — does not go through a changeset for performance
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

  # Fetches all intent ids for the run and batch-enqueues execute_payment messages to SQS
  defp enqueue_payments(run_id) do
    run_id
    |> list_intent_ids()
    |> Queue.enqueue_execute_payments()
  end

  # Blocks calculation if company balance is insufficient to cover the total payroll amount
  defp check_balance(company_id, total) do
    balance = Companies.get_company_balance(company_id)

    if Decimal.compare(balance, total) == :lt do
      {:error, "insufficient balance: required #{total}, available #{balance}"}
    else
      :ok
    end
  end

  # Allows recalculation from both "draft" and "calculating" — the latter handles reconciliation retries
  defp validate_calculable(status) when status in ["draft", "calculating"], do: :ok
  defp validate_calculable(status), do: {:error, "cannot calculate from status: #{status}"}

  defp validate_cancellable(status) when status in ["draft", "pending_approval"], do: :ok
  defp validate_cancellable(status), do: {:error, "cannot cancel run in status: #{status}"}

  # Skips transition if already "calculating" — handles idempotent redelivery from SQS
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
    run
    |> PayrollRun.changeset(%{status: status})
    |> Repo.update()
  end

  defp mark_failed(run, reason) do
    run
    |> PayrollRun.changeset(%{status: "failed", error: reason})
    |> Repo.update()

    {:error, reason}
  end

  # Called by invoice_worker on a schedule — finds all "paying" runs with no pending/processing intents and closes them
  def close_completed_runs do
    from(r in PayrollRun,
      as: :run,
      where: r.status == "paying",
      where:
        not exists(
          from(i in PayrollIntent,
            where: i.payroll_run_id == parent_as(:run).id,
            where: i.status in ["pending", "processing"]
          )
        ),
      select: r.id
    )
    |> Repo.all()
    |> Enum.each(&close_run/1)
  end

  # Locks the run with SKIP LOCKED to avoid double-closing when multiple nodes run the job concurrently
  defp close_run(run_id) do
    Repo.transaction(fn ->
      run =
        from(r in PayrollRun,
          where: r.id == ^run_id and r.status == "paying",
          lock: "FOR UPDATE SKIP LOCKED"
        )
        |> Repo.one()

      if run, do: generate_and_close(run)
    end)
  end

  # Aggregates completed intents, creates the invoice, and marks the run as "completed"
  defp generate_and_close(run) do
    agg =
      from(i in PayrollIntent,
        where: i.payroll_run_id == ^run.id and i.status == "completed",
        select: %{
          total_gross: sum(i.gross_salary),
          total_net: sum(i.net_salary),
          total_taxes: sum(i.income_tax) + sum(i.social_security),
          total_fees: sum(i.platform_fee)
        }
      )
      |> Repo.one()

    total_gross = agg.total_gross || Decimal.new(0)
    total_net = agg.total_net || Decimal.new(0)
    total_taxes = agg.total_taxes || Decimal.new(0)
    total_fees = agg.total_fees || Decimal.new(0)

    Repo.insert!(
      Invoice.changeset(%Invoice{}, %{
        company_id: run.company_id,
        payroll_run_id: run.id,
        total_gross_salaries: total_gross,
        total_taxes_withheld: total_taxes,
        total_platform_fees: total_fees,
        total_amount: Decimal.add(total_net, total_fees),
        issued_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )

    Repo.update!(PayrollRun.changeset(run, %{status: "completed"}))
  end
end
