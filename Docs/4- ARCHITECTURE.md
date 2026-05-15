# Global Payroll System — Architecture

---

## Design Architecture (Full Scale)

This is the target architecture for a production-grade globally scalable system.
The diagram below represents the logical design — not what we implement in code.

```
                          ┌─────────────────────────────────────────────────────────┐
                          │                     AWS Infrastructure                   │
                          │                                                           │
Frontend ──────────────► API Gateway                                                 │
                          │                                                           │
                          ├──► LB ──► Companies Service ──────────────► Companies DB │
                          │                                                           │
                          ├──► LB ──► Employees Service ──────────────► Employees DB │
                          │                                                           │
                          ├──► LB ──► Taxes Service ────────────────── ► Taxes DB    │
                          │                                                           │
                          ├──► LB ──► Ledger Service ───────────────── ► Ledger DB   │
                          │                   ▲                                       │
                          │                   │ (refunds/deductions)                  │
                          ├──► LB ──► Payroll Service ──────────────── ► Payroll DB  │
                          │                   │                         │             │
                          │                   │                         └──► S3       │
                          │              Message Broker (SQS)                        │
                          │                   │                                       │
                          │          ┌────────┴─────────┐                            │
                          │          ▼                   ▼                            │
                          ├──► LB ──► Payment Service   Notifications Service        │
                          │                   │               (no DB)                 │
                          │              Message Broker (SQS)                        │
                          │                   │                                       │
                          │                   ├──► Ledger Service                    │
                          │                   └──► Notifications Service             │
                          │                   │                                       │
                          │                   └──► Payment Provider (external)       │
                          │                                                           │
                          └─────────────────────────────────────────────────────────┘
```

### Services

| Service | Responsibility | Database |
|---------|---------------|----------|
| **API Gateway** | Routes requests, auth, rate limiting | None |
| **Companies Service** | Company registration, status management | PostgreSQL |
| **Employees Service** | Employee profiles, payment methods | PostgreSQL |
| **Taxes Service** | Country tax rules lookup | PostgreSQL |
| **Payroll Service** | Payroll run orchestration, payslips, invoices | PostgreSQL + S3 |
| **Payment Service** | Payment execution, retries, Payment Provider integration | PostgreSQL |
| **Ledger Service** | Append-only company_transactions, balance computation | PostgreSQL |
| **Notifications Service** | Notifies companies of run status changes | None |

### Message Broker Flow

```
Payroll Service ──[run approved]──► SQS ──► Payment Service
                ──[run completed/failed]──► SQS ──► Notifications Service

Payment Service ──[payment done/failed]──► SQS ──► Ledger Service
                ──[payment done/failed]──► SQS ──► Notifications Service
```

### Storage

- **PostgreSQL** — all structured data (per service in full scale, shared in implementation)
- **S3** — invoice and payslip PDF files. Accessed via pre-signed URLs (no CDN — private documents)

---

## Implementation Architecture (What We Actually Build)

For this exercise we collapse the microservices into a single Elixir/Phoenix application
with clear internal module boundaries. The design principles still apply — modules don't
cross-call each other arbitrarily, and the event flow is preserved via a real queue.

```
┌─────────────────────────────────────────────────────────────┐
│                Single Elixir/Phoenix Node                    │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐           │
│  │Companies │  │Employees │  │ Payroll           │           │
│  │  Context │  │  Context │  │ Context           │           │
│  └──────────┘  └──────────┘  └──────────────────┘           │
│                                      │                        │
│  ┌──────────┐  ┌──────────┐         │ POST /start            │
│  │  Taxes   │  │  Ledger  │◄──┐     │ → enqueue calculate    │
│  │  Context │  │  Context │   │     │ POST /approve          │
│  └──────────┘  └──────────┘   │     │ → enqueue 1 msg/intent │
│                                │     ▼                        │
│                                │  [payroll-jobs]              │
│                                │     │                        │
│                         ┌──────┴─────▼──────────────────┐    │
│                         │  Broadway Consumer             │    │
│                         │  · calculate_payroll(run_id)  │    │
│                         │  · execute_payment(intent_id) │    │
│                         │    → calls PaymentProvider    │    │
│                         │    → publishes to results     │    │
│                         └──────────────┬────────────────┘    │
│                                        │                      │
│                                 [payment-results]             │
│                                        │                      │
│                         ┌──────────────▼────────────────┐    │
│                         │  Broadway Consumer             │    │
│                         │  · completed → Ledger debit   │    │
│                         │  · failed    → Ledger refund  │    │
│                         │  · any       → Notifications  │    │
│                         └───────────────────────────────┘    │
│                                                               │
└───────────────────────────────┬───────────────────────────── ┘
                                │
                  ┌─────────────┴─────────────┐
                  │      PostgreSQL (single)   │
                  │   all tables, one DB       │
                  └───────────────────────────┘
```

### Queue Message Design

**`payroll-jobs`** — published by the API, consumed by Broadway Payment Worker

| Trigger | Message | Quantity |
|---------|---------|----------|
| `POST /payroll-runs/:id/start` | `{ job: "calculate_payroll", run_id }` | 1 per run |
| `POST /payroll-runs/:id/approve` | `{ job: "execute_payment", intent_id }` | 1 per employee |

On approve, the API fetches all `payroll_intents` for the run and enqueues one message per intent.
Broadway processes each independently — a failed payment is retried without affecting others.

**`payment-results`** — published by Broadway after each payment attempt, consumed by Ledger + Notifications

| Trigger | Message | Quantity |
|---------|---------|----------|
| Payment succeeded | `{ intent_id, status: "completed" }` | 1 per employee |
| Payment failed (max retries) | `{ intent_id, status: "failed" }` | 1 per employee |

### Stack

| Component | Technology |
|-----------|-----------|
| Web framework | Phoenix |
| Background jobs / queue consumer | Broadway |
| Queue (local dev) | ElasticMQ (SQS-compatible) via Floci |
| Database | PostgreSQL (single instance) |
| Multi-node (optional) | Elixir clustering via libcluster |

### Why this still works at scale later

- Module boundaries in code map 1:1 to the microservices in the design diagram
- When you need to split services, each Phoenix context becomes its own app
- Broadway consumers already behave like independent workers — scaling them is additive
- The queue (SQS via ElasticMQ locally, real SQS in production) is the same interface
- `payroll-jobs` maps to the Payroll→Payment SQS in the full-scale design
- `payment-results` maps to the Payment→Ledger/Notifications SQS in the full-scale design

---

## On Event Sourcing

**Should we switch to full event sourcing?**

No — and here's why:

Our system already uses event sourcing **where it matters most**: the financial ledger.
`company_transactions` is an append-only event log. The balance is derived by replaying
those events. That IS event sourcing for money movement.

Full event sourcing for the entire system would mean:
- No `payroll_runs.status` column — instead replay `PayrollCreated`, `PayrollStarted`,
  `PayrollCalculated`, `PayrollApproved`, `PaymentExecuted`... to derive current state
- Requires CQRS + read projections (a separate read model rebuilt from events)
- Queries become complex — "what is the current status of this run?" requires replaying history

**The trade-off:**
- Full event sourcing gives perfect audit history and time-travel debugging
- But adds significant complexity — especially for a system where current state
  (status, balance) is what clients query most

**Our approach is the right balance:**
- Ledger = event sourced (financial audit trail for free)
- Payroll run = state machine with timestamps (traceable, not full event sourcing)
- Payment intents = individual records with retry_count and error (auditable)

This is actually how most fintech systems work in practice, including likely Remote.
Full event sourcing is more common in systems where replaying history is a core feature
(e.g. accounting systems, blockchain).
