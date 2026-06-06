# frozen_string_literal: true

# Read-only Kanban board for a single project.
# Access is gated by Redmine: the ez_kanban module must be enabled on the
# project and the user must hold :view_ez_kanban (enforced by #authorize).
class KanbanController < ApplicationController
  menu_item :ez_kanban

  # retrieve_query / query helpers reuse Redmine's standard query machinery (R7).
  include QueriesHelper
  # Expose query/filter view helpers so the embedded filter partial renders.
  helper :queries

  before_action :find_project_by_project_id
  before_action :authorize

  def show
    # Subproject inclusion is a board range control, off by default; its state
    # rides in the URL so reload/share restore it (R-0007, scope A).
    @include_subprojects = params[:subprojects] == '1'
    # Optional parent scope (R3): restrict the board to a parent's descendant
    # leaves. Resolved through Issue.visible so an unreadable/absent id simply
    # yields no scope (never leaking existence). Its id rides in the URL so
    # reload/share restore it.
    @scope_issue = find_scope_issue
    board = EzKanban::Board.new(@project, query: board_query,
                                          include_subprojects: @include_subprojects,
                                          scope_issue: @scope_issue)
    # The effective query (an explicit/saved one, or the unrestricted default)
    # drives the filter UI so it reflects the current board state (R7).
    @query = board.query
    @columns = board.columns
    # Render cap state for the over-capacity banner (R-0007).
    @over_cap = board.over_cap?
    @render_cap = board.render_cap
    # WIP threshold highlight is opt-in and global (R10-3); off by default.
    @highlight_wip = board.highlight_wip?
    # Ancestor paths for every card, resolved in one query (R2, no N+1).
    @ancestry = EzKanban::Ancestry.for(@columns.flat_map(&:cards))
    # Freshness (issue 0009): an XHR asks only for the board fragment so the
    # client can swap it in place, keeping the page (and scroll) and all current
    # filter/scope/subproject/cap state carried in the URL. Read-only — a plain
    # GET that renders, never writes (R5).
    render partial: 'board', layout: false if request.xhr?
  end

  private

  # The IssueQuery driving the board (R7). When the user picks a saved query
  # (query_id) or applies an ad-hoc filter (set_filter), reuse Redmine's
  # standard retrieval so saved queries, custom fields, visibility and sort all
  # apply for free. Otherwise return nil so the Board uses its own default,
  # status-unrestricted query (ADR-0005).
  def board_query
    return unless params[:query_id].present? || params[:set_filter].present?

    retrieve_query(IssueQuery)
  end

  # The scope parent (R3), or nil. Looked up through Issue.visible so the scope
  # honors Redmine's visibility rules and an absent/forbidden id falls back to
  # the unscoped board rather than erroring.
  def find_scope_issue
    return if params[:scope_issue_id].blank?

    Issue.visible.find_by(id: params[:scope_issue_id])
  end
end
