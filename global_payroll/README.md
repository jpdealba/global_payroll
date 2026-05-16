# Global Payroll

Backend system for paying employees across multiple countries. Handles tax calculation, payroll run orchestration, and async payment execution via a real queue (SQS-compatible).

## Local setup

```bash
# Start infrastructure (Postgres, ElasticMQ, Adminer)
docker compose up -d

# Install deps and create/migrate DB
mix setup

# Start the server
mix phx.server
```

Services available after `docker compose up`:

| Service | URL |
|---------|-----|
| API | http://localhost:4000 |
| DB UI (Adminer) | http://localhost:8080 |
| SQS API | http://localhost:9324 |
| SQS UI | http://localhost:9325 |

Adminer login: System=PostgreSQL, Server=postgres, User=postgres, Password=postgres, DB=global_payroll_dev

## Before committing

```bash
mix precommit
```

Runs: `compile --warning-as-errors`, `deps.unlock --unused`, `format`, `test`.

## Project docs

| Doc | Content |
|-----|---------|
| `Docs/1- REQUIREMENTS.md` | Functional and non-functional requirements |
| `Docs/1.5- SEQUENCE.md` | Sequence diagrams for main flows |
| `Docs/3- API DESIGN.md` | REST resource design |
| `Docs/4- ARCHITECTURE.md` | Full-scale design + implementation architecture + next steps |

## Key design decisions

- **Async payments** — Broadway consumes `payroll-jobs`, sends instruction to provider, marks intent as `processing`. Provider calls webhook → webhook enqueues to `payment-results` → second Broadway consumer records the outcome.
- **Ledger is append-only** — company balance is never stored as a field; it is derived from `company_transactions`.
- **Idempotency via `guard_already_settled`** — prevents double processing on SQS message redelivery.
- **No Redis yet** — SQS visibility timeout handles concurrency. Redis distributed lock is deferred until Broadway consumer is implemented and profiled.
