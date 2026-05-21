# Global Payroll

A backend system for running payroll across multiple countries. Built with **Elixir / Phoenix**, it handles tax calculation, payroll orchestration, and async payment execution via a message queue (SQS-compatible).

This is a study project exploring distributed system design — the architecture document covers both a full-scale microservices target and the current monolith implementation.

## Tech stack

- **Elixir / Phoenix** — HTTP API + LiveView dashboard
- **PostgreSQL** — all structured data (companies, employees, taxes, payroll, ledger)
- **Broadway + SQS (ElasticMQ locally)** — async payroll job and payment result processing
- **Docker Compose** — local infrastructure (Postgres, ElasticMQ, Adminer)

## Architecture overview

The system models two queues:

1. `payroll-jobs` — Broadway consumer sends payment instructions to the provider and marks the intent as `processing`
2. `payment-results` — webhook from the provider enqueues outcomes; a second Broadway consumer records them in the ledger

The ledger is append-only: company balance is derived from `company_transactions`, never stored as a field.

See [`Docs/4- ARCHITECTURE.md`](Docs/4-%20ARCHITECTURE.md) for the full design (microservices target + current monolith).

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
| [`Docs/1- REQUIREMENTS.md`](Docs/1-%20REQUIREMENTS.md) | Functional and non-functional requirements |
| [`Docs/1.5- SEQUENCE.md`](Docs/1.5-%20SEQUENCE.md) | Sequence diagrams for main flows |
| [`Docs/2- DATA_MODEL.md`](Docs/2-%20DATA_MODEL.md) | Database schema and relationships |
| [`Docs/3- API DESIGN.md`](Docs/3-%20API%20DESIGN.md) | REST resource design |
| [`Docs/4- ARCHITECTURE.md`](Docs/4-%20ARCHITECTURE.md) | Full-scale design + implementation architecture + next steps |

## Key design decisions

- **Async payments** — Broadway consumes `payroll-jobs`, sends instruction to provider, marks intent as `processing`. Provider calls webhook → webhook enqueues to `payment-results` → second Broadway consumer records the outcome.
- **Append-only ledger** — company balance is never stored as a field; it is derived from `company_transactions`.
- **Idempotency via `guard_already_settled`** — prevents double processing on SQS message redelivery.
- **No Redis** — SQS visibility timeout handles concurrency. A distributed lock is deferred until Broadway consumers are profiled under load.
