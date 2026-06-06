# frozen_string_literal: true

require_relative '../test_helper'

# The admin column editor (issue 0005) is rendered as the plugin's settings
# partial on Administration -> Plugins -> Configure. These tests exercise it
# through Redmine's SettingsController so the real render path is covered.
class SettingsPartialTest < Redmine::ControllerTest
  tests SettingsController
  fixtures :projects, :users, :email_addresses, :roles, :issue_statuses

  def setup
    @request.session[:user_id] = 1 # admin
  end

  # The editor renders one row per configured column, with name, status,
  # is_done and WIP threshold inputs, plus the global highlight toggle.
  def test_plugin_settings_renders_column_editor
    with_plugin_settings(
      'columns' => [{ 'key' => 'todo', 'name' => 'To Do',
                      'status_ids' => ['1'], 'is_done' => false,
                      'wip_limit' => 5 }]
    ) do
      get :plugin, params: { id: 'redmine_ez_kanban' }
    end

    assert_response :success
    assert_select 'table.ez-kanban-settings-columns tbody tr.ez-kanban-settings-row' do
      assert_select 'input.ez-kanban-settings-name[value=?]', 'To Do'
      assert_select 'input[type=checkbox].ez-kanban-settings-status[value=?]', '1'
      assert_select 'input[type=radio].ez-kanban-settings-done'
      assert_select 'input.ez-kanban-settings-wip[value=?]', '5'
    end
    assert_select 'input[type=checkbox][name=?]', 'settings[highlight_wip]'
  end

  # The implicit Unclassified column is not editable (ADR-0004): no editor row
  # offers it.
  def test_editor_has_no_unclassified_row
    with_plugin_settings(
      'columns' => [{ 'key' => 'todo', 'name' => 'To Do', 'status_ids' => ['1'] }]
    ) do
      get :plugin, params: { id: 'redmine_ez_kanban' }
    end

    assert_select "input.ez-kanban-settings-name[value=?]",
                  I18n.t(:label_ez_kanban_column_unclassified), count: 0
  end
end
