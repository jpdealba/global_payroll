defmodule GlobalPayroll.Payrolls do
  import Ecto.Query
  alias Ecto.Multi
  alias GlobalPayroll.Payrolls.{PayrollRun, PayrollIntent}
  alias GlobalPayroll.Employees.Employee
  alias GlobalPayroll.{Pagination, Repo, Companies}

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
         :ok <- validate_transition(run.status, "calculating") do
      do_calculate(run)
    end
  end

  # --- Private ---

  # The actual calculation pipeline. Separated from calculate_run/1 so that
  # the `else` clause has access to `run` and can mark it as failed when needed.
  #
  # Order matters:
  #   1. Fetch employees — fail fast if there are none
  #   2. Calculate all intents concurrently — pure math, no DB writes yet
  #   3. Sum the total cost — needed before the balance check
  #   4. Check balance — if insufficient, mark failed WITHOUT transitioning to calculating
  #   5. Transition to calculating — only happens if everything above passed
  #   6. Write intents + transition to pending_approval in one transaction
  # TODO: implement chunking of the employees to avoid memory issues
  defp do_calculate(run) do
    with {:ok, employees} <- fetch_active_employees(run.company_id),
         intents_data = build_intents_data(employees),
         total = sum_total(intents_data),
         :ok <- check_balance(run.company_id, total),
         {:ok, run} <- transition(run, "calculating") do
      insert_intents_and_complete(run, intents_data, total)
    else
      {:error, reason} -> mark_failed(run, reason)
    end
  end

  # Fetches all active employees for a company with their tax rule preloaded.
  # Preloading avoids N+1 queries — one query for employees, one for all their tax rules.
  defp fetch_active_employees(company_id) do
    employees =
      Employee
      |> where([e], e.company_id == ^company_id and e.status == "active")
      |> Repo.all()
      |> Repo.preload(:country_tax_rule)

    case employees do
      [] -> {:error, "no active employees found"}
      list -> {:ok, list}
    end
  end

  # Runs calc_intent/1 for every employee in parallel using Task.async_stream.
  # This is why tax rules are preloaded — each task only does math, no DB calls.
  defp build_intents_data(employees) do
    employees
    |> Task.async_stream(&calc_intent/1, ordered: true)
    |> Enum.map(fn {:ok, data} -> data end)
  end

  # Calculates the tax breakdown for one employee using their country's rates.
  # Uses snapshots — reads salary and rates at this moment, not live values.
  # net_salary = gross - income_tax - social_security
  defp calc_intent(employee) do
    tax = employee.country_tax_rule
    gross = employee.gross_salary
    income_tax = Decimal.mult(gross, tax.income_tax_rate)
    social_security = Decimal.mult(gross, tax.social_security_rate)
    net_salary = gross |> Decimal.sub(income_tax) |> Decimal.sub(social_security)

    %{
      employee_id: employee.id,
      gross_salary: gross,
      income_tax: income_tax,
      social_security: social_security,
      net_salary: net_salary,
      platform_fee: @platform_fee
    }
  end

  # Total cost to company = sum of (net_salary + platform_fee) per employee.
  # This is what gets compared against the company balance.
  defp sum_total(intents_data) do
    Enum.reduce(intents_data, Decimal.new(0), fn intent, acc ->
      acc |> Decimal.add(intent.net_salary) |> Decimal.add(intent.platform_fee)
    end)
  end

  # Compares the total run cost against the company's current balance.
  # Balance is computed as SUM(amount) from company_transactions — never stored directly.
  defp check_balance(company_id, total) do
    balance = Companies.get_company_balance(company_id)

    if Decimal.compare(balance, total) == :lt do
      {:error, "insufficient balance: required #{total}, available #{balance}"}
    else
      :ok
    end
  end

  # Writes all payroll intents and transitions the run to pending_approval atomically.
  # Uses Ecto.Multi so both operations succeed or both are rolled back together.
  # insert_all is used instead of individual inserts — one query for all employees.
  # Timestamps and UUIDs are generated manually because insert_all bypasses Ecto callbacks.
  defp insert_intents_and_complete(run, intents_data, total) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # We need to generate the uuids cause that way we avoid makid a select query to get the id of the intent after the insert
    rows =
      Enum.map(intents_data, fn intent ->
        Map.merge(intent, %{
          id: Ecto.UUID.generate(),
          payroll_run_id: run.id,
          company_id: run.company_id,
          status: "pending",
          retry_count: 0,
          inserted_at: now,
          updated_at: now
        })
      end)

    Multi.new()
    |> Multi.insert_all(:intents, PayrollIntent, rows)
    |> Multi.update(
      :run,
      PayrollRun.changeset(run, %{
        status: "pending_approval",
        total_amount: total,
        ran_at: DateTime.utc_now()
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{run: run}} -> {:ok, run}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  # Checks that the requested transition is allowed by the state machine.
  # Looks up the allowed next state for `from` and compares it to `to`.
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

  # Marks the run as failed with a reason. Terminal state — no further transitions allowed.
  # Called when balance is insufficient, no employees found, or a DB error occurs.
  defp mark_failed(run, reason) do
    run |> PayrollRun.changeset(%{status: "failed", error: reason}) |> Repo.update()
    {:error, reason}
  end
end
