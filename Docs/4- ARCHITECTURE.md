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
                          │          │     ▲                 (no DB)                  │
                          │          │     │ webhook                                  │
                          │          │  Payment Provider (external)                   │
                          │          │                                                 │
                          │          └──► Message Broker (SQS: payment-results)      │
                          │                   │                                       │
                          │                   ├──► Ledger Service                    │
                          │                   └──► Notifications Service             │
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
| **Payment Service** | Payment execution, retries, webhook handling, reconciliation | PostgreSQL |
| **Ledger Service** | Append-only company_transactions, balance computation | PostgreSQL |
| **Notifications Service** | Notifies companies of run status changes | None |

### Message Broker Flow

```
Payroll Service ──[run approved]──► SQS (payroll-jobs) ──► Payment Service
Payment Provider ──[webhook]──► Payment Service ──► SQS (payment-results)
Payment Service (payment-results) ──► Ledger Service
                                  └──► Notifications Service
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
┌──────────────────────────────────────────────────────────────────┐
│                   Single Elixir/Phoenix Node                      │
│                                                                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐                │
│  │Companies │  │Employees │  │ Payroll           │                │
│  │  Context │  │  Context │  │ Context           │                │
│  └──────────┘  └──────────┘  └──────────────────┘                │
│                                      │                             │
│  ┌──────────┐  ┌──────────┐         │ POST /start                 │
│  │  Taxes   │  │  Ledger  │◄──┐     │ → enqueue calculate         │
│  │  Context │  │  Context │   │     │ POST /approve               │
│  └──────────┘  └──────────┘   │     │ → enqueue 1 msg/intent      │
│                                │     ▼                             │
│                                │  [payroll-jobs]                   │
│                                │     │                             │
│                         ┌──────┴─────▼──────────────────┐         │
│                         │  Broadway (PaymentWorker)       │         │
│                         │  · calculate_payroll(run_id)   │         │
│                         │  · execute_payment(intent_id)  │         │
│                         │    → calls Provider API         │         │
│                         │    → intent = "processing"      │         │
│                         └───────────────────────────────┘         │
│                                                                    │
│  Payment Provider ──webhook──► POST /webhooks/payment             │
│                                      │                             │
│                                      ▼                             │
│                              Webhook Handler                       │
│                              · enqueue to payment-results          │
│                              · return 200 immediately              │
│                                      │                             │
│                               [payment-results]                    │
│                                      │                             │
│                         ┌────────────▼──────────────────┐         │
│                         │  Broadway (ResultsWorker)       │         │
│                         │  · completed → Ledger debit    │         │
│                         │  · failed    → retry via SQS   │         │
│                         │              or Ledger refund  │         │
│                         └───────────────────────────────┘         │
│                                                                    │
│  Reconciliation Job (periodic)                                     │
│  · find intents stuck in "processing" > threshold                  │
│  · poll Provider API → resolve or retry                            │
│                                                                    │
└──────────────────────────┬─────────────────────────────────────── ┘
                           │
             ┌─────────────┴─────────────┐
             │      PostgreSQL (single)   │
             │   all tables, one DB       │
             └───────────────────────────┘
```

### Queue Message Design

#### `payroll-jobs` — work to be done

| Trigger | Message | Quantity |
|---------|---------|----------|
| `POST /payroll-runs/:id/start` | `{"job":"calculate_payroll","run_id":"..."}` | 1 per run |
| `approve_run` via `Task.start` (async) | `{"job":"execute_payment","intent_id":"..."}` | 1 per intent |
| Payment failed, `retry_count < 3` | `{"job":"execute_payment","intent_id":"..."}` | 1 per retry |

On approve, `approve_run` transitions the run to `paying` and immediately returns to the caller.
A `Task.start` fires in the background to batch-enqueue one `execute_payment` message per intent
using the SQS batch API (10 messages per call). Broadway processes each intent independently —
a failed payment is retried without affecting others.

#### `payment-results` — outcomes from the provider

| Trigger | Message | Quantity |
|---------|---------|----------|
| Mock provider success (dev) | `{"intent_id":"...","status":"succeeded"}` | 1 per intent |
| Mock provider failure (dev) | `{"intent_id":"...","status":"failed","error":"..."}` | 1 per attempt |
| Real provider webhook (prod) | `{"payment_id":"...","status":"succeeded\|failed"}` | 1 per attempt |
| Reconciliation (stuck intents) | `{"intent_id":"...","status":"succeeded\|failed"}` | 1 per resolved |

In production, the provider calls `POST /webhooks/payment` when a payment resolves. The webhook
handler only enqueues to `payment-results` and returns `200` immediately — real providers
(Wise, Stripe) retry the webhook if they don't get a response within ~5 seconds, so no DB
work is done inside the request. In dev, the mock short-circuits this: it simulates the provider
call and enqueues the result itself, so the webhook is never triggered.

---

### State Machines

#### PayrollRun

```
draft ──► calculating ──► pending_approval ──► approved ──► paying ──► completed
                                                                  └──► failed
```

| Transition | Trigger |
|---|---|
| `draft → calculating` | Broadway picks up `calculate_payroll`, balance check passes |
| `calculating → pending_approval` | All intents inserted successfully |
| `pending_approval → approved` | `approve_run` called |
| `approved → paying` | Immediately after approved, in the same `approve_run` call |
| `paying → completed` | `InvoiceWorker` detects no intents left in `pending` or `processing` |
| `any → failed` | Balance check fails, or run explicitly cancelled |

#### PayrollIntent

```
pending ──► processing ──► completed
                      └──► pending   (retry, retry_count < 3)
                      └──► failed    (retry_count = 3)
```

| Transition | Trigger |
|---|---|
| `pending → processing` | `execute_payment` starts — intent locked before provider call |
| `processing → completed` | `on_success` — ledger deduction + payslip created atomically |
| `processing → pending` | `on_failure` — re-enqueued to `payroll-jobs` for retry |
| `processing → failed` | `on_max_retries` — ledger refund issued |

---

### Complete Message Flow

#### `calculate_payroll` message

```
POST /start
  └─ enqueue {"job":"calculate_payroll","run_id":"X"} → payroll-jobs

PayrollWorker (Broadway)
  └─ Payrolls.calculate_run("X")
       ├─ validate: status is "draft" or "calculating"
       ├─ compute total net salaries + platform fees
       ├─ check company balance ≥ total
       ├─ run → "calculating"
       ├─ delete any existing intents (safe to retry)
       ├─ insert N intents in chunks of 500 (bulk insert, parallel per chunk)
       └─ run → "pending_approval"
                                        ← Broadway acks message (deleted from SQS)
```

#### `execute_payment` message

```
POST /approve
  └─ approve_run()
       ├─ run → "approved" → "paying"
       └─ Task.start (async) → batch-enqueue N × {"job":"execute_payment","intent_id":"Y"}

PayrollWorker (Broadway) — N messages processed in parallel
  └─ Payments.execute_payment("Y")
       ├─ guard: already settled? → ack and stop
       ├─ check existing PaymentAttempt (idempotency on redelivery)
       ├─ intent → "processing", save idempotency_key
       ├─ MockProvider.call() → {:ok, provider_id} | {:error, reason}
       ├─ record PaymentAttempt (succeeded | failed)
       ├─ save provider_payment_id on intent
       └─ enqueue {"intent_id":"Y","status":"succeeded|failed"} → payment-results
                                        ← Broadway acks message

PaymentResultsWorker (Broadway)
  └─ Payments.process_result(event)
       ├─ on "succeeded":
       │    └─ DB transaction:
       │         ├─ lock intent (FOR UPDATE)
       │         ├─ intent → "completed"
       │         ├─ Ledger.payroll_deduction()
       │         └─ insert Payslip
       └─ on "failed":
            ├─ retry_count < 3 → intent → "pending", re-enqueue execute_payment
            └─ retry_count = 3 → intent → "failed", Ledger.refund()

InvoiceWorker (every 1 minute)
  └─ close_completed_runs()
       └─ finds "paying" runs with no intents in "pending" or "processing"
            └─ FOR UPDATE SKIP LOCKED (safe for multiple nodes)
                 ├─ aggregate completed intent totals
                 ├─ insert Invoice
                 └─ run → "completed"
```

#### Reconciliation (safety net, every 1 minute)

```
InvoiceWorker → Payments.reconcile_stuck_intents()

Case 1 — intent "processing", PaymentAttempt exists but result never reached payment-results:
  └─ re-dispatch result from the attempt record (no provider call)

Case 2 — intent "processing", no PaymentAttempt (crash between status update and attempt record):
  └─ reset intent → "pending", re-enqueue execute_payment

Case 3 — intent "pending" for 5+ minutes, no PaymentAttempt (SQS message lost):
  └─ re-enqueue execute_payment
```

---

### Why the webhook only enqueues

Real payment providers (Wise, Stripe Payouts) expect a `200` response within ~5 seconds or they
retry the webhook. Doing DB writes inside the request risks timeouts under load. The webhook
handler only enqueues the result to `payment-results` and returns immediately — `PaymentResultsWorker`
does the actual work.

### Stack

| Component | Technology |
|-----------|-----------|
| Web framework | Phoenix |
| Queue consumer | Broadway |
| Queue (local dev) | floci (SQS-compatible) |
| Queue (production) | AWS SQS |
| Database | PostgreSQL (single instance) |
| Reconciliation + invoice close | `InvoiceWorker` GenServer (every 1 min) |

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

