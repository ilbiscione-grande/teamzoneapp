# Assistant layout, categories and team scope

The assistant keeps a single list with horizontal category chips: All, Important, Preparation, Matches, Training and Other. Counts reflect the selected active/snoozed/archived bucket. Empty categories are hidden and a category that becomes empty falls back to All. Categories overlap intentionally: a preparation task for a match can appear under both filters, but is shown once in All. Important includes calendar conflicts and callup/preparation tasks for events starting within 24 hours of the projection timestamp.

Cards have 16-pixel outer gaps, padded headers, spaced summaries and a divider before the three existing actions. Empty secondary sections are hidden. The horizontal chip list has its own scrollbar for desktop use.

Settings now offer All my teams or Current team. The account stores this preference; the active team is resolved from the current app context. List and badge use the same loader. Team scope is applied before other teams' leader/event reads; personal conflicts remain visible when either side belongs to the selected club/team. With no selected team, current-team mode shows no tasks and prompts for a team selection. Permission checks remain unchanged.

Migration `20261003064829_assistant_task_team_scope.sql` adds the private scope field and a versioned save RPC. The old RPC preserves scope for installed clients. Both use the same revision counter; identical retries are safe. Local database tests cover scope persistence, isolation, stale revisions, retry, null validation, legacy writes and anonymous denial. Audit migration and hosted rollback smoke check passed. Security advisors show no finding for the changed preferences feature; existing findings remain unchanged.

Validation: 54 focused Flutter tests passed (52 on the suite run; two adjusted UI tests passed on rerun). The adjusted tests scroll to a settings control and assert the intentionally hidden empty section. Added tests cover both sides of personal conflicts, selected-team reads, no selected team, category counts/filtering at 360-pixel width and scope persistence after a failed save. Flutter analyze and diff whitespace checks passed.

Audit web release built successfully with the existing Cupertino font warning. Localhost port 5000 serves the new build; no external hosting deployment or phone installation was performed.
