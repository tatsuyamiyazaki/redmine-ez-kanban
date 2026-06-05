# Board default status range is all statuses (override Redmine's open-only default)

The board's default IssueQuery places no status restriction (open **and** closed), deliberately overriding Redmine's usual "open issues only" default. Without this, the `is_closed`-fed Done Column would always be empty and Requirement 6-3 would be meaningless; a Kanban board exists to show the whole status flow, completion included. If a user explicitly selects a saved query or filter that restricts status, that restriction applies (and the Done Column may then be empty by intent).
