# Redmine EZ Kanban

A read-only Kanban board plugin for Redmine that visualizes a project's issues as cards grouped into fixed status columns. The board is purely for observation; all editing stays in Redmine core.

## Language

**Leaf** (リーフ):
An issue that has no child issues in the Redmine tree. Leaf-ness is a global property of the full issue tree, independent of any filter. The unit of card display.
_Avoid_: terminal issue, end ticket

**Card**:
The visual representation of a single Leaf. A Leaf is shown as a Card if and only if it is a leaf in the full tree **and** matches the active IssueQuery filter. Parents and ancestors are never Cards.
_Avoid_: tile, ticket box

**Column** (列):
One of a fixed, global, admin-defined set of buckets that Cards are placed into. A Column maps to one or more Redmine statuses. Columns are shared across all projects. Placement precedence: explicit status→Column mapping first, then the Done Column for unmapped closed statuses, then the Unclassified Column.
_Avoid_: lane, bucket, stage

**Done Column** (完了列):
The single Column the admin designates (via an `is_done` flag) as the fallback for `is_closed` statuses that have no explicit mapping. Explicit mappings still win over it.
_Avoid_: closed column, finished column

**Unclassified Column** (未分類列):
An implicit, always-present trailing Column (not admin-editable) that catches non-closed statuses with no explicit mapping. Guarantees every Card has a home.
_Avoid_: misc column, other column, default column

**Scope** (スコープ):
An optional restriction to a single chosen parent issue: the board then shows only the descendant Leaves of that parent (any depth), ANDed with the active filter.
_Avoid_: filter, parent filter, subtree

**Breadcrumb** (パンくず):
The ancestor path (root → nearest parent) displayed on a Card for context. Standalone issues (no parent) have no Breadcrumb.
_Avoid_: trail, path, hierarchy label

**WIP**:
The per-Column count of Cards, plus an optional threshold that visually highlights an over-capacity Column. Highlighting is off by default and never affects placement or visibility.
_Avoid_: load, capacity, limit
