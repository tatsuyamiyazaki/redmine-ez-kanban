# frozen_string_literal: true

module EzKanban
  # Computes each card's ancestor path (root -> nearest parent) for breadcrumbs
  # (R2). Ancestors for the whole card set are loaded in a single nested-set
  # query, so cost is constant in the number of cards (no N+1).
  class Ancestry
    # @param cards [Array<Issue>] the leaf issues to resolve paths for.
    # @return [Hash{Integer => Array<Issue>}] card id -> ancestors, root first,
    #   nearest parent last. A standalone issue maps to an empty array.
    def self.for(cards)
      new(cards).paths
    end

    def initialize(cards)
      @cards = cards
    end

    def paths
      return {} if @cards.empty?

      ancestors = load_ancestors
      @cards.each_with_object({}) do |card, map|
        map[card.id] = ancestors_of(card, ancestors)
      end
    end

    private

    def ancestors_of(card, ancestors)
      ancestors.select do |a|
        a.root_id == card.root_id && a.lft < card.lft && a.rgt > card.rgt
      end.sort_by(&:lft)
    end

    # One query for every card's ancestors via the nested set, built with Arel
    # so no SQL is ever assembled from strings.
    def load_ancestors
      issues = Issue.arel_table
      condition = @cards.map do |card|
        issues[:root_id].eq(card.root_id)
                        .and(issues[:lft].lt(card.lft))
                        .and(issues[:rgt].gt(card.rgt))
      end.reduce(:or)
      Issue.where(condition).to_a
    end
  end
end
