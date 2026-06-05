# frozen_string_literal: true

# Read-only Kanban board for a single project.
# Access is gated by Redmine: the ez_kanban module must be enabled on the
# project and the user must hold :view_ez_kanban (enforced by #authorize).
class KanbanController < ApplicationController
  menu_item :ez_kanban

  before_action :find_project_by_project_id
  before_action :authorize

  def show
    @columns = EzKanban::Board.new(@project).columns
    # Ancestor paths for every card, resolved in one query (R2, no N+1).
    @ancestry = EzKanban::Ancestry.for(@columns.flat_map(&:cards))
  end
end
