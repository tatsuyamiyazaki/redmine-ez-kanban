# frozen_string_literal: true

require_relative '../../test_helper'

module EzKanban
  # Card-set rule (ADR-0002): a Card is a leaf in the full issue tree that
  # also matches the active query and is visible to the current user.
  class BoardTest < ActiveSupport::TestCase
    fixtures :projects, :users, :email_addresses, :roles, :members,
             :member_roles, :enabled_modules, :issue_statuses, :trackers,
             :enumerations, :issues, :issue_categories, :versions

    def setup
      @project = Project.find(1)
      User.current = User.find(1) # admin sees everything
    end

    def test_visible_leaf_appears_as_card
      leaf = create_issue(subject: 'Lonely leaf')

      cards = Board.new(@project).cards

      assert_includes cards, leaf
    end

    # A (Req 1): a parent (has children) is never a Card; its child leaf is.
    def test_parent_with_children_is_not_a_card
      parent = create_issue(subject: 'Parent')
      child = create_issue(subject: 'Child', parent_issue_id: parent.id)
      parent.reload

      cards = Board.new(@project).cards

      refute_includes cards, parent
      assert_includes cards, child
    end

    # B (ADR-0002): a leaf is a Card even when its parent is filtered out,
    # because leaf-ness is a global tree property, not relative to the filter.
    def test_leaf_is_card_even_when_parent_filtered_out
      parent = create_issue(subject: 'Parent DROP')
      child  = create_issue(subject: 'Child KEEP', parent_issue_id: parent.id)

      cards = Board.new(@project, query: query_with_subject('KEEP')).cards

      assert_includes cards, child
      refute_includes cards, parent
    end

    # C: a leaf that does not match the filter is excluded.
    def test_leaf_not_matching_filter_is_excluded
      match   = create_issue(subject: 'Alpha KEEP')
      nomatch = create_issue(subject: 'Beta other')

      cards = Board.new(@project, query: query_with_subject('KEEP')).cards

      assert_includes cards, match
      refute_includes cards, nomatch
    end

    # ADR-0005: closed leaves appear under the default (all-status) query.
    def test_closed_leaf_is_included_by_default
      closed = IssueStatus.where(is_closed: true).first
      leaf = create_issue(subject: 'Done leaf', status: closed)

      cards = Board.new(@project).cards

      assert_includes cards, leaf
    end

    # Visibility is enforced: issues the current user cannot see are not Cards.
    def test_issue_not_visible_to_user_is_excluded
      User.current = User.find(2) # jsmith
      # 'default' visibility hides other people's private issues (Redmine
      # controls private-issue visibility via Role#issues_visibility).
      User.current.roles_for_project(@project).each do |role|
        role.update!(issues_visibility: 'default')
      end
      hidden  = create_issue(subject: 'Secret', is_private: true,
                             author: User.find(1))
      visible = create_issue(subject: 'Public leaf')

      cards = Board.new(@project).cards

      refute_includes cards, hidden
      assert_includes cards, visible
    end

    # R4: a leaf that gains a child drops off the board (recomputed each time).
    def test_leaf_drops_off_when_it_gains_a_child
      was_leaf = create_issue(subject: 'Will become parent')
      assert_includes Board.new(@project).cards, was_leaf

      create_issue(subject: 'New child', parent_issue_id: was_leaf.id)
      was_leaf.reload

      refute_includes Board.new(@project).cards, was_leaf
    end

    # --- #columns (issue 0003): cards grouped into status columns ---

    # Tracer bullet: a leaf lands in the default column for its own status.
    def test_card_lands_in_its_status_column
      leaf = create_issue(subject: 'New leaf', status: IssueStatus.find(1))

      columns = Board.new(@project).columns

      col = columns.find { |c| c.cards.include?(leaf) }
      assert_equal IssueStatus.find(1).name, col.name
    end

    # Default config: an is_closed status with no explicit mapping falls into
    # the single trailing Done column (precedence step 2).
    def test_closed_card_lands_in_done_column
      closed = IssueStatus.where(is_closed: true).first
      leaf = create_issue(subject: 'Done leaf', status: closed)

      columns = Board.new(@project).columns

      col = columns.find { |c| c.cards.include?(leaf) }
      assert col, 'closed card was dropped from every column'
      assert col.is_done?, 'closed card should land in the Done column'
    end

    # The admin-configured layout in Setting overrides the built-in default.
    def test_uses_admin_configured_columns_from_setting
      with_plugin_columns([
                            { 'key' => 'backlog', 'name' => 'Backlog',
                              'status_ids' => [1, 2] }
                          ]) do
        leaf = create_issue(subject: 'Backlog leaf', status: IssueStatus.find(2))

        columns = Board.new(@project).columns

        col = columns.find { |c| c.cards.include?(leaf) }
        assert_equal 'Backlog', col.name
      end
    end

    # Each column reports its exact card total (R10-1): with no render cap yet,
    # that is simply the number of cards placed in it.
    def test_column_wip_count_equals_its_card_total
      base = column(Board.new(@project).columns, 'status_1').wip_count
      2.times { |i| create_issue(subject: "wip#{i}", status: IssueStatus.find(1)) }

      col = column(Board.new(@project).columns, 'status_1')

      assert_equal col.cards.size, col.wip_count
      assert_equal base + 2, col.wip_count
    end

    # R9 default order within a column: priority descending, then due ascending.
    def test_default_in_column_sort_is_priority_desc_then_due_asc
      high = IssuePriority.active.order(:position).last
      low  = IssuePriority.active.order(:position).first
      later  = create_issue(subject: 'A', status: IssueStatus.find(4),
                            priority: high, due_date: Date.new(2026, 7, 10))
      sooner = create_issue(subject: 'B', status: IssueStatus.find(4),
                            priority: high, due_date: Date.new(2026, 7, 1))
      low_pri = create_issue(subject: 'C', status: IssueStatus.find(4),
                             priority: low, due_date: Date.new(2026, 1, 1))

      col = column(Board.new(@project).columns, 'status_4')

      ordered = col.cards.select { |i| [later, sooner, low_pri].include?(i) }
      assert_equal [sooner, later, low_pri], ordered
    end

    # R9: an explicit query sort overrides the default in-column order.
    def test_in_column_order_follows_query_sort
      query = IssueQuery.new(name: '_', project: @project)
      query.filters = {}
      query.sort_criteria = [['subject', 'asc']]
      zzz = create_issue(subject: 'ZZZ sort', status: IssueStatus.find(4))
      aaa = create_issue(subject: 'AAA sort', status: IssueStatus.find(4))

      col = column(Board.new(@project, query: query).columns, 'status_4')

      ordered = col.cards.select { |i| [zzz, aaa].include?(i) }
      assert_equal [aaa, zzz], ordered
    end

    # --- render cap (issue 0007): cap the rendered cards, keep true counts ---

    # Tracer: a low global cap truncates the rendered cards, but each column
    # still reports its true total (so WIP/over-WIP detection stays correct).
    def test_render_cap_truncates_rendered_cards_keeping_true_counts
      with_plugin_columns_and_cap(cap: 2) do
        5.times { |i| create_issue(subject: "Cap #{i}", status: IssueStatus.find(1)) }
        board = Board.new(@project)

        cols = board.columns
        rendered = cols.sum { |c| c.cards.size }
        counted  = cols.sum(&:wip_count)

        assert_operator rendered, :<=, 2, 'rendered cards must not exceed the cap'
        assert_operator counted, :>=, 5, 'wip_count must reflect the true total'
        assert board.over_cap?, 'over_cap? must be true when total exceeds the cap'
      end
    end

    # --- subproject scope (issue 0007): default off, opt-in include ---

    # Default off: a subproject leaf is excluded. Opt-in include: it appears.
    def test_subproject_leaf_excluded_by_default_included_on_request
      sub = @project.children.where(is_public: true, status: Project::STATUS_ACTIVE).first
      assert sub, 'fixtures must give project 1 a public active subproject'
      leaf = Issue.create!(
        project: sub, tracker: Tracker.find(1), author: User.find(1),
        status: IssueStatus.find(1), priority: IssuePriority.first,
        subject: 'Subproject leaf'
      )

      refute_includes Board.new(@project).cards, leaf
      assert_includes Board.new(@project, include_subprojects: true).cards, leaf
    end

    private

    def with_plugin_columns_and_cap(cap:)
      previous = Setting.plugin_redmine_ez_kanban
      Setting.plugin_redmine_ez_kanban = previous.merge('render_cap' => cap)
      yield
    ensure
      Setting.plugin_redmine_ez_kanban = previous
    end

    def column(columns, key)
      columns.find { |c| c.key == key }
    end

    def with_plugin_columns(columns)
      previous = Setting.plugin_redmine_ez_kanban
      Setting.plugin_redmine_ez_kanban = { 'columns' => columns }
      yield
    ensure
      Setting.plugin_redmine_ez_kanban = previous
    end

    def query_with_subject(text)
      query = IssueQuery.new(name: '_', project: @project)
      query.add_filter('subject', '~', [text])
      query
    end

    def create_issue(attrs = {})
      Issue.create!({
        project: @project,
        tracker: Tracker.find(1),
        author: User.find(1),
        status: IssueStatus.find(1),
        priority: IssuePriority.first,
        subject: 'Test issue'
      }.merge(attrs))
    end
  end
end
