# frozen_string_literal: true

require_relative '../test_helper'

# Access-control behavior of the read-only Kanban board.
# The board is reachable only when the project has the ez_kanban module
# enabled AND the user holds :view_ez_kanban.
class KanbanControllerTest < Redmine::ControllerTest
  fixtures :projects, :users, :email_addresses, :roles,
           :members, :member_roles, :enabled_modules

  def setup
    @project = Project.find(1)
    enable_ez_kanban(@project)
    # jsmith (id 2) is a member of project 1 with role 1.
    @request.session[:user_id] = 2
  end

  def test_show_renders_for_permitted_user
    Role.find(1).add_permission!(:view_ez_kanban)

    get :show, params: { project_id: @project.id }

    assert_response :success
  end

  def test_show_is_forbidden_without_permission
    # Role 1 does not hold :view_ez_kanban in this test.
    get :show, params: { project_id: @project.id }

    assert_response :forbidden
  end

  def test_show_is_forbidden_when_module_disabled
    Role.find(1).add_permission!(:view_ez_kanban)
    @project.enabled_modules.where(name: 'ez_kanban').destroy_all

    get :show, params: { project_id: @project.id }

    assert_response :forbidden
  end

  def test_show_renders_a_card_for_each_leaf_with_fields
    Role.find(1).add_permission!(:view_ez_kanban)
    leaf = Issue.create!(
      project: @project, tracker: Tracker.find(2), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Card under test', assigned_to: User.find(2),
      due_date: Date.new(2026, 7, 1)
    )

    get :show, params: { project_id: @project.id }

    assert_response :success
    assert_select ".ez-kanban-card[data-issue-id=?]", leaf.id.to_s do
      assert_select '.ez-kanban-card__subject', text: /Card under test/
      assert_select '.ez-kanban-card__tracker', text: leaf.tracker.name
      assert_select '.ez-kanban-card__priority', text: leaf.priority.name
      assert_select '.ez-kanban-card__due'
      assert_select '.ez-kanban-card__assignee'
    end
  end

  def test_show_renders_status_columns_with_heading_count_and_card
    Role.find(1).add_permission!(:view_ez_kanban)
    leaf = Issue.create!(
      project: @project, tracker: Tracker.find(2), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Columned card'
    )

    get :show, params: { project_id: @project.id }

    assert_response :success
    assert_select '.ez-kanban-column[data-column-key=?]', 'status_1' do
      assert_select '.ez-kanban-column__title', text: /#{IssueStatus.find(1).name}/
      assert_select '.ez-kanban-column__count'
      assert_select ".ez-kanban-card[data-issue-id=?]", leaf.id.to_s
    end
  end

  private

  def enable_ez_kanban(project)
    return if project.module_enabled?(:ez_kanban)

    EnabledModule.create!(project: project, name: 'ez_kanban')
  end
end
