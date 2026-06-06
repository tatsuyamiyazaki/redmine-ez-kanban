# frozen_string_literal: true

module EzKanban
  # A single board column: an immutable bundle of a heading and the Cards
  # placed under it. Built by Board#columns from a Layout definition; never
  # mutated after construction (cards are grouped, then handed in whole).
  class Column
    attr_reader :key, :name, :cards

    def initialize(key:, name:, cards:, is_done: false, wip_limit: nil,
                   wip_count: nil)
      @key = key
      @name = name
      @cards = cards
      @is_done = is_done
      @wip_limit = wip_limit
      # True card total for the column, which may exceed the rendered cards
      # when the board's render cap truncates drawing (R-0007). Falls back to
      # the rendered size when no separate total is given.
      @wip_count = wip_count || cards.size
    end

    attr_reader :wip_limit

    def is_done?
      @is_done
    end

    # Exact card total for this column (R10-1), independent of the render cap
    # (R-0007): equals every matching card, even when only some are drawn.
    def wip_count
      @wip_count
    end

    # Whether this column is over its WIP threshold (R10-2). Purely
    # informational: a true result never changes placement or visibility
    # (R10-4). A column with no threshold is never over WIP.
    def over_wip?
      !@wip_limit.nil? && wip_count > @wip_limit
    end
  end
end
