# Column model: global Setting-serialized config with explicit > is_done > unclassified precedence

Columns are a single global, admin-defined set stored as serialized structured data in the plugin's `Setting` (no dedicated tables), since the config is small and inherently global across all projects (Redmine statuses are global). Card placement precedence is: explicit status→Column mapping first; then the admin-designated `is_done` Column for unmapped `is_closed` statuses; then an implicit, always-present trailing "Unclassified" Column.

## Considered Options

- **Setting-serialized config (chosen).** Small, global dataset; avoids migrations and extra models. The admin editor is a custom settings partial either way.
- **Dedicated `kanban_columns` tables.** Rejected for v1: adds migrations, models, and CRUD UI without enough payoff at this scale.

## Consequences

The implicit Unclassified Column guarantees every Card has a home even when an admin forgets to map a status, satisfying Requirement 6-4. Explicit mappings deliberately override the `is_closed`→Done fallback, so a closed status can be shown in a non-Done Column if the admin chooses.
