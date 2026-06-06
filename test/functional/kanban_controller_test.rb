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

  def test_card_shows_breadcrumb_for_leaf_with_parent
    Role.find(1).add_permission!(:view_ez_kanban)
    root = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Root project area'
    )
    leaf = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Child leaf', parent_issue_id: root.id
    )

    get :show, params: { project_id: @project.id }

    assert_response :success
    assert_select ".ez-kanban-card[data-issue-id=?]", leaf.id.to_s do
      assert_select '.ez-kanban-card__breadcrumb[title=?]', 'Root project area'
      assert_select '.ez-kanban-card__breadcrumb', text: /Root project area/
    end
  end

  def test_standalone_card_has_no_breadcrumb
    Role.find(1).add_permission!(:view_ez_kanban)
    leaf = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Lonely card'
    )

    get :show, params: { project_id: @project.id }

    assert_select ".ez-kanban-card[data-issue-id=?]", leaf.id.to_s do
      assert_select '.ez-kanban-card__breadcrumb', count: 0
    end
  end

  # WIP highlight is opt-in (R10-3): with the global toggle on, a column whose
  # count exceeds its threshold gets a highlight class. Threshold 0 + one card
  # is the smallest over-capacity case.
  def test_over_wip_column_is_highlighted_when_toggle_on
    Role.find(1).add_permission!(:view_ez_kanban)
    Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Over-cap card'
    )

    with_plugin_settings(
      'columns' => [{ 'key' => 'todo', 'name' => 'To Do',
                      'status_ids' => ['1'], 'wip_limit' => '0' }],
      'highlight_wip' => '1'
    ) do
      get :show, params: { project_id: @project.id }
    end

    assert_select '.ez-kanban-column[data-column-key=?].ez-kanban-column--over-wip',
                  'todo'
  end

  # R10-3: highlighting is off by default, so even an over-capacity column
  # carries no highlight class.
  def test_over_wip_column_not_highlighted_by_default
    Role.find(1).add_permission!(:view_ez_kanban)
    Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Over-cap card'
    )

    with_plugin_settings(
      'columns' => [{ 'key' => 'todo', 'name' => 'To Do',
                      'status_ids' => ['1'], 'wip_limit' => '0' }]
    ) do
      get :show, params: { project_id: @project.id }
    end

    assert_select '.ez-kanban-column--over-wip', count: 0
  end

  # R7: an ad-hoc filter (set_filter + f/op/v) restricts the board's cards to
  # those matching the IssueQuery. Filtering to status 1 drops the closed card.
  def test_filter_restricts_cards_to_matching_status
    Role.find(1).add_permission!(:view_ez_kanban)
    keep = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Filter keep'
    )
    drop = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(5), priority: IssuePriority.first,
      subject: 'Filter drop'
    )

    get :show, params: {
      project_id: @project.id, set_filter: '1',
      f: ['status_id'], op: { 'status_id' => '=' }, v: { 'status_id' => ['1'] }
    }

    assert_response :success
    assert_select ".ez-kanban-card[data-issue-id=?]", keep.id.to_s
    assert_select ".ez-kanban-card[data-issue-id=?]", drop.id.to_s, count: 0
  end

  # R7-2: choosing a saved query renders the board under that query's
  # conditions. The public query restricts to status 1, so the closed card drops.
  def test_saved_query_drives_the_board
    Role.find(1).add_permission!(:view_ez_kanban)
    query = IssueQuery.create!(
      name: 'Only new', project: @project, user: User.find(2),
      visibility: Query::VISIBILITY_PUBLIC,
      filters: { 'status_id' => { operator: '=', values: ['1'] } }
    )
    keep = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first, subject: 'Keep'
    )
    drop = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(5), priority: IssuePriority.first, subject: 'Drop'
    )

    get :show, params: { project_id: @project.id, query_id: query.id }

    assert_response :success
    assert_select ".ez-kanban-card[data-issue-id=?]", keep.id.to_s
    assert_select ".ez-kanban-card[data-issue-id=?]", drop.id.to_s, count: 0
  end

  # R7-3: custom-field conditions work because filtering rides on IssueQuery.
  def test_custom_field_filter_narrows_cards
    Role.find(1).add_permission!(:view_ez_kanban)
    field = IssueCustomField.create!(
      name: 'Team', field_format: 'string', is_filter: true,
      is_for_all: true, trackers: Tracker.all
    )
    keep = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Alpha', custom_field_values: { field.id => 'alpha' }
    )
    drop = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(1), priority: IssuePriority.first,
      subject: 'Beta', custom_field_values: { field.id => 'beta' }
    )

    get :show, params: {
      project_id: @project.id, set_filter: '1',
      f: ["cf_#{field.id}"], op: { "cf_#{field.id}" => '=' },
      v: { "cf_#{field.id}" => ['alpha'] }
    }

    assert_response :success
    assert_select ".ez-kanban-card[data-issue-id=?]", keep.id.to_s
    assert_select ".ez-kanban-card[data-issue-id=?]", drop.id.to_s, count: 0
  end

  # ADR-0005: with no query selected the board stays status-unrestricted, so a
  # closed-status leaf still appears (Redmine's open-only default is overridden).
  def test_default_view_shows_closed_status_cards
    Role.find(1).add_permission!(:view_ez_kanban)
    closed = Issue.create!(
      project: @project, tracker: Tracker.find(1), author: User.find(2),
      status: IssueStatus.find(5), priority: IssuePriority.first,
      subject: 'Closed leaf'
    )

    get :show, params: { project_id: @project.id }

    assert_response :success
    assert_select ".ez-kanban-card[data-issue-id=?]", closed.id.to_s
  end

  # R7-5: the board carries a GET filter form whose filters fieldset is
  # collapsed by default, plus a saved-query selector (R7-2).
  def test_filter_ui_is_present_and_collapsed_by_default
    Role.find(1).add_permission!(:view_ez_kanban)
    IssueQuery.create!(
      name: 'Saved one', project: @project, user: User.find(2),
      visibility: Query::VISIBILITY_PUBLIC,
      filters: { 'status_id' => { operator: '=', values: ['1'] } }
    )

    get :show, params: { project_id: @project.id }

    assert_response :success
    assert_select 'form#ez-kanban-query-form[method=?]', 'get'
    assert_select 'fieldset#filters.collapsible.collapsed'
    assert_select 'select#ez-kanban-query-id' do
      assert_select 'option', text: /Saved one/
    end
  end

  # The selected query round-trips through the URL: a shared/reloaded
  # ?query_id=… link shows that query as the active selection.
  def test_selected_query_is_reflected_in_selector
    Role.find(1).add_permission!(:view_ez_kanban)
    query = IssueQuery.create!(
      name: 'Pinned', project: @project, user: User.find(2),
      visibility: Query::VISIBILITY_PUBLIC,
      filters: { 'status_id' => { operator: '*', values: [''] } }
    )

    get :show, params: { project_id: @project.id, query_id: query.id }

    assert_response :success
    assert_select 'select#ez-kanban-query-id option[selected][value=?]',
                  query.id.to_s, text: /Pinned/
  end

  private

  def enable_ez_kanban(project)
    return if project.module_enabled?(:ez_kanban)

    EnabledModule.create!(project: project, name: 'ez_kanban')
  end
end
