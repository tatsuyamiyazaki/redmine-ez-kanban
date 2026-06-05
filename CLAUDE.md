# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

This repository is at the **requirements stage**: there are no commits, no source code, and no build tooling yet. The single source of truth is [`docs/requirements.md`](docs/requirements.md) — read it in full before any implementation work. It is a *checkpoint* document: the display layer (cards, columns, filters, sorting, WIP) is finalized; permissions detail and non-functional requirements are explicitly listed as open (`未確定事項`) and must be confirmed before being built.

When scaffolding begins, update this file with the actual build/test/lint commands.

## What this is

`redmine-ez-kanban` is a **Redmine plugin** (Ruby on Rails) that renders a project's issues as a Kanban board. It is therefore expected to follow Redmine's plugin layout (`init.rb`, `app/`, `lib/`, `config/`, `assets/`, `test/`) and live inside a host Redmine install under `plugins/`.

## Non-negotiable design constraints

These come straight from the requirements and shape the entire architecture. Do not violate them:

- **Strictly read-only.** The board never writes to Redmine — no status/assignee changes, no drag-to-move, no reordering. All editing is delegated to Redmine core. Any feature that would mutate an issue is out of scope by definition (Req 5).
- **Cards are leaves only.** A card represents an issue with *no children* (a leaf or standalone issue). Parent issues are never rendered as cards and are never a unit of operation. Leaf-ness is dynamic — it must be recomputed on each render, not cached (Req 1, 4).
- **Flat layout, no swimlanes.** All leaf cards sit flat inside status columns. Parent hierarchy is shown only as a breadcrumb on each card (root → nearest parent), truncated with a hover-to-expand full path when too wide (Req 2).
- **Fixed, status-grouped columns.** Columns are a single global, admin-defined set with a status→column mapping, shared across all projects (Redmine statuses are global). `is_closed` statuses fall into the "完了" column even without an explicit mapping; unmapped non-closed statuses fall into a trailing "未分類" column (Req 6).
- **Reuse Redmine's `IssueQuery`.** Filtering is built on Redmine's standard query mechanism so saved queries, custom fields, and visibility/permission rules all apply for free — never re-implement filtering or visibility checks (Req 7).

## Key domain concepts

- **Scope** — an optional single-parent filter that restricts the board to *all descendant leaves* of that parent at any depth. Scope is ANDed with the active query filter (Req 3, 7-4).
- **Sort within a column** — follows the query's sort order; default fallback is priority desc, then due date ascending (Req 9).
- **WIP** — each column shows its card count; per-column thresholds can highlight over-capacity columns, but highlighting is **off by default** and is purely informational (never affects placement or visibility) (Req 10).

## Redmine plugin conventions (apply once code exists)

A live Redmine instance is reachable via the `redmine` MCP server — use it to inspect real statuses, trackers, queries, and the issue tree rather than guessing the data model.

Standard Redmine plugin commands (run from the host Redmine root, not this repo root):

```bash
# Run this plugin's tests only
bundle exec rake redmine:plugins:test NAME=redmine_ez_kanban RAILS_ENV=test

# Run a single test file
bundle exec ruby -Itest plugins/redmine_ez_kanban/test/unit/<file>_test.rb

# Plugin migrations
bundle exec rake redmine:plugins:migrate NAME=redmine_ez_kanban RAILS_ENV=production
```
