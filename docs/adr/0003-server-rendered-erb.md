# Server-rendered ERB, reusing Redmine's IssueQuery and view helpers

The board is rendered server-side with ERB, reusing Redmine's `IssueQuery`, the standard filter partial, avatar/i18n helpers, and `Issue.visible` permission rules. Refresh is a manual button plus optional opt-in AJAX re-render of the board partial.

## Considered Options

- **Server-rendered ERB (chosen).** The board is read-only with no drag-and-drop, and every requirement leans on reusing Redmine's native query/permission/visibility machinery. ERB gets all of that for free with minimal code.
- **JSON API + JS frontend (SPA).** Rejected: it would duplicate rendering, permission, avatar, and i18n logic that Redmine already provides, which is overkill for a read-only board.
