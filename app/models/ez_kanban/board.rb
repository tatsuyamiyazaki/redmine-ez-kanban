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
    def initialize(project, query: nil)
      @project = project
      @query = query || default_query
    end

    # Visible leaf issues matching the query, as a flat list.
    def cards
      # IssueQuery#issues already restricts to issues visible to User.current.
      @query.issues.select(&:leaf?)
    end

    private

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
