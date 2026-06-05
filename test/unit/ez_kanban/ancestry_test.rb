# frozen_string_literal: true

require_relative '../../test_helper'

module EzKanban
  # Ancestor-path computation for cards (R2): each leaf's root -> nearest-parent
  # chain, gathered for all cards in a constant number of queries (no N+1).
  class AncestryTest < ActiveSupport::TestCase
    fixtures :projects, :users, :email_addresses, :roles, :members,
             :member_roles, :enabled_modules, :issue_statuses, :trackers,
             :enumerations, :issues

    def setup
      @project = Project.find(1)
      User.current = User.find(1)
    end

    # Tracer bullet: a leaf's path is its ancestors ordered root -> nearest,
    # excluding the leaf itself.
    def test_path_is_root_to_nearest_parent
      root = create_issue(subject: 'Root')
      mid  = create_issue(subject: 'Mid', parent_issue_id: root.id)
      leaf = create_issue(subject: 'Leaf', parent_issue_id: mid.id)

      paths = Ancestry.for([leaf.reload])

      assert_equal [root.id, mid.id], paths[leaf.id].map(&:id)
    end

    # A standalone issue (no parent) has an empty path (R2-5).
    def test_standalone_issue_has_empty_path
      lonely = create_issue(subject: 'Lonely')

      paths = Ancestry.for([lonely.reload])

      assert_empty paths[lonely.id]
    end

    # Ancestors for the whole card set load in a single query regardless of how
    # many cards are passed (no N+1).
    def test_ancestors_load_in_a_single_query
      leaves = Array.new(3) do |i|
        root = create_issue(subject: "Root #{i}")
        create_issue(subject: "Leaf #{i}", parent_issue_id: root.id)
      end
      leaves.each(&:reload)

      queries = count_select_queries { Ancestry.for(leaves) }

      assert_equal 1, queries
    end

    private

    def count_select_queries
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        payload = args.last
        sql = payload[:sql]
        next if payload[:name] == 'SCHEMA'
        next unless sql =~ /\ASELECT/i

        count += 1
      end
      yield
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
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
