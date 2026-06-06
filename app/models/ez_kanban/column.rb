# frozen_string_literal: true

module EzKanban
  # A single board column: an immutable bundle of a heading and the Cards
  # placed under it. Built by Board#columns from a Layout definition; never
  # mutated after construction (cards are grouped, then handed in whole).
  class Column
    attr_reader :key, :name, :cards

    def initialize(key:, name:, cards:, is_done: false, wip_limit: nil)
      @key = key
      @name = name
      @cards = cards
      @is_done = is_done
      @wip_limit = wip_limit
    end

    attr_reader :wip_limit

    def is_done?
      @is_done
    end

    # Exact card total for this column (R10-1). With no render cap yet
    # (issue 0007), every matching card is present, so size is the true count.
    def wip_count
      @cards.size
    end

    # Whether this column is over its WIP threshold (R10-2). Purely
    # informational: a true result never changes placement or visibility
    # (R10-4). A column with no threshold is never over WIP.
    def over_wip?
      !@wip_limit.nil? && wip_count > @wip_limit
    end
  end
end
