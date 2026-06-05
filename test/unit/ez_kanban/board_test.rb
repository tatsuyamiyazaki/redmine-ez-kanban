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

    private

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
