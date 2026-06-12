# frozen_string_literal: true

require_relative '../../test_helper'

module EzKanban
  # ColumnConfig is the pure engine behind the admin column editor (issue 0005):
  # it normalizes raw posted form data into the clean, storable column array the
  # Layout consumes, and validates it for user-facing warnings. It never raises:
  # bad input is sanitized so the 0003 placement fallback stays safe.
  class ColumnConfigTest < ActiveSupport::TestCase
    # A row with no name carries no column; drop it so empty editor rows vanish.
    def test_normalize_drops_rows_with_blank_name
      raw = [
        { 'key' => 'todo', 'name' => 'To Do', 'status_ids' => ['1'] },
        { 'key' => 'blank', 'name' => '', 'status_ids' => ['2'] }
      ]

      result = ColumnConfig.normalize(raw)

      assert_equal ['todo'], result.map { |spec| spec[:key] }
    end

    # The Unclassified column is implicit and always trailing (ADR-0004); an
    # admin can't define it, so a row reusing its key is dropped.
    def test_normalize_drops_unclassified_row
      raw = [
        { 'key' => 'todo', 'name' => 'To Do' },
        { 'key' => Layout::UNCLASSIFIED_KEY, 'name' => 'My Unclassified' }
      ]

      result = ColumnConfig.normalize(raw)

      assert_equal ['todo'], result.map { |spec| spec[:key] }
    end

    # Status checkboxes post an array of id strings; store them as ints. A row
    # with none selected gets an empty list (no statuses mapped).
    def test_normalize_coerces_status_ids_to_integers
      raw = [
        { 'key' => 'wip', 'name' => 'WIP', 'status_ids' => %w[2 4] },
        { 'key' => 'todo', 'name' => 'To Do' }
      ]

      result = ColumnConfig.normalize(raw)

      assert_equal [2, 4], result.first[:status_ids]
      assert_equal [], result.last[:status_ids]
    end

    # Keys are machine identifiers (DOM data attributes, grouping keys). The
    # editor only generates [a-z0-9_] keys, so anything else in a posted key is
    # stripped on normalize — hostile or corrupted input degrades to a plain
    # token instead of riding into markup.
    def test_normalize_strips_unsafe_characters_from_key
      raw = [
        { 'key' => 'todo', 'name' => 'To Do' },
        { 'key' => '<script>alert(1)</script>col_1', 'name' => 'Messy' }
      ]

      result = ColumnConfig.normalize(raw)

      assert_equal %w[todo scriptalert1scriptcol_1],
                   result.map { |spec| spec[:key] }
    end

    # A WIP threshold is an optional positive integer; a blank field means "no
    # threshold" and stores nil so the column is never highlighted (R10-2).
    def test_normalize_coerces_wip_limit_with_blank_as_nil
      raw = [
        { 'key' => 'wip', 'name' => 'WIP', 'wip_limit' => '5' },
        { 'key' => 'todo', 'name' => 'To Do', 'wip_limit' => '' }
      ]

      result = ColumnConfig.normalize(raw)

      assert_equal 5, result.first[:wip_limit]
      assert_nil result.last[:wip_limit]
    end

    # A negative threshold is meaningless (it would mark the column over-WIP
    # forever, even when empty); it normalizes to "no threshold". Zero stays a
    # valid threshold ("nothing belongs here"), matching the editor's min of 0.
    def test_normalize_treats_negative_wip_limit_as_none
      raw = [
        { 'key' => 'neg', 'name' => 'Negative', 'wip_limit' => '-1' },
        { 'key' => 'zero', 'name' => 'Zero', 'wip_limit' => '0' }
      ]

      result = ColumnConfig.normalize(raw)

      assert_nil result.first[:wip_limit]
      assert_equal 0, result.last[:wip_limit]
    end

    # Exactly one column may be the is_done column (ADR-0004). If a stray form
    # marks several, only the first wins; the rest are cleared so placement
    # stays deterministic.
    def test_normalize_forces_single_is_done_first_wins
      raw = [
        { 'key' => 'todo', 'name' => 'To Do', 'is_done' => '0' },
        { 'key' => 'review', 'name' => 'Review', 'is_done' => '1' },
        { 'key' => 'done', 'name' => 'Done', 'is_done' => '1' }
      ]

      result = ColumnConfig.normalize(raw)

      assert_equal [false, true, false], result.map { |spec| spec[:is_done] }
    end

    # Only one is_done column is meaningful (ADR-0004). Marking several is a
    # user mistake worth surfacing, even though normalize silently keeps the
    # first. validate returns i18n keys for the settings page to show.
    def test_validate_warns_on_multiple_is_done
      raw = [
        { 'key' => 'review', 'name' => 'Review', 'is_done' => '1' },
        { 'key' => 'done', 'name' => 'Done', 'is_done' => '1' }
      ]

      assert_includes ColumnConfig.validate(raw),
                      :error_ez_kanban_multiple_is_done
    end

    # A single is_done column is valid and raises no such warning.
    def test_validate_allows_single_is_done
      raw = [
        { 'key' => 'todo', 'name' => 'To Do' },
        { 'key' => 'done', 'name' => 'Done', 'is_done' => '1' }
      ]

      assert_not_includes ColumnConfig.validate(raw),
                          :error_ez_kanban_multiple_is_done
    end

    # A row with mappings or a threshold but no name is silently dropped by
    # normalize; warn so the admin notices their input was ignored.
    def test_validate_warns_on_nameless_row_with_data
      raw = [
        { 'key' => 'todo', 'name' => 'To Do' },
        { 'key' => 'oops', 'name' => '', 'status_ids' => %w[2] }
      ]

      assert_includes ColumnConfig.validate(raw),
                      :error_ez_kanban_nameless_column
    end

    # A fully empty trailing row (the editor's blank "add" row) is not a
    # mistake and must not warn.
    def test_validate_ignores_fully_empty_row
      raw = [
        { 'key' => 'todo', 'name' => 'To Do' },
        { 'key' => '', 'name' => '', 'status_ids' => [] }
      ]

      assert_empty ColumnConfig.validate(raw)
    end
  end
end
