# Target Redmine 6.0+ / Rails 7.2 only

We support only Redmine 6.0 and later (Rails 7.2) rather than also covering the 5.x line. The host Redmine for this plugin is a fresh, recent install, and dropping back-compat lets the implementation use current plugin/asset/IssueQuery APIs without version-branching code or dual-line CI — at the cost of excluding 5.x sites.
