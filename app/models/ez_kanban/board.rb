# frozen_string_literal: true

module EzKanban
  # Decides the set of Cards for a project's board.
  #
  # A Card is an issue that is a leaf in the FULL issue tree (no children,
  # independent of any filter), matches the active query, and is visible to
  # the current user (ADR-0002). Leaf-ness is evaluated in SQL over the whole
  # tree via the nested set (rgt = lft + 1), recomputed on every request.
  #
  # Data access is bounded (ADR-0006, issue 0011): one status-grouped COUNT
  # gives every column its true WIP total (R10-1) and the board its over-cap
  # state (R-0007) without materializing a row; the per-column fetches then
  # share render_cap as one left-to-right row budget, so a request never
  # instantiates more than render_cap issues.
  class Board
    # Global render cap (R-0007): how many cards the board will draw at most,
    # protecting the server/DOM on large projects. Admin-adjustable via Setting.
    DEFAULT_RENDER_CAP = 500

    # In-column fallback order (R9) when the caller supplied no query:
    # priority desc, then due date asc with missing dates last. Plain SQL kept
    # portable across PG/MySQL/SQLite (no NULLS LAST); Arel.sql marks the
    # expressions as trusted for Rails' raw-order check. IssueQuery joins the
    # priority table itself when the order references it.
    FALLBACK_ORDER = [
      Arel.sql("#{IssuePriority.table_name}.position DESC"),
      Arel.sql("CASE WHEN #{Issue.table_name}.due_date IS NULL THEN 1 ELSE 0 END"),
      Arel.sql("#{Issue.table_name}.due_date ASC")
    ].freeze

    # The effective query driving the board, exposed so the filter UI (issue
    # 0006) can render the current filters and selected saved query.
    attr_reader :query

    def initialize(project, query: nil, include_subprojects: false,
                   scope_issue: nil)
      @project = project
      # Board range control (R-0007, scope A): off by default restricts the
      # board to this project's own issues; on widens it to all descendants.
      @include_subprojects = include_subprojects
      # Optional single-parent scope (R3): when set, restrict the board to all
      # descendant leaves of this issue at any depth, ANDed with the active
      # query (R7-4). nil leaves the board flat over every leaf.
      @scope_issue = scope_issue
      # A caller-supplied query carries its own sort (R9); the board's own
      # default query is treated as unsorted so the R9 fallback order applies.
      @query_sorted = !query.nil?
      @query = query || default_query
      # Widening to subprojects rides on the standard subproject filter so the
      # query's own statement carries the range for counts and fetches alike.
      widen_to_subprojects if include_subprojects
    end

    # Visible leaf issues drawn on the board, as a flat list (≤ render_cap).
    def cards
      columns.flat_map(&:cards)
    end

    # The cap on how many cards the board renders (R-0007). Admin-set via
    # Setting; non-positive or missing values fall back to the default.
    def render_cap
      configured = Setting.plugin_redmine_ez_kanban['render_cap'].to_i
      configured.positive? ? configured : DEFAULT_RENDER_CAP
    end

    # Whether the matching card total exceeds the render cap, so the board
    # truncated what it drew and should warn the user (R-0007 banner).
    # Decided from the counts query — no cards are materialized for this.
    def over_cap?
      status_counts.values.sum > render_cap
    end

    # Whether WIP threshold highlighting is enabled (R10-3, opt-in). A global
    # setting shared across all projects (R6-5); off by default.
    def highlight_wip?
      ColumnConfig.truthy?(Setting.plugin_redmine_ez_kanban['highlight_wip'])
    end

    # Cards grouped into the board's status columns (issue 0003). Drawn left
    # to right, columns share one render_cap budget with no per-column paging
    # (R-0007); wip_count carries each column's true total from the counts
    # query, so WIP and over-WIP detection stay correct under truncation.
    def columns
      @columns ||= begin
        layout = Layout.default
        ids_by_key = status_ids_by_column(layout)
        remaining = render_cap
        layout.definitions.map do |definition|
          ids = ids_by_key.fetch(definition.key, [])
          total = ids.sum { |id| status_counts.fetch(id, 0) }
          drawn = fetch_cards(ids, [remaining, 0].max, total)
          remaining -= drawn.size
          Column.new(key: definition.key, name: definition.name,
                     is_done: definition.is_done, wip_limit: definition.wip_limit,
                     cards: drawn, wip_count: total)
        end
      end
    end

    private

    # R-0007 scope A: widen the query to the whole subtree via the standard
    # subproject filter (only when the project actually has subprojects).
    def widen_to_subprojects
      return unless @query.available_filters.key?('subproject_id')

      @query.add_filter('subproject_id', '*', [''])
    end

    # Every status maps to exactly one column under the layout's placement
    # precedence (explicit mapping > Done > Unclassified); invert that so each
    # column knows the status ids it owns.
    def status_ids_by_column(layout)
      IssueStatus.all.group_by { |status| layout.column_key_for(status) }
                 .transform_values { |statuses| statuses.map(&:id) }
    end

    # True card totals by status (R10-1): one COUNT over the query's scope
    # (visibility included, R7) plus the board conditions. Builds no rows.
    def status_counts
      @status_counts ||= @query.base_scope
                               .where(board_conditions)
                               .group("#{Issue.table_name}.status_id")
                               .count
    end

    # One column's drawn cards: a LIMITed fetch through IssueQuery#issues so
    # visibility, preloads and the query's own sort (R9) all apply for free.
    # The board's default query gets the R9 fallback order instead.
    def fetch_cards(status_ids, limit, total)
      return [] if status_ids.empty? || limit.zero? || total.zero?

      @query.issues(
        conditions: board_conditions(status_ids),
        limit: limit,
        order: (@query_sorted ? nil : FALLBACK_ORDER)
      )
    end

    # The SQL conditions shared by the counts and fetch phases: leaf-ness via
    # the nested set (ADR-0002: full-tree, filter-independent), the optional
    # parent scope (R3: strict descendant by root_id + lft/rgt bounds), the
    # own-project range when subprojects are off, and a column's statuses.
    def board_conditions(status_ids = nil)
      issues = Issue.table_name
      conditions = ["#{issues}.rgt = #{issues}.lft + 1"]
      unless @include_subprojects
        conditions << Issue.sanitize_sql(["#{issues}.project_id = ?", @project.id])
      end
      if @scope_issue
        conditions << Issue.sanitize_sql(
          ["#{issues}.root_id = ? AND #{issues}.lft > ? AND #{issues}.rgt < ?",
           @scope_issue.root_id, @scope_issue.lft, @scope_issue.rgt]
        )
      end
      if status_ids
        conditions << Issue.sanitize_sql(["#{issues}.status_id IN (?)", status_ids])
      end
      conditions.join(' AND ')
    end

    # Default board query: no status restriction (open AND closed), overriding
    # Redmine's usual open-only default so the Done column can fill (ADR-0005).
    # IssueQuery#initialize seeds a default "status = open" filter, so we clear
    # all filters to surface every status.
    def default_query
      query = IssueQuery.new(name: '_', project: @project)
      query.filters = {}
      query
    end
  end
end
