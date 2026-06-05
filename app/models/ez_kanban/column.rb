# frozen_string_literal: true

module EzKanban
  # A single board column: an immutable bundle of a heading and the Cards
  # placed under it. Built by Board#columns from a Layout definition; never
  # mutated after construction (cards are grouped, then handed in whole).
  class Column
    attr_reader :key, :name, :cards

    def initialize(key:, name:, cards:, is_done: false)
      @key = key
      @name = name
      @cards = cards
      @is_done = is_done
    end

    def is_done?
      @is_done
    end

    # Exact card total for this column (R10-1). With no render cap yet
    # (issue 0007), every matching card is present, so size is the true count.
    def wip_count
      @cards.size
    end
  end
end
