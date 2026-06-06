# frozen_string_literal: true

module EzKanban
  # Pure engine behind the admin column editor (issue 0005). Turns raw posted
  # form rows into the clean, storable column array the Layout consumes, and
  # validates them for user-facing warnings. Never raises: invalid input is
  # sanitized so the 0003 placement fallback stays safe (ADR-0004).
  module ColumnConfig
    module_function

    # Normalize raw posted rows into stored column specs. Drops rows that carry
    # no usable column (blank name).
    #
    # @param raw [Array<Hash>, Hash, nil] posted rows (array, or Rails
    #   hash-of-index when form indices are used).
    # @return [Array<Hash>] clean specs keyed by symbols.
    def normalize(raw)
      specs = rows(raw).filter_map do |row|
        key = row['key'].to_s
        name = row['name'].to_s.strip
        next if name.empty? || key == Layout::UNCLASSIFIED_KEY

        { key: key, name: name,
          status_ids: Array(row['status_ids']).map(&:to_i),
          is_done: truthy?(row['is_done']),
          wip_limit: wip_limit(row['wip_limit']) }
      end
      enforce_single_is_done(specs)
    end

    # A blank threshold means "none" (nil); otherwise an integer.
    def wip_limit(raw)
      value = raw.to_s.strip
      value.empty? ? nil : value.to_i
    end

    # Checkbox/radio submit '1'/'true'/'on' when set, '0'/'' otherwise.
    def truthy?(raw)
      %w[1 true on].include?(raw.to_s.strip.downcase)
    end

    # A row that carries mappings, a threshold, or the is_done flag but no name:
    # normalize drops it, so the admin's input would vanish silently.
    def nameless_with_data?(row)
      return false unless row['name'].to_s.strip.empty?

      Array(row['status_ids']).any? { |id| id.to_s.strip != '' } ||
        row['wip_limit'].to_s.strip != '' ||
        truthy?(row['is_done'])
    end

    # Keep only the first is_done column; clear the flag on the rest so a single
    # Done column governs the is_closed fallback (ADR-0004).
    def enforce_single_is_done(specs)
      seen = false
      specs.map do |spec|
        keep = spec[:is_done] && !seen
        seen ||= spec[:is_done]
        spec.merge(is_done: keep)
      end
    end

    # User-facing warnings about the raw submitted rows, as i18n keys for the
    # settings page. Advisory only: normalize still stores a safe config, so a
    # warning never blocks saving.
    def validate(raw)
      parsed = rows(raw)
      warnings = []
      done_count = parsed.count { |row| truthy?(row['is_done']) }
      warnings << :error_ez_kanban_multiple_is_done if done_count > 1
      warnings << :error_ez_kanban_nameless_column if parsed.any? { |row| nameless_with_data?(row) }
      warnings
    end

    # Coerce the raw columns collection into an ordered array of string-keyed
    # row hashes, tolerating both array and Rails hash-of-index shapes.
    def rows(raw)
      collection = raw.is_a?(Hash) ? raw.values : Array(raw)
      collection.map { |row| row.respond_to?(:to_h) ? row.to_h.stringify_keys : {} }
    end
  end
end
