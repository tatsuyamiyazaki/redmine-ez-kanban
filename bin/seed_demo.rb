# frozen_string_literal: true

# Demo data seeder for the EZ Kanban board (development only).
#
# Run inside the Redmine container:
#   docker compose exec -u root -T redmine bash -lc '
#     cd /usr/src/redmine
#     export SECRET_KEY_BASE="$REDMINE_SECRET_KEY_BASE"
#     RAILS_ENV=production bundle exec rails runner \
#       plugins/redmine_ez_kanban/bin/seed_demo.rb'
#
# Idempotent: re-running updates/ensures the same fixtures rather than
# duplicating them. The dataset is shaped to exercise the board's defining
# behaviors:
#   - leaf-only cards (parents/sub-epics must NOT appear as cards)
#   - status-grouped columns incl. is_closed -> Done fallback
#   - multi-level hierarchy for breadcrumb truncation
#   - standalone leaves (no breadcrumb)
#   - assignee / priority / due date / tracker fields populated

DEMO_PROJECT_IDENTIFIER = 'ez-kanban-demo'

# --- Default configuration data (statuses, trackers, priorities, roles) ---
if Redmine::DefaultData::Loader.no_data?
  puts 'Loading Redmine default data (en)...'
  Redmine::DefaultData::Loader.load('en')
end

admin = User.find_by_login('admin') || User.where(admin: true).first
raise 'No admin user found' unless admin

# Lookups by name (default English data).
def status!(name)
  IssueStatus.find_by!(name: name)
end

def tracker!(name)
  Tracker.find_by!(name: name)
end

def priority!(name)
  IssuePriority.find_by!(name: name)
end

# --- Project ---
project = Project.find_by(identifier: DEMO_PROJECT_IDENTIFIER)
unless project
  project = Project.new(
    name: 'EZ Kanban Demo',
    identifier: DEMO_PROJECT_IDENTIFIER,
    description: 'Sample project for exercising the read-only Kanban board.',
    is_public: true
  )
  project.save!
end

# Enable issue tracking + the kanban board module.
project.enabled_module_names = (project.enabled_module_names | %w[issue_tracking ez_kanban])
# Associate all standard trackers so issues can use any of them.
project.trackers = Tracker.all
project.save!

# --- Permission: let Manager role view the board ---
manager = Role.find_by(name: 'Manager') || Role.givable.first
manager.add_permission!(:view_ez_kanban) if manager

# Add admin as a Manager member (so issues can be assigned to them).
unless project.members.any? { |m| m.user_id == admin.id }
  Member.create!(project: project, user: admin, roles: [manager].compact)
end

today = Date.current

# --- Issue helpers -------------------------------------------------------
# find_or_create by (project, subject) keeps the seed idempotent.
def upsert_issue(project, author, subject:, tracker:, status:, priority:,
                 assigned_to: nil, due_date: nil, parent: nil)
  issue = Issue.find_or_initialize_by(project_id: project.id, subject: subject)
  issue.author      ||= author
  issue.tracker       = tracker
  issue.status        = status
  issue.priority      = priority
  issue.assigned_to   = assigned_to
  issue.due_date      = due_date
  issue.description  ||= subject
  # Set hierarchy in the SAME save: a second save after a nested-set move
  # bumps lock_version via update_all and makes the in-memory object stale.
  issue.parent_issue_id = parent&.id
  issue.save!
  issue
end

bug     = tracker!('Bug')
feature = tracker!('Feature')
support = tracker!('Support')

s_new       = status!('New')
s_progress  = status!('In Progress')
s_resolved  = status!('Resolved')
s_feedback  = status!('Feedback')
s_closed    = status!('Closed')
s_rejected  = status!('Rejected')

p_low    = priority!('Low')
p_normal = priority!('Normal')
p_high   = priority!('High')
p_urgent = priority!('Urgent')

# --- Epic A (parent -> NOT a card) ---
epic_a = upsert_issue(project, admin,
  subject: '[Epic A] Onboarding flow', tracker: feature,
  status: s_progress, priority: p_high)
upsert_issue(project, admin, subject: 'A-1 Sign-up form', tracker: feature,
  status: s_new, priority: p_high, assigned_to: admin,
  due_date: today + 7, parent: epic_a)
upsert_issue(project, admin, subject: 'A-2 Email verification', tracker: feature,
  status: s_progress, priority: p_normal, due_date: today + 3, parent: epic_a)
upsert_issue(project, admin, subject: 'A-3 Welcome tour', tracker: feature,
  status: s_resolved, priority: p_low, parent: epic_a)

# --- Epic B with a nested sub-epic (3 levels -> breadcrumb truncation) ---
epic_b = upsert_issue(project, admin,
  subject: '[Epic B] Billing', tracker: feature,
  status: s_progress, priority: p_normal)
sub_b1 = upsert_issue(project, admin,
  subject: '[Sub] B-1 Payment provider integration', tracker: feature,
  status: s_progress, priority: p_high, parent: epic_b)
upsert_issue(project, admin, subject: 'B-1-a Webhook receiver', tracker: bug,
  status: s_new, priority: p_normal, assigned_to: admin, parent: sub_b1)
upsert_issue(project, admin, subject: 'B-1-b Retry on 5xx', tracker: bug,
  status: s_closed, priority: p_high, parent: sub_b1)
upsert_issue(project, admin, subject: 'B-2 Invoice PDF', tracker: feature,
  status: s_feedback, priority: p_urgent, assigned_to: admin,
  due_date: today - 2, parent: epic_b)

# --- Standalone leaves (no parent -> no breadcrumb) ---
upsert_issue(project, admin, subject: 'S-1 Fix typo on landing page',
  tracker: bug, status: s_new, priority: p_normal)
upsert_issue(project, admin, subject: 'S-2 Upgrade dependencies',
  tracker: support, status: s_closed, priority: p_low)
upsert_issue(project, admin, subject: 'S-3 Investigate flaky test',
  tracker: bug, status: s_rejected, priority: p_normal)
upsert_issue(project, admin, subject: 'S-4 Add dark mode',
  tracker: feature, status: s_progress, priority: p_normal, assigned_to: admin)

# --- Summary ------------------------------------------------------------
issues = project.issues.reload
leaves = issues.select { |i| i.leaf? }
puts '--- EZ Kanban demo seeded ---'
puts "project:  #{project.name} (#{project.identifier})"
puts "modules:  #{project.enabled_module_names.sort.join(', ')}"
puts "issues:   #{issues.count} total, #{leaves.count} leaves (cards)"
puts 'by status (leaves):'
leaves.group_by { |i| i.status.name }.sort_by { |k, _| k }.each do |name, list|
  puts "  #{name}: #{list.count}"
end
puts "view at: /projects/#{project.identifier}/ez_kanban"
