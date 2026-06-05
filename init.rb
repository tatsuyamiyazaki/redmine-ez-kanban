# frozen_string_literal: true

Redmine::Plugin.register :redmine_ez_kanban do
  name 'Redmine EZ Kanban'
  author 't-miyazaki'
  description "Read-only Kanban board that visualizes a project's leaf issues " \
              'as cards in fixed status columns. All editing stays in Redmine core.'
  version '0.1.0'
  url 'https://github.com/t-miyazaki/redmine-ez-kanban'

  requires_redmine version_or_higher: '6.0.0'

  # Global column layout (ADR-0004), serialized into Setting. Empty 'columns'
  # means "use the built-in default layout"; the admin editor (issue 0005)
  # populates it later. No settings partial yet.
  settings default: { 'columns' => [] }

  project_module :ez_kanban do
    # Read-only board: a single view permission is all the plugin needs.
    permission :view_ez_kanban, { kanban: [:show] }, read: true
  end

  menu :project_menu, :ez_kanban,
       { controller: 'kanban', action: 'show' },
       caption: :label_ez_kanban,
       param: :project_id
end
