# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Global Payroll — an Elixir/Phoenix backend for running payroll across multiple countries. It handles tax calculation, payroll orchestration, and async payment execution through SQS-compatible message queues. This is a study project; `Docs/` contains the full design (a microservices target plus the current monolith implementation).

## Commands

```bash
docker compose up -d        # Start infra: Postgres, ElasticMQ/SQS, Adminer
mix setup                   # deps.get + ecto.create + ecto.migrate + seeds
mix phx.server              # Run the server (http://localhost:4000)
mix precommit               # compile --warning-as-errors, deps.unlock --unused, format, test — RUN BEFORE COMMITTING
```

Testing:
```bash
mix test                       # All tests (auto-creates/migrates the test DB via the test alias)
mix test test/path/file.exs    # Single file
mix test path/file.exs:42      # Single test by line number
mix test --failed              # Re-run previously failed tests
```

`mix test` is aliased to run `ecto.create --quiet` and `ecto.migrate --quiet` first, so it works on a clean checkout once Docker is up.

Local services after `docker compose up`: API `:4000`, Adminer `:8080`, SQS API `:9324`, SQS UI `:9325`. SQS queue URLs the app actually connects to are configured per-env (`config/dev.exs` points `:ex_aws, :sqs` at `localhost:4566`).

## Architecture

The system is built around **two SQS queues** consumed by **Broadway** workers, plus a periodic GenServer for reconciliation/closing. Everything is supervised in `lib/global_payroll/application.ex`, which also creates the queues on boot (for local SQS).

### Domain contexts (`lib/global_payroll/`)
Standard Phoenix context layout — a context module (e.g. `payrolls.ex`) wraps schemas in its subfolder (e.g. `payrolls/payroll_run.ex`).
- `Payrolls` — payroll run lifecycle, intent generation, run closing/invoicing.
- `Payments` — payment execution, retries, result handling, reconciliation. Also defines `MockPaymentProvider` (random ~1% failure) at the bottom of the file.
- `Ledger` / `ledgers/company_transaction.ex` — append-only money movements.
- `Companies`, `Employees`, `Taxes` — supporting contexts.
- `Queue` — the SQS send layer (single + batched sends with retry/backoff).

### Async payment flow
1. `POST /api/payroll-runs/:id/start` enqueues `calculate_payroll` to `payroll-jobs`.
2. `PayrollWorker` consumes it → `Payrolls.calculate_run/1` checks balance, generates one `PayrollIntent` per active employee (chunked `insert_all`, no changeset, tax rules preloaded to avoid N+1), moves run to `pending_approval`.
3. `POST /.../approve` transitions `approved → paying` and (in a background `Task`) batch-enqueues one `execute_payment` per intent.
4. `PayrollWorker` consumes each `execute_payment` → `Payments.execute_payment/1` calls the provider, records a `PaymentAttempt`, and enqueues the outcome to `payment-results`.
5. `PaymentResultsWorker` consumes results → `Payments.process_result/1` runs an `Ecto.Multi`: marks intent `completed`, writes the ledger deduction, inserts a `Payslip` — all in one transaction.
6. `InvoiceWorker` (GenServer, every 1 min) runs `Payments.reconcile_stuck_intents/0` and `Payrolls.close_completed_runs/0`, which closes fully-paid runs and generates the `Invoice`.

### Key invariants — preserve these when editing
- **Append-only ledger**: company balance is NEVER a stored field. It is always derived via `Companies.get_company_balance/1` (`SUM(company_transactions.amount)`). Don't add a balance column.
- **Idempotency**: SQS redelivers. `guard_already_settled/1` rejects already-`completed`/`failed` intents; attempts are keyed by `(intent_id, attempt_number)` with a deterministic `idempotency_key`. Workers ack (return `message`) on `:already_settled`/`:not_found` and only `Message.failed/2` for genuinely retryable errors.
- **Run status machine**: transitions are gated by `@valid_transitions` in `payrolls.ex` (`draft → calculating → pending_approval → approved → paying → completed`). Go through `validate_transition/2`; don't set `status` ad hoc.
- **Locking**: `process_result` success/failure paths lock the intent (`FOR UPDATE`); run-closing uses `FOR UPDATE SKIP LOCKED` so concurrent nodes don't double-process. No Redis — SQS visibility timeout (120s) + DB locks handle concurrency.
- **Reconciliation** in `Payments` distinguishes three stuck states (processing-with-attempt, processing-without-attempt, pending-without-attempt) based on whether a `PaymentAttempt` exists; each resumes differently rather than blindly re-calling the provider.

### Web layer (`lib/global_payroll_web/`)
- JSON REST API under `/api` (controllers + `*_json.ex` views), payment provider webhook under `/webhooks`.
- LiveView dashboard under `/app` (`live/`).
- Routes in `router.ex`.

## Conventions

`AGENTS.md` holds the authoritative Phoenix/Elixir/Ecto usage rules — read it before non-trivial work. Highlights:
- Use `Req` for HTTP (already a dep); avoid HTTPoison/Tesla/httpc.
- LiveView templates must start with `<Layouts.app flash={@flash} ...>`; use `<.input>` and `<.icon>` from `core_components`.
- No index access on lists (`Enum.at/2`), no `changeset[:field]` on structs (`Ecto.Changeset.get_field/2`), bind results of `if`/`case` rather than rebinding inside them.
- Programmatic fields (e.g. `company_id`) are set explicitly, never via `cast`.
