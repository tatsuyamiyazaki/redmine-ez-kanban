# frozen_string_literal: true

require_relative '../../test_helper'

module EzKanban
  # A board Column bundles a heading with its cards and reports WIP (issue 0003,
  # extended in 0005 with an optional threshold). over_wip? is purely
  # informational (R10-4): it never affects placement or visibility.
  class ColumnTest < ActiveSupport::TestCase
    # With a threshold set, a column whose count exceeds it is over WIP (R10-2).
    def test_over_wip_when_count_exceeds_limit
      column = Column.new(key: 'wip', name: 'WIP', cards: [1, 2, 3], wip_limit: 2)

      assert_predicate column, :over_wip?
    end

    # At or below the threshold is not over WIP.
    def test_not_over_wip_at_or_below_limit
      column = Column.new(key: 'wip', name: 'WIP', cards: [1, 2], wip_limit: 2)

      assert_not column.over_wip?
    end

    # No threshold means a column can never be flagged (R10-2 is conditional).
    def test_never_over_wip_without_limit
      column = Column.new(key: 'wip', name: 'WIP', cards: [1, 2, 3], wip_limit: nil)

      assert_not column.over_wip?
    end
  end
end
