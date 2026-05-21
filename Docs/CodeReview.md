# Code Review Progress

✅ = revisado | ⬜ = pendiente

---

## Config & Setup

- ✅ `config/config.exs` — ecto_repos, queues SQS, endpoint, mailer, logger, jason
- ✅ `config/dev.exs` — DB local, endpoint dev, AWS/LocalStack, logger limpio
- ✅ `config/prod.exs` — Swoosh real, logger :info
- ✅ `config/runtime.exs` — PHX_SERVER, secret_key_base, host/port, DNS cluster, endpoint prod
- ✅ `config/test.exs` — DB test, Sandbox pool, server false, Swoosh.Test
- ✅ `mix.exs` — project/0, application/0, cli/0, elixirc_paths/1, deps/0
- ✅ `.formatter.exs` — import_deps, subdirectories, inputs

---

## Core App

- ✅ `lib/global_payroll.ex` — módulo raíz vacío (placeholder)
- ✅ `lib/global_payroll/application.ex`
  - ✅ `start/2` — crea colas SQS, levanta árbol de supervisores
  - ✅ `config_change/3` — hot upgrade del endpoint
- ✅ `lib/global_payroll/repo.ex` — Ecto.Repo con adapter Postgres

---

## Infrastructure

- ⬜ `lib/global_payroll/queue.ex`
  - ⬜ `enqueue_calculate_payroll/1`
  - ⬜ `enqueue_payment_result/1`
  - ⬜ `enqueue_execute_payment/1`
  - ⬜ `enqueue_execute_payments/1`
  - ⬜ `batch_failed?/1` (private)
  - ⬜ `send_message/3` (private)
  - ⬜ `request_with_retry/2` (private)
  - ⬜ `send_backoff_ms/1` (private)

- ⬜ `lib/global_payroll/helpers/pagination.ex`
  - ⬜ `paginate/3`
  - ⬜ `next_cursor/2`
  - ⬜ `apply_cursor/2` (private)

- ⬜ `lib/global_payroll/helpers/mailer.ex` — Swoosh.Mailer config

---

## Domain: Companies

- ⬜ `lib/global_payroll/companies.ex`
  - ⬜ `list_companies/2`
  - ⬜ `get_company/1`
  - ⬜ `create_company/1`
  - ⬜ `update_company/2`
  - ⬜ `get_company_balance/1`
  - ⬜ `list_transactions/4`
  - ⬜ `apply_tx_cursor/2` (private)
  - ⬜ `tx_next_cursor/2` (private)

- ✅ `lib/global_payroll/companies/company.ex`
  - ✅ `changeset/2`

---

## Domain: Employees

- ⬜ `lib/global_payroll/employees.ex`
  - ⬜ `get_employee/1`
  - ⬜ `create_employee/1`
  - ⬜ `update_employee/2`
  - ⬜ `count_employees_by_company/1`
  - ⬜ `list_employees_by_company/3`
  - ⬜ `list_active_employees/1`
  - ⬜ `list_payment_methods/1`
  - ⬜ `get_payment_method/1`
  - ⬜ `add_payment_method/2`
  - ⬜ `update_payment_method/2`
  - ⬜ `delete_payment_method/1`
  - ⬜ `get_default_payment_method/1`

- ✅ `lib/global_payroll/employees/employee.ex`
  - ✅ `changeset/2`

- ✅ `lib/global_payroll/employees/payment_method.ex`
  - ✅ `changeset/2`

---

## Domain: Taxes

- ⬜ `lib/global_payroll/taxes.ex`
  - ⬜ `list_country_tax_rules/2`
  - ⬜ `get_country_tax_rule/1`
  - ⬜ `create_country_tax_rule/1`
  - ⬜ `update_country_tax_rule/2`

- ✅ `lib/global_payroll/taxes/country_tax_rule.ex`
  - ✅ `changeset/2`

---

## Domain: Ledger

- ⬜ `lib/global_payroll/ledger.ex`
  - ⬜ `deposit/4`
  - ⬜ `refund/4`
  - ⬜ `payroll_deduction/4`
  - ⬜ `create_company_transaction/1` (private)

- ✅ `lib/global_payroll/ledgers/company_transaction.ex`
  - ✅ `changeset/2`

---

## Domain: Payments

- ⬜ `lib/global_payroll/payments.ex`
  - ⬜ `reconcile_stuck_intents/0`
  - ⬜ `execute_payment/1`
  - ⬜ `handle_webhook_event/1`
  - ⬜ `process_result/1`
  - ⬜ `fetch_intent/1` (private)
  - ⬜ `fetch_by_provider_id/1` (private)
  - ⬜ `lock_intent/1` (private)
  - ⬜ `guard_already_settled/1` (private)
  - ⬜ `attempt_payment/1` (private)
  - ⬜ `perform_payment_attempt/2` (private)
  - ⬜ `persist_provider_result/2` (private)
  - ⬜ `dispatch_provider_result/2` (private)
  - ⬜ `dispatch_success_result/1` (private)
  - ⬜ `dispatch_failure_result/2` (private)
  - ⬜ `enqueue_result/1` (private)
  - ⬜ `resume_after_provider_success/2` (private)
  - ⬜ `resume_after_provider_failure/2` (private)
  - ⬜ `mock_provider_id/2` (private)
  - ⬜ `record_attempt/3` (private)
  - ⬜ `get_attempt/2` (private)
  - ⬜ `on_success/1` (private)
  - ⬜ `on_failure/3` (private)
  - ⬜ `on_max_retries/2` (private)
  - ⬜ `stuck_cutoff/0` (private)
  - ⬜ `reconcile_processing_with_attempts/0` (private)
  - ⬜ `reconcile_processing_without_attempts/0` (private)
  - ⬜ `reconcile_pending_without_attempts/0` (private)

- ⬜ `lib/global_payroll/payments/mock_payment_provider.ex`
  - ⬜ `call/1`

- ✅ `lib/global_payroll/payments/payment_attempt.ex`
  - ✅ `changeset/2`

---

## Domain: Payrolls

- ⬜ `lib/global_payroll/payrolls.ex`
  - ⬜ `create_run/2`
  - ⬜ `list_runs/3`
  - ⬜ `get_run/1`
  - ⬜ `list_intents/1`
  - ⬜ `count_intents_by_status/1`
  - ⬜ `list_intent_ids/1`
  - ⬜ `list_intents_page/4`
  - ⬜ `get_intent_with_preloads/1`
  - ⬜ `list_payslips_by_run/1`
  - ⬜ `list_payslips_by_run_page/3`
  - ⬜ `list_payslips_by_employee/1`
  - ⬜ `list_invoices_by_company/1`
  - ⬜ `approve_run/1`
  - ⬜ `start_paying/1`
  - ⬜ `cancel_run/1`
  - ⬜ `calculate_run/1`
  - ⬜ `close_completed_runs/0`
  - ⬜ `do_calculate/1` (private)
  - ⬜ `compute_expected_total/1` (private)
  - ⬜ `insert_intents_in_chunks/2` (private)
  - ⬜ `build_intent_row/3` (private)
  - ⬜ `enqueue_payments/1` (private)
  - ⬜ `check_balance/2` (private)
  - ⬜ `validate_calculable/1` (private)
  - ⬜ `validate_cancellable/1` (private)
  - ⬜ `maybe_transition_to_calculating/1` (private)
  - ⬜ `validate_transition/2` (private)
  - ⬜ `transition/2` (private)
  - ⬜ `mark_failed/2` (private)

- ✅ `lib/global_payroll/payrolls/payroll_run.ex`
  - ✅ `changeset/2`

- ✅ `lib/global_payroll/payrolls/payroll_intent.ex`
  - ✅ `changeset/2`

- ✅ `lib/global_payroll/payrolls/payslip.ex`
  - ✅ `changeset/2`

- ✅ `lib/global_payroll/payrolls/invoice.ex`
  - ✅ `changeset/2`

---

## Workers

- ⬜ `lib/global_payroll/workers/payroll_worker.ex`
  - ⬜ `start_link/1`
  - ⬜ `handle_message/3`

- ⬜ `lib/global_payroll/workers/payment_results_worker.ex`
  - ⬜ `start_link/1`
  - ⬜ `handle_message/3`

- ⬜ `lib/global_payroll/workers/invoice_worker.ex`
  - ⬜ `start_link/1`
  - ⬜ `init/1`
  - ⬜ `handle_info/2`
  - ⬜ `schedule/0` (private)

---

## Web: Core

- ✅ `lib/global_payroll_web.ex` — macro factory para controllers, routers, live_views
- ⬜ `lib/global_payroll_web/endpoint.ex`
- ⬜ `lib/global_payroll_web/router.ex`
- ⬜ `lib/global_payroll_web/telemetry.ex`
  - ⬜ `start_link/1`
  - ⬜ `init/1`
  - ⬜ `metrics/0`
  - ⬜ `periodic_measurements/0` (private)
- ⬜ `lib/global_payroll_web/gettext.ex`
- ⬜ `lib/global_payroll_web/helpers.ex`
  - ⬜ `format_money/1`
  - ⬜ `format_number/1`
- ⬜ `lib/global_payroll_web/layouts.ex`

---

## Web: Controllers

- ⬜ `lib/global_payroll_web/controllers/company_controller.ex`
  - ⬜ `index/2`
  - ⬜ `create/2`
  - ⬜ `update/2`
  - ⬜ `list_invoices/2`
- ⬜ `lib/global_payroll_web/controllers/company_json.ex`

- ⬜ `lib/global_payroll_web/controllers/employee_controller.ex`
  - ⬜ `index/2`
  - ⬜ `create/2`
  - ⬜ `update/2`
  - ⬜ `list_payslips/2`
- ⬜ `lib/global_payroll_web/controllers/employee_json.ex`

- ⬜ `lib/global_payroll_web/controllers/payroll_run_controller.ex`
  - ⬜ `index/2`
  - ⬜ `show/2`
  - ⬜ `create/2`
  - ⬜ `start/2`
  - ⬜ `approve/2`
  - ⬜ `cancel/2`
  - ⬜ `list_intents/2`
  - ⬜ `list_payslips/2`
  - ⬜ `format_error/1` (private)
- ⬜ `lib/global_payroll_web/controllers/payroll_run_json.ex`

- ⬜ `lib/global_payroll_web/controllers/payment_method_controller.ex`
  - ⬜ `index/2`
  - ⬜ `create/2`
  - ⬜ `update/2`
  - ⬜ `delete/2`
- ⬜ `lib/global_payroll_web/controllers/payment_method_json.ex`

- ⬜ `lib/global_payroll_web/controllers/country_tax_rule_controller.ex`
  - ⬜ `index/2`
  - ⬜ `update/2`
- ⬜ `lib/global_payroll_web/controllers/country_tax_rule_json.ex`

- ⬜ `lib/global_payroll_web/controllers/company_transaction_controller.ex`
  - ⬜ `index/2`
  - ⬜ `deposit/2`
- ⬜ `lib/global_payroll_web/controllers/company_transaction_json.ex`

- ⬜ `lib/global_payroll_web/controllers/payment_webhook_controller.ex`
  - ⬜ `event/2`

- ⬜ `lib/global_payroll_web/controllers/error_json.ex`
  - ⬜ `render/2`

---

## Web: LiveView

- ⬜ `lib/global_payroll_web/live/companies_live.ex`
- ⬜ `lib/global_payroll_web/live/company_show_live.ex`
- ⬜ `lib/global_payroll_web/live/run_show_live.ex`

---

## Orden de revisión sugerido

1. **Schemas** — Solo structs y validaciones, base para entender todo lo demás:
   `company.ex`, `employee.ex`, `payment_method.ex`, `country_tax_rule.ex`, `company_transaction.ex`, `payroll_run.ex`, `payroll_intent.ex`, `payslip.ex`, `invoice.ex`, `payment_attempt.ex`

2. **Contextos simples** — CRUD básico:
   `companies.ex`, `employees.ex`, `taxes.ex`

3. **Infrastructure** — Utilidades que usan los demás:
   `pagination.ex`, `queue.ex`

4. **Ledger** — Lógica de dinero, corto pero importante:
   `ledger.ex`

5. **Workers** — Broadway, cortos y dan contexto para entender payments:
   `payroll_worker.ex`, `payment_results_worker.ex`, `invoice_worker.ex`

6. **Payrolls** — El contexto más grande, orquesta todo el flujo:
   `payrolls.ex`

7. **Payments** — El más complejo: retries, idempotencia, reconciliación:
   `payments.ex`

8. **Web** — Al final porque ya entiendes el dominio:
   `router.ex`, controllers, LiveViews

> Los LiveViews se pueden saltar si el tiempo aprieta — para la entrevista el dominio importa más que la UI.
