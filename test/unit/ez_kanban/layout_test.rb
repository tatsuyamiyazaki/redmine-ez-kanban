# frozen_string_literal: true

require_relative '../../test_helper'

module EzKanban
  # Column layout and placement precedence (ADR-0004):
  #   explicit status->column mapping > is_done column > trailing Unclassified.
  class LayoutTest < ActiveSupport::TestCase
    fixtures :issue_statuses

    # Explicit mapping: a status listed in a column's status_ids goes there.
    def test_explicit_mapping_places_status_in_its_column
      layout = Layout.new(columns: [
                            { key: 'todo', name: 'To Do', status_ids: [1] }
                          ])

      assert_equal 'todo', layout.column_key_for(IssueStatus.find(1))
    end

    # An unmapped non-closed status falls into the trailing Unclassified column.
    def test_unmapped_open_status_falls_to_unclassified
      layout = Layout.new(columns: [
                            { key: 'todo', name: 'To Do', status_ids: [1] }
                          ])

      assert_equal Layout::UNCLASSIFIED_KEY,
                   layout.column_key_for(IssueStatus.find(2))
    end

    # Precedence: an explicit mapping wins over the is_closed -> Done fallback,
    # so an admin can show a closed status in a non-Done column.
    def test_explicit_mapping_wins_over_done_fallback
      closed = IssueStatus.where(is_closed: true).first
      layout = Layout.new(columns: [
                            { key: 'review', name: 'Review',
                              status_ids: [closed.id] }
                          ])

      assert_equal 'review', layout.column_key_for(closed)
    end

    # An unmapped is_closed status still falls into the Done column.
    def test_unmapped_closed_status_falls_to_done
      closed = IssueStatus.where(is_closed: true).first
      layout = Layout.new(columns: [
                            { key: 'todo', name: 'To Do', status_ids: [1] },
                            { key: 'done', name: 'Done', status_ids: [],
                              is_done: true }
                          ])

      assert_equal 'done', layout.column_key_for(closed)
    end

    # Definitions always end with the implicit Unclassified column so every
    # card has a home (Req 6-4).
    def test_definitions_end_with_unclassified
      layout = Layout.new(columns: [
                            { key: 'todo', name: 'To Do', status_ids: [1] }
                          ])

      assert_equal Layout::UNCLASSIFIED_KEY, layout.definitions.last.key
    end

    # A configured WIP threshold rides along on the column definition so the
    # board can flag over-capacity columns (R10-2, issue 0005).
    def test_definition_carries_wip_limit
      layout = Layout.new(columns: [
                            { key: 'wip', name: 'WIP', status_ids: [1],
                              wip_limit: 3 }
                          ])

      assert_equal 3, layout.definitions.first.wip_limit
    end
  end
end
