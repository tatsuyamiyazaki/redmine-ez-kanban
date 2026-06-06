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

    # The effective query driving the board, exposed so the filter UI (issue
    # 0006) can render the current filters and selected saved query.
    attr_reader :query

    def initialize(project, query: nil)
      @project = project
      # A caller-supplied query carries its own sort (R9); the board's own
      # default query is treated as unsorted so the R9 fallback order applies.
      # (The default query still has IssueQuery's built-in sort, which is not
      # the board's intended in-column order, so we must not follow it.)
      @query_sorted = !query.nil?
      @query = query || default_query
    end

    # Visible leaf issues matching the query, as a flat list.
    def cards
      # IssueQuery#issues already restricts to issues visible to User.current.
      @query.issues.select(&:leaf?)
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
      layout.definitions.map do |definition|
        Column.new(key: definition.key, name: definition.name,
                   is_done: definition.is_done, wip_limit: definition.wip_limit,
                   cards: sort_within_column(grouped.fetch(definition.key, [])))
      end
    end

    private

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
