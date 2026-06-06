# frozen_string_literal: true

module EzKanban
  # Decides the set of Cards for a project's board.
  #
  # A Card is an issue that is a leaf in the FULL issue tree (no children,
  # independent of any filter), matches the active query, and is visible to
  # the current user (ADR-0002). Leaf-ness is computed over the whole tree via
  # the nested set, so a filtered-in parent is never a Card and a filtered-in
  # leaf whose parent is filtered out still is.
  class Board
    # Sentinel so cards without a due date sort after those that have one.
    FAR_FUTURE = Date.new(9999, 12, 31)

    # Global render cap (R-0007): how many cards the board will draw at most,
    # protecting the server/DOM on large projects. Admin-adjustable via Setting.
    DEFAULT_RENDER_CAP = 500

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
      # (The default query still has IssueQuery's built-in sort, which is not
      # the board's intended in-column order, so we must not follow it.)
      @query_sorted = !query.nil?
      @query = query || default_query
    end

    # Visible leaf issues matching the query, as a flat list. Memoized so the
    # query runs once per board (columns and over_cap? both read it).
    def cards
      # IssueQuery#issues already restricts to issues visible to User.current.
      @cards ||= begin
        leaves = scoped_issues.select(&:leaf?)
        # Parent scope (R3) intersects the filtered leaves with the chosen
        # parent's subtree; off, the board stays flat over every leaf.
        @scope_issue ? leaves.select { |leaf| within_scope?(leaf) } : leaves
      end
    end

    # The cap on how many cards the board renders (R-0007). Admin-set via
    # Setting; non-positive or missing values fall back to the default.
    def render_cap
      configured = Setting.plugin_redmine_ez_kanban['render_cap'].to_i
      configured.positive? ? configured : DEFAULT_RENDER_CAP
    end

    # Whether the matching card total exceeds the render cap, so the board
    # truncated what it drew and should warn the user (R-0007 banner).
    def over_cap?
      cards.size > render_cap
    end

    # Whether WIP threshold highlighting is enabled (R10-3, opt-in). A global
    # setting shared across all projects (R6-5); off by default.
    def highlight_wip?
      ColumnConfig.truthy?(Setting.plugin_redmine_ez_kanban['highlight_wip'])
    end

    # Cards grouped into the board's status columns (issue 0003).
    def columns
      layout = Layout.default
      grouped = cards.group_by { |card| layout.column_key_for(card.status) }
      # Global render budget (R-0007): drawn left to right, columns share one
      # cap with no per-column paging. wip_count keeps the true total so WIP and
      # over-WIP detection stay correct even when rendering is truncated.
      remaining = render_cap
      layout.definitions.map do |definition|
        all = sort_within_column(grouped.fetch(definition.key, []))
        drawn = all.first([remaining, 0].max)
        remaining -= drawn.size
        Column.new(key: definition.key, name: definition.name,
                   is_done: definition.is_done, wip_limit: definition.wip_limit,
                   cards: drawn, wip_count: all.size)
      end
    end

    private

    # Issues for the board's range (R-0007, scope A). Off by default, restrict
    # to this project alone via an extra condition, so the result never depends
    # on the global "display subprojects" setting. On, widen the query to the
    # whole subtree via the standard subproject filter (only when the project
    # actually has subprojects to include).
    def scoped_issues
      if @include_subprojects
        if @query.available_filters.key?('subproject_id')
          @query.add_filter('subproject_id', '*', [''])
        end
        @query.issues
      else
        @query.issues(conditions: { "#{Issue.table_name}.project_id" => @project.id })
      end
    end

    # Whether an issue is a strict descendant of the scope parent via the
    # nested set: same tree (root_id) and inside the parent's lft..rgt bounds
    # (R3-2, depth-agnostic). The strict comparison excludes the parent itself,
    # which is never a leaf and so never a card anyway.
    def within_scope?(issue)
      issue.root_id == @scope_issue.root_id &&
        issue.lft > @scope_issue.lft &&
        issue.rgt < @scope_issue.rgt
    end

    # In-column order (R9): follow the query's sort when one was supplied;
    # otherwise fall back to priority descending, then due date ascending.
    def sort_within_column(cards)
      return cards if @query_sorted

      cards.sort_by { |card| [-card.priority.position, card.due_date || FAR_FUTURE] }
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
