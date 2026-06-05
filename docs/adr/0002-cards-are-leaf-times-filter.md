# Cards = Leaf × Filter, with leaf-ness as a global tree property

A Card is shown if and only if the issue is a leaf **in the full Redmine issue tree** (zero children, independent of any filter) **and** it matches the active IssueQuery. Parents/ancestors are never Cards; they appear only as Breadcrumb/Scope context.

## Considered Options

- **Leaf-ness over the full tree, then intersect with the filter (chosen).** A filtered-in parent whose children are filtered out is still not a Card; a filtered-in leaf whose parent is filtered out is still a Card. Matches Requirement 4 (a leaf gaining a child drops off the board regardless of filters).
- **Leaf-ness computed within the filtered set.** Rejected: the same issue would flip between card/parent depending on the filter, making the board's card set unstable and contradicting Requirement 4.
