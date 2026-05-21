defmodule GlobalPayroll.Pagination do
  import Ecto.Query

  # Applies cursor-based pagination to any Ecto query.
  # Orders by inserted_at + id so results are stable and consistent across pages.
  # Returns at most `per_page` records starting after the given cursor.
  def paginate(query, cursor, per_page) do
    query
    |> apply_cursor(cursor)
    |> order_by([q], asc: q.inserted_at, asc: q.id)
    |> limit(^per_page)
  end

  # No more pages — returns nil when results are fewer than a full page.
  def next_cursor(results, per_page) when length(results) < per_page, do: nil
  # Full page returned — cursor points to the last record so the next call starts after it.
  def next_cursor(results, _per_page) do
    last = List.last(results)
    {last.inserted_at, last.id}
  end

  # No cursor means first page — return all records from the beginning.
  defp apply_cursor(query, nil), do: query
  # Cursor present — skip everything up to and including the last seen record.
  # Uses inserted_at as the primary sort key, id as tiebreaker for same-timestamp records.
  defp apply_cursor(query, {inserted_at, id}) do
    where(
      query,
      [q],
      q.inserted_at > ^inserted_at or
        (q.inserted_at == ^inserted_at and q.id > ^id)
    )
  end
end
