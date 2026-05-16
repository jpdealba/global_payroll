# Global Payroll System — Requirements

## Overview

A backend system that allows companies to pay employees located in different countries,
without needing to know each country's tax laws, banking systems, or employment regulations.
The platform acts as the legal employer of record and handles compliance, tax calculation,
and payment execution.

---

## Actors

| Actor | Description |
|-------|-------------|
| **Company** | Hires employees through the platform. Submits payroll inputs and approves payroll runs. |
| **Employee** | Receives salary. Can view their payslips. |
| **Payment Provider** | External service that executes bank transfers (e.g. Wise, local bank rails). |
| **System** | Acts as employer of record. Handles tax calculation, compliance, and payment orchestration. |

---

## Functional Requirements

### Companies
- A company can register with a name, country, and billing email.
- A new company starts in `pending` status and must be activated before running payroll.
- A company's balance is derived from an append-only ledger of transactions. The balance is always computed as the sum of all transactions — it is never stored as a single field.
- Every money movement (deposit, payroll deduction, refund) is recorded as an immutable transaction entry.
- Funds can be added via API endpoint, which inserts a `deposit` transaction.
- An active company can add employees, specifying their country, role, and base salary.
- A company can initiate a payroll run for a given pay period.
- A company can submit one-time adjustments per employee per period (bonuses, extra deductions).
- A company can review and approve a payroll run before payments are executed.
- A company cannot run payroll twice for the same employee in the same pay period.

### Employees
- An employee belongs to exactly one company.
- An employee has a country of residence that determines which tax rules apply.
- An employee has a bank account on file for receiving payments.
- An employee can view their payslips after a payroll run completes.

### Payroll Run
- A payroll run is scoped to a company and a pay period (e.g. 2025-05).
- The system calculates net pay per employee: `gross - income_tax - social_security - deductions`.
- The system generates a payslip for each employee as part of the run.
- The run follows a strict state machine — no state can be skipped.
- Payments are only executed after explicit company approval.
- Every state transition is recorded with a timestamp for audit purposes.

### Payments
- Before executing payments, the system verifies the company has enough balance to cover total net salaries + platform fees. If not, the run fails immediately.
- Each payment is tracked individually — one per employee per run.
- If a payment fails, it is retried up to 3 times before being marked as failed.
- If a payment ultimately fails, the reserved funds for that employee are returned to the company balance.
- A failed payment does not cancel the rest of the run — other employees still get paid.
- The system guarantees idempotency: the same payment is never executed twice, even if the system crashes after sending the payment instruction but before recording the result. This is enforced via a per-attempt idempotency key sent to the provider on every call.
- Payments are executed asynchronously — the system must handle cases where the provider takes time to confirm or never responds.

### Invoicing
- After all payments in a run are settled (completed or failed), the system generates one invoice per company.
- The invoice reflects only the payments that succeeded — failed payments are excluded since their funds were already refunded.
- The invoice includes: total gross salaries, total taxes withheld, and a flat platform fee of $599 per successfully paid employee.
- The invoice is immutable once generated — corrections require a new run or a credit note.
- Invoice status starts as `unpaid` and transitions to `paid` when the company settles it.

### Tax Rules
- Each country has a fixed income tax rate and social security rate.
- Tax rules are stored in the system and versioned — a change in rates does not affect past runs.
- For this version, tax rates are simplified flat rates per country (no brackets).

---

## Payroll Run State Machine

```
draft → calculating → pending_approval → approved → paying → completed
                                                          ↘ failed
```

| State | Description |
|-------|-------------|
| `draft` | Run created, no calculations yet. |
| `calculating` | System is computing net pay for each employee. |
| `pending_approval` | Payslips generated, waiting for company to approve. |
| `approved` | Company approved. Ready to execute payments. |
| `paying` | Payments being sent to payment provider. |
| `completed` | All payments confirmed. Run is closed. |
| `failed` | One or more payments failed after max retries. Run flagged for review. |

---

## Non-Functional Requirements

| Requirement | Description |
|-------------|-------------|
| **Idempotency** | Running the same operation twice produces the same result without side effects. Critical for payments. |
| **Auditability** | Every state transition and payment attempt is logged with a timestamp. Records are immutable. |
| **Fault tolerance** | A failure in one payment does not bring down the entire run. The system recovers from crashes without duplicating work. |
| **Consistency** | Payslip calculations must match what was actually paid. No rounding errors or silent mismatches. |
| **Simplicity** | No multi-currency conversion in v1. Each employee is paid in their country's default currency. |

---

## Out of Scope (v1)

- Multi-currency conversion (employees are paid in their local currency, no FX logic)
- Tax bracket calculations (flat rates only)
- Expense reimbursements
- Contractor payments (employees only)
- UI / frontend
- Authentication and authorization
- Real payment provider integration (payment provider will be simulated)

---

## Open Questions

- Should a payroll run be rejected (not just failed) if any employee is missing bank details before calculating?
- Who can retry a failed payment — the system automatically, or does the company trigger it?
- What happens if an employee's country changes mid-period?
