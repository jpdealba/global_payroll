# Code Review Progress

✅ = revisado | ⬜ = pendiente | ⚠️ = pendiente de repasar

---

## Esta noche — 9pm a 11pm (2h)

**9:00 - 9:45** — Repasar payments pendiente

- LISTO

**9:45 - 10:15** — Router y tests por encima

- LISTO

**10:15 - 10:45** — LiveView rápido

- LISTO

**10:45 - 11:00** — Práctica oral del flujo completo, una vez

- LISTO

**11:00** — Para. A dormir.

---

## Mañana — 8am a 11:30am

**8:00 - 8:45** — Temas técnicos

- **SQS vs Oban vs Kafka** — cuándo usar cada uno, por qué elegimos SQS aquí
- **Bottlenecks del sistema** — insert_all en chunks, async_stream, batch SQS, lock_intent
- **Decisiones de diseño que puedes defender** — reconciliation job vs DLQ, idempotency keys, Ecto.Multi en on_success
- **Errores que encontraste** — `@max_send_retries 5` que en realidad son 4 intentos, atom/string en add_payment_method

**8:45 - 9:15** — Tests

- Leer `payments_test.exs` con calma — happy path, failure, edge cases
- Poder describir cómo sería un test e2e aunque no esté escrito

**9:15 - 10:00** — Práctica oral final

- Flujo completo de voz, una vez más
- Repasar preguntas para hacerles a ellos

**10:00 - 11:30** — Buffer. No estudies más, descansa.

---

## Preguntas para hacerles a ellos

1. ¿Qué proyectos les han presentado candidatos que les hayan llamado la atención, y qué tenían en común?
2. ¿Cuál es el problema técnico más difícil que el equipo ha tenido que resolver en el último año?
3. ¿Cómo está estructurado el proceso de code review y quién tiene voz en decisiones de arquitectura?
4. ¿Cuál es el stack actual en producción y hay planes de cambiar algo?
5. ¿Cómo manejan el onboarding técnico — hay documentación, hay un buddy, cuánto tarda alguien en hacer su primer deploy?

---

## Ya revisado

Todo el dominio (`payments.ex`, `payrolls.ex`, `ledger.ex`, `employees.ex`, `companies.ex`, `taxes.ex`), workers (Broadway), infrastructure (queue, pagination, mailer), schemas, config, core app.