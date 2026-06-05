# frozen_string_literal: true

RedmineApp::Application.routes.draw do
  get 'projects/:project_id/ez_kanban',
      to: 'kanban#show',
      as: 'project_ez_kanban'
end
