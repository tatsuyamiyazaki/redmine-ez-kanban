# frozen_string_literal: true

module EzKanban
  # The board's column layout: an ordered set of column definitions plus the
  # rule that decides which column a status belongs to (ADR-0004).
  #
  # Placement precedence:
  #   1. explicit status->column mapping (status_id listed in a column)
  #   2. the is_done column, for unmapped is_closed statuses
  #   3. the implicit, always-present trailing Unclassified column
  #
  # With no admin config yet, the built-in default is used: one column per open
  # status in position order, then a single Done column. The Unclassified
  # column is always appended so every card has a home (Req 6-4).
  class Layout
    Definition = Struct.new(:key, :name, :status_ids, :is_done, keyword_init: true)

    DONE_KEY = 'done'
    UNCLASSIFIED_KEY = 'unclassified'

    # The active layout: the admin-configured columns from Setting, or the
    # built-in default when none are configured (ADR-0004).
    def self.default
      configured = Setting.plugin_redmine_ez_kanban['columns']
      configured.present? ? new(columns: configured) : new
    end

    # @param columns [Array<Hash>, nil] explicit column specs; nil uses the
    #   built-in default. Each spec: {key:, name:, status_ids:, is_done:}.
    def initialize(columns: nil)
      @specs = (columns || built_in_columns).map { |spec| normalize(spec) }
    end

    # Ordered column definitions, left to right, ending with Unclassified.
    def definitions
      @specs.map { |spec| Definition.new(**spec) } + [unclassified_definition]
    end

    # The column key a status maps to under this layout (precedence above).
    def column_key_for(status)
      explicit = @specs.find { |spec| spec[:status_ids].include?(status.id) }
      return explicit[:key] if explicit
      return done_key if status.is_closed? && done_key

      UNCLASSIFIED_KEY
    end

    private

    def done_key
      spec = @specs.find { |spec| spec[:is_done] }
      spec && spec[:key]
    end

    # Coerce symbol/string keys and serialized string ids into a stable shape.
    def normalize(spec)
      {
        key: spec[:key] || spec['key'],
        name: spec[:name] || spec['name'],
        status_ids: Array(spec[:status_ids] || spec['status_ids']).map(&:to_i),
        is_done: spec[:is_done] || spec['is_done'] || false
      }
    end

    def built_in_columns
      open_columns = IssueStatus.where(is_closed: false).order(:position).map do |status|
        { key: "status_#{status.id}", name: status.name,
          status_ids: [status.id], is_done: false }
      end
      open_columns + [{ key: DONE_KEY, name: I18n.t(:label_ez_kanban_column_done),
                        status_ids: [], is_done: true }]
    end

    def unclassified_definition
      Definition.new(key: UNCLASSIFIED_KEY,
                     name: I18n.t(:label_ez_kanban_column_unclassified),
                     status_ids: [], is_done: false)
    end
  end
end
