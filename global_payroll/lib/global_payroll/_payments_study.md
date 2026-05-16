# Cómo estudiar payments.ex

## El problema que resuelve

Ejecutar un pago bancario no es una operación simple. Puede fallar, puede tardarse, puede ejecutarse dos veces si el sistema crashea en el momento equivocado. Este módulo resuelve los tres problemas.

## Flujo principal

```
execute_payment(intent_id)
        ↓
¿Ya fue procesado? → salir (idempotencia)
        ↓
Llamar al provider (mock por ahora)
        ↓
Registrar intento en payment_attempts
        ↓
¿Éxito?  → marcar completed + deducir del ledger
¿Fallo?  → ¿quedan reintentos? → incrementar retry_count → Broadway reintenta
                                → sin reintentos → marcar failed + refund al ledger
```

## Conceptos clave para entender primero

### 1. Idempotencia
```elixir
defp guard_already_settled(%{status: status}) when status in ["completed", "failed"]
```
Broadway puede entregar el mismo mensaje más de una vez si el worker crashea.
Sin este guard, el mismo empleado podría recibir dos pagos.

### 2. Por qué Ecto.Multi en on_success y on_max_retries
Tanto el intent como el ledger deben actualizarse juntos.
Si marcas el intent como "completed" pero falla el insert del ledger,
el balance de la company nunca se debita — inconsistencia financiera.
Multi garantiza que ambos ocurren o ninguno.

### 3. El retry mechanism
```
attempt_number = intent.retry_count + 1
```
No es un loop dentro de la función. Broadway reencola el mensaje.
Cada vez que Broadway llama a execute_payment, el retry_count aumenta.
Cuando llega a 3, on_max_retries cierra el caso.

### 4. El mock provider
```elixir
if :rand.uniform(10) > 3 do :ok else {:error, ...}
```
70% de probabilidad de éxito, 30% de fallo.
Cuando integres un provider real (Wise, banco), solo reemplazas este módulo.
El resto del código no cambia.

## Capas de estudio

**Capa 1 — Entiende los conceptos base**
- ¿Qué es idempotencia y por qué importa en pagos?
- ¿Cómo funciona `Ecto.Multi.run` vs `Multi.update`?
- ¿Cómo Broadway reintenta mensajes fallidos?

**Capa 2 — Lee el flujo sin entrar a las funciones**
Lee solo `execute_payment` y los nombres de las funciones privadas.
Dibuja el árbol de decisiones: éxito, fallo con reintentos, fallo sin reintentos.

**Capa 3 — Entra a cada función privada**
- `guard_already_settled` — ¿cuándo retorna `:ok`? ¿cuándo retorna error?
- `attempt_payment` — ¿qué hace con el resultado del provider?
- `on_success` — ¿qué escribe en la DB? ¿en qué orden?
- `on_failure` — ¿cómo decide si retry o give up?
- `on_max_retries` — ¿qué escribe en la DB? ¿qué devuelve?

**Capa 4 — Pruébalo en iex**
```elixir
# Llama execute_payment con un intent_id real
# Llama varias veces — verifica que la segunda vez retorna :already_settled
# Revisa payment_attempts en la DB
# Revisa company_transactions para ver el ledger
```

**Capa 5 — Rómpelo a propósito**
- ¿Qué pasa si llamas execute_payment con un intent que no existe?
- ¿Qué pasa si el ledger insert falla? ¿El intent queda completed?
- ¿Qué pasa si el provider siempre falla? ¿Llega a max retries?
