# Global Payroll System — Data Model

---

## Entities

### `companies`
| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| name | string | |
| country | string | ISO code e.g. "MX" |
| billing_email | string | |
| balance | virtual | Computed as `SUM(amount)` from `company_transactions` — not stored |
| status | enum | `pending`, `active`, `inactive` |
| inserted_at | datetime | |
| updated_at | datetime | |

**Constraints:**
- Unique on `billing_email`
- Payroll can only run if `status = active`

---

### `company_transactions`
Append-only ledger. Never updated or deleted — only inserted.

| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| company_id | uuid | FK → companies |
| amount | decimal | Positive = credit, negative = debit |
| type | enum | `deposit`, `payroll_deduction`, `refund` |
| reference_id | uuid | nullable — points to payroll_run or payroll_intent |
| description | string | Human-readable note |
| inserted_at | datetime | |

**The company balance is always:** `SELECT SUM(amount) FROM company_transactions WHERE company_id = x`

---

### `country_tax_rules`
| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| country_code | string | ISO code e.g. "MX", "US", "ES" |
| country_name | string | |
| income_tax_rate | decimal | e.g. 0.25 for 25% |
| social_security_rate | decimal | e.g. 0.065 for 6.5% |
| currency | string | e.g. "MXN", "USD", "EUR" |
| inserted_at | datetime | |

**Constraints:**
- Unique on `country_code`
- Rates are flat for v1 — no brackets

---

### `employees`
| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| company_id | uuid | FK → companies |
| country_tax_id | uuid | FK → country_tax_rules |
| name | string | |
| email | string | |
| gross_salary | decimal | Monthly gross in their local currency |
| status | enum | `pending`, `active`, `terminated` |
| inserted_at | datetime | |
| updated_at | datetime | |

**Constraints:**
- Unique on `email`
- Only `active` employees are included in payroll runs

---

### `payment_methods`
| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| employee_id | uuid | FK → employees |
| bank_name | string | |
| account_holder | string | |
| account_number | string | |
| bank_code | string | Routing number, CLABE, IBAN, etc. |
| is_default | boolean | Employee may have multiple accounts |
| inserted_at | datetime | |
| updated_at | datetime | |

**Constraints:**
- Only one `is_default = true` per employee

---

### `payroll_runs`
| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| company_id | uuid | FK → companies |
| pay_period | string | e.g. "2025-05" |
| status | enum | `draft`, `calculating`, `pending_approval`, `approved`, `paying`, `completed`, `failed` |
| error | string | nullable — reason the run failed (e.g. "insufficient balance") |
| total_amount | decimal | Total cost to company (salaries + fees). Set after calculating. |
| ran_at | datetime | When the run was actually executed |
| inserted_at | datetime | |
| updated_at | datetime | |

**Constraints:**
- Unique on `(company_id, pay_period)` — prevents duplicate runs

---

### `payroll_intents`
One record per employee per run. Represents the individual payment to one employee.

| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| payroll_run_id | uuid | FK → payroll_runs |
| employee_id | uuid | FK → employees |
| gross_salary | decimal | Snapshot at time of run — not a live reference |
| income_tax | decimal | Calculated amount withheld |
| social_security | decimal | Calculated amount withheld |
| net_salary | decimal | What the employee actually receives |
| platform_fee | decimal | $599 flat, charged to company |
| status | enum | `pending`, `processing`, `completed`, `failed` |
| error | string | nullable — stores error message if failed |
| retry_count | integer | default 0, max 3 |
| inserted_at | datetime | |
| updated_at | datetime | |

**Constraints:**
- Unique on `(payroll_run_id, employee_id)` — prevents paying the same employee twice in a run

**Why snapshot gross_salary instead of reading from employee?**
If an employee's salary changes next month, it must not alter a past payroll record. The intent stores what was true at the moment of the run.

---

### `payslips`
Generated after a payroll_intent completes. The employee-facing document.

| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| payroll_intent_id | uuid | FK → payroll_intents |
| employee_id | uuid | FK → employees |
| pay_period | string | Denormalized for easy querying |
| gross_salary | decimal | |
| income_tax | decimal | |
| social_security | decimal | |
| net_salary | decimal | |
| generated_at | datetime | |
| inserted_at | datetime | |

**Immutable once created.**

---

### `payment_attempts`
One record per payment attempt. Tracks the full retry history for each payroll_intent.

| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| payroll_intent_id | uuid | FK → payroll_intents |
| attempt_number | integer | 1, 2, or 3 |
| status | enum | `succeeded`, `failed` |
| error | string | nullable — raw error from payment provider |
| attempted_at | datetime | When the attempt was made |
| inserted_at | datetime | |

**Constraints:**
- Unique on `(payroll_intent_id, attempt_number)` — prevents recording the same attempt twice

**Why this exists separately from `payroll_intents`:**
`payroll_intents.retry_count` tracks how many attempts have been made. `payment_attempts` stores the full history — what failed, when, and why. This separation keeps the intent clean and gives full audit trail of every interaction with the payment provider.

---

### `invoices`
One per payroll run. The company-facing document.

| Field | Type | Notes |
|-------|------|-------|
| id | uuid | PK |
| company_id | uuid | FK → companies |
| payroll_run_id | uuid | FK → payroll_runs |
| total_gross_salaries | decimal | Sum of all employee gross salaries |
| total_taxes_withheld | decimal | Sum of all taxes across employees |
| total_platform_fees | decimal | $599 × number of employees |
| total_amount | decimal | What the company owes |
| status | enum | `unpaid`, `paid` |
| issued_at | datetime | |
| paid_at | datetime | nullable |
| inserted_at | datetime | |
| updated_at | datetime | |

**Constraints:**
- Unique on `payroll_run_id` — one invoice per run
- Immutable once issued — corrections require a new run or credit note

---

## Relationships

```
companies ──< employees ──< payment_methods
    │               │
    │               └──> country_tax_rules
    │
    ├──< company_transactions
    │
    └──< payroll_runs ──< payroll_intents ──> payslips
              │                   │
              └──> invoices        └──< payment_attempts
```

---

## Scalability Notes

- **Never use float for money.** Always `decimal` with fixed precision. A float can silently misrepresent $0.01 at scale.
- **Balance uses a ledger table (`company_transactions`).** Append-only inserts are concurrent-safe — no two writes conflict the way a single `UPDATE balance = balance - X` would. Full audit history is free.
- **Salary snapshot on payroll_intent** protects historical accuracy — reads from employee at run time, never after.
- **Unique constraints on (company_id, pay_period) and (payroll_run_id, employee_id)** are the database-level idempotency guarantees. Application logic alone is not enough.
- **Indexes needed:** `company_id` on employees, `payroll_run_id` on payroll_intents, `employee_id` on payslips.
