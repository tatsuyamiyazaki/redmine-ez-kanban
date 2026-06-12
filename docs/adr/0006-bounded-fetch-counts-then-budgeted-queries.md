# Bounded board fetch: counts first, then per-column budgeted queries

The board never materializes more than `render_cap` issues per request. Leaf-ness
(ADR-0002) and Scope (R3) move into SQL via the nested set: a Leaf is
`issues.rgt = issues.lft + 1` (zero children in the full tree, recomputed every
render, never cached) and a Scope descendant is
`root_id = :root AND lft > :parent_lft AND rgt < :parent_rgt`. Board data access
becomes two phases on top of the active query's scope (visibility included):

1. **Counts** — one status-grouped `COUNT` over (query ∧ leaf ∧ scope ∧ range).
   Statuses map to Columns via the existing placement precedence, giving every
   Column its true WIP count (R10-1) and the board its over-cap total (R-0007)
   without instantiating a single row.
2. **Budgeted fetch** — Columns are drawn left to right sharing one
   `render_cap` budget (unchanged R-0007 semantics). Each Column with cards and
   remaining budget issues one `LIMIT`ed query (`status_id IN` that Column's
   statuses, ordered per R9), so total rows fetched ≤ `render_cap`.

In-column order (R9) also moves into SQL: the query's own sort when one was
supplied, otherwise priority position descending then due date ascending with
NULLs last (portable `CASE WHEN due_date IS NULL` expression, no
vendor-specific `NULLS LAST`).

## Considered Options

- **Counts query + per-column budgeted LIMIT queries (chosen).** 1 + (number of
  drawn Columns) cheap, index-friendly queries; memory is O(render_cap); WIP
  counts and the over-cap banner come from the counts phase — which is what
  issues 0003/0007 specified ("GROUP BY COUNT") before the implementation
  drifted to counting in Ruby over an unbounded fetch.
- **Status quo (fetch all, filter in Ruby).** Rejected: unbounded memory/CPU
  per request, amplified by the 30s polling option (security review MEDIUM-1).
- **Single fetch with `LIMIT render_cap + 1`.** Rejected: one global ORDER BY
  cannot reproduce the left-to-right per-column budget, so the wrong cards get
  drawn; true WIP counts and the over-cap banner would still need a counts
  query anyway.
- **One window-function query (`ROW_NUMBER() OVER (PARTITION BY status)`).**
  Rejected: harder to read, no measurable win at board scale, and column
  membership (Done/Unclassified fallback) is placement logic that lives in
  Layout, not SQL.
