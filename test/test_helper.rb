# frozen_string_literal: true

# Load the host Redmine's test helper so plugin tests run inside the full
# Redmine test environment (fixtures, Redmine::ControllerTest, etc.).
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

module EzKanban
  # Shared helpers for this plugin's tests.
  module TestHelpers
    # Run the block with the plugin's Setting temporarily replaced, restoring it
    # afterward so tests stay isolated.
    def with_plugin_settings(overrides)
      original = Setting.plugin_redmine_ez_kanban
      Setting.plugin_redmine_ez_kanban = original.merge(overrides)
      yield
    ensure
      Setting.plugin_redmine_ez_kanban = original
    end
  end
end

ActiveSupport::TestCase.include EzKanban::TestHelpers
