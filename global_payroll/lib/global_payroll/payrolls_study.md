# Cómo estudiar payrolls.ex

## Capa 1 — Entiende los conceptos base primero

Antes de leer el código, asegúrate de entender bien estos conceptos de Elixir en aislamiento:

1. `with` — cómo funciona el happy path y el `else`
2. `Task.async_stream` — qué problema resuelve vs un `Enum.map` normal
3. `Ecto.Multi` — por qué existe vs un `Repo.transaction` simple
4. Pattern matching en `case` y `with`

Para cada uno, escribe un ejemplo pequeño en `iex` que no tenga nada que ver con payroll. Entiéndelo solo antes de verlo en contexto.

---

## Capa 2 — Lee el flujo principal, ignora los detalles

Lee solo las funciones públicas y los comentarios de las privadas, sin entrar en su implementación:

```
calculate_run → do_calculate → [6 pasos en orden]
```

Dibuja el flujo en papel. Qué pasa si falla el paso 1, el 3, el 5.

---

## Capa 3 — Entra a cada función privada

Una por una, en el orden en que se llaman. Para cada una pregúntate:
- ¿Qué recibe?
- ¿Qué devuelve?
- ¿Qué pasa si falla?

---

## Capa 4 — Pruébalo en `iex`

Esta es la más importante. Crea datos reales y llama cada función:

```elixir
# Llama fetch_active_employees directamente
# Llama calc_intent con un employee real
# Llama sum_total con datos inventados
# Llama calculate_run completo y observa el resultado
```

Ver los datos reales pasar por las funciones vale más que leer el código 10 veces.

---

## Capa 5 — Rómpelo a propósito

- ¿Qué pasa si el balance es 0?
- ¿Qué pasa si llamas `calculate_run` dos veces?
- ¿Qué pasa si un employee no tiene `country_tax_rule`?

Entender los casos de falla te da más confianza que entender solo el happy path.
