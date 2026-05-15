# Global Payroll System — Implementation Guide

---

## Fase 1 — Setup

### 1. Crear proyecto Phoenix

```bash
mix phx.new global_payroll --no-html --no-assets
cd global_payroll
```

### 2. Agregar dependencias

En `mix.exs`:

```elixir
{:broadway, "~> 1.0"},
{:ex_aws, "~> 2.0"},
{:ex_aws_sqs, "~> 3.0"},
{:hackney, "~> 1.9"},
{:jason, "~> 1.0"}
```

### 3. Configurar PostgreSQL

En `config/dev.exs`, verificar que apunta a `localhost:5432` con user/password `postgres`.

### 4. Configurar SQS

En `config/dev.exs`:

```elixir
config :ex_aws,
  access_key_id: "local",
  secret_access_key: "local",
  region: "us-east-1"

config :ex_aws, :sqs,
  scheme: "http://",
  host: "localhost",
  port: 9324
```

**Verificar:** `mix deps.get` y `mix phx.server` sin errores.

---

## Fase 2 — Base de Datos

### 5. Escribir migraciones

Crear en este orden (respeta foreign keys):


| #   | Tabla                  | Comando                                              |
| --- | ---------------------- | ---------------------------------------------------- |
| 1   | `companies`            | `mix ecto.gen.migration create_companies`            |
| 2   | `country_tax_rules`    | `mix ecto.gen.migration create_country_tax_rules`    |
| 3   | `employees`            | `mix ecto.gen.migration create_employees`            |
| 4   | `payment_methods`      | `mix ecto.gen.migration create_payment_methods`      |
| 5   | `company_transactions` | `mix ecto.gen.migration create_company_transactions` |
| 6   | `payroll_runs`         | `mix ecto.gen.migration create_payroll_runs`         |
| 7   | `payroll_intents`      | `mix ecto.gen.migration create_payroll_intents`      |
| 8   | `payslips`             | `mix ecto.gen.migration create_payslips`             |
| 9   | `invoices`             | `mix ecto.gen.migration create_invoices`             |


Referencia de campos: `2- DATA_MODEL.md`.

**Verificar:** `mix ecto.migrate` sin errores. Confirmar tablas en Adminer (`localhost:8080`).

### 6. Escribir Ecto schemas

Un schema por tabla en `lib/global_payroll/`. Incluir tipos, validaciones y constraints del data model.

**Verificar:** `mix compile` sin errores.

---

## Fase 3 — Contextos

Implementar en orden de dependencia — cada contexto solo puede llamar a los anteriores.

### 7. `Companies`

- Registrar empresa (status inicial: `pending`)
- Activar empresa
- Calcular balance: `SELECT SUM(amount) FROM company_transactions WHERE company_id = x`

**Verificar:** Crear empresa en iex, activarla, consultar balance vacío = 0.

### 8. `Taxes`

- Lookup de reglas por `country_code`
- Seed de países con sus tasas (`income_tax_rate`, `social_security_rate`)

**Verificar:** `Taxes.get_by_country("MX")` retorna la regla correcta.

### 9. `Employees`

- Crear employee (vinculado a company y country_tax_rule)
- Agregar método de pago (default)
- Solo employees `active` participan en payroll

**Verificar:** Crear employee, asignarle banco, listarlo por empresa.

### 10. `Ledger`

- Solo inserts — nunca updates ni deletes
- Tipos: `deposit`, `payroll_deduction`, `refund`
- `deposit/2` — agrega fondos a una empresa

**Verificar:** Insertar depósito, confirmar que el balance de la empresa aumenta.

### 11. `Payroll`

- Crear run (`draft`)
- Calcular run:
  - Verificar balance suficiente
  - Para cada employee: calcular `gross - income_tax - social_security` → crear `payroll_intent`
  - Status: `draft → calculating → pending_approval`
- State machine — ningún estado puede saltarse

**Verificar:** Crear run, calcularlo, revisar intents generados con montos correctos.

### 12. `Payments`

- Ejecutar pago individual por `payroll_intent_id`
- Llamar al payment provider (mock — retorna éxito/fallo aleatorio)
- Reintentos: hasta 3 veces antes de marcar `failed`
- Si falla: insertar `refund` en el ledger
- Si completa: insertar `payroll_deduction` en el ledger

**Verificar:** Ejecutar pago mock, verificar que el ledger se actualiza correctamente.

---

## Fase 4 — API

### 13. Controllers y rutas

Implementar siguiendo `3- API DESIGN.md`:


| Recurso         | Rutas                                                                                                      |
| --------------- | ---------------------------------------------------------------------------------------------------------- |
| Companies       | `GET /companies`, `POST /companies`, `PUT /companies/:id`                                                  |
| Employees       | `GET /employees`, `POST /employees`, `PUT /employees/:id`                                                  |
| Payment Methods | `GET /payment-methods`, `POST /payment-methods`, `PUT /payment-methods/:id`, `DELETE /payment-methods/:id` |
| Taxes           | `GET /country-tax-rules`, `PUT /country-tax-rules/:id`                                                     |
| Payroll Runs    | `GET /payroll-runs`, `GET /payroll-runs/:id`, `POST /payroll-runs`                                         |
| Payroll Actions | `POST /payroll-runs/:id/start`, `POST /payroll-runs/:id/approve`                                           |
| Payroll Intents | `GET /payroll-runs/:id/intents`                                                                            |
| Payslips        | `GET /payroll-runs/:id/payslips`, `GET /employees/:id/payslips`                                            |
| Invoices        | `GET /companies/:id/invoices`                                                                              |
| Transactions    | `GET /companies/:id/transactions`, `POST /companies/:id/deposit`                                           |


**Verificar:** Cada endpoint responde con el status y shape correctos.

### 14. Probar con curl/Postman

Recorrer el happy path completo antes de seguir:

1. Crear empresa → activar → depositar fondos
2. Agregar employees con banco
3. Crear run → start → verificar status `pending_approval`
4. Aprobar run → verificar status `approved`

---

## Concurrencia — Qué usar y dónde

Antes de implementar los workers, entender qué herramienta aplica en cada caso:


| Herramienta           | Usar?                   | Por qué                                                                                         |
| --------------------- | ----------------------- | ----------------------------------------------------------------------------------------------- |
| **Broadway**          | Sí — es el core         | Consume SQS, maneja concurrencia, acks y reintentos automáticamente                             |
| **Task.async_stream** | Sí — dentro de Broadway | Para calcular net pay de N employees en paralelo dentro de un solo mensaje                      |
| **Task.Supervisor**   | No                      | Broadway ya supervisa sus workers                                                               |
| **DynamicSupervisor** | No                      | Sería necesario si el estado del run viviera en un proceso en memoria — pero vive en PostgreSQL |
| **GenServer**         | No                      | Mismo motivo — no hay estado en memoria que mantener entre llamadas                             |


### Flujo real del async

```
API controller
  → ExAws.SQS.send_message()       # síncrono, retorna 202 inmediatamente
      ↓
  Broadway consumer (proceso separado)
    → handle_message/2
        → "calculate_payroll" → Task.async_stream(employees, &calc_net_pay/1)
        → "execute_payment"   → Payments.execute(intent_id)  # un intent por mensaje
```

El API no espera nada — su responsabilidad termina cuando publica el mensaje. Broadway toma el control desde ahí.

### Por qué NO usar Task directamente desde el API controller

```elixir
# Esto parece funcionar pero es frágil:
Task.start(fn -> Payroll.calculate(run_id) end)

# Si el nodo se reinicia, la tarea desaparece — el run queda en status "calculating" para siempre.
# SQS + Broadway resuelven esto: el mensaje vuelve a la cola si no se ackea.
```

---

## Fase 5 — Workers (Broadway)

### 15. `PayrollWorker` — consume `payroll-jobs`

Maneja dos tipos de mensaje:


| job                 | Acción                                                             | Concurrencia                                               |
| ------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------- |
| `calculate_payroll` | Calcula net pay por employee, crea intents                         | `Task.async_stream` sobre la lista de employees            |
| `execute_payment`   | Ejecuta un pago individual, publica resultado en `payment-results` | Broadway procesa N mensajes en paralelo (uno por employee) |


Estructura básica:

```elixir
defmodule GlobalPayroll.Workers.PayrollWorker do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwaySQS.Producer, queue_url: "http://localhost:9324/.../payroll-jobs"}
      ],
      processors: [default: [concurrency: 10]]
    )
  end

  def handle_message(_, %{data: data} = message, _) do
    case Jason.decode!(data) do
      %{"job" => "calculate_payroll", "run_id" => run_id} ->
        Payroll.calculate(run_id)

      %{"job" => "execute_payment", "intent_id" => intent_id} ->
        Payments.execute(intent_id)
    end

    message
  end
end
```

### 16. `ResultsWorker` — consume `payment-results`


| status      | Acción                                           |
| ----------- | ------------------------------------------------ |
| `completed` | `Ledger.record_deduction(intent_id)` + notificar |
| `failed`    | `Ledger.record_refund(intent_id)` + notificar    |


**Verificar:** Publicar mensaje de prueba en `payroll-jobs` desde iex, confirmar que Broadway lo procesa y actualiza el estado del run.

---

## Fase 6 — Smoke Test End-to-End

### 17. Happy path completo

```
POST /companies              → crear empresa
PUT  /companies/:id          → activar
POST /companies/:id/deposit  → depositar fondos
POST /employees              → crear 3 employees con banco
POST /payroll-runs           → crear run
POST /payroll-runs/:id/start → calcular (Broadway procesa)
GET  /payroll-runs/:id       → verificar status: pending_approval
POST /payroll-runs/:id/approve → aprobar (Broadway procesa pagos)
GET  /payroll-runs/:id       → verificar status: completed
GET  /companies/:id/transactions → verificar ledger con deductions
GET  /payroll-runs/:id/payslips  → verificar payslips generados
GET  /companies/:id/invoices     → verificar invoice generada
```

---

## Orden de dependencias (resumen)

```
Migrations → Schemas → Companies → Taxes → Employees
                                              │
                                           Ledger
                                              │
                                           Payroll → Payments
                                                          │
                                                       Workers → API
```

