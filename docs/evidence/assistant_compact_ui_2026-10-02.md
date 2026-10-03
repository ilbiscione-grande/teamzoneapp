# Min assistent: compact tasks and personal organization

## User-visible change

The default task card shows its subject/count, event, team/club and time. Explanations, source timestamps, full intervals and secondary conflict links are disclosed on expansion; one card is expanded at a time. Actions remain directly accessible: Åtgärda, Skjut upp and Arkivera. Following screenshot feedback, the three actions share one fixed row with equal-width controls, compact labels and 48 px height. Assistant settings and the inactive specialist-queue explanation are collapsed beneath the task list.

Åtgärda opens the existing authorized domain editor. Skjut upp offers one hour, one day or one week. Arkivera affects the current user's assistant list only; it does not mark work complete, cancel events or affect colleagues. Both support undo/restore. Aktuellt, Uppskjutet and Arkiverat filters show counts. Archived/snoozed views contain only tasks still relevant and authorized by the live projection, not a permanent activity history. Archived tasks remain archived until restored; snoozed tasks return when the selected interval expires, provided the domain task is still relevant. Refresh, resume and the next snooze-expiry timer re-read current facts.

## Persistence and authorization

Migration `20261002142418_assistant_task_disposition.sql` is applied to audit project `hgcshgunvooyudvrcpig`.

- Dispositions are private to auth.uid(), keyed by task kind and canonical source route (including conflict partner). No names, report bodies or contact details are stored.
- The write validates that the exact task exists in the caller's authorized leader-context projection. Revoked capabilities and foreign tasks cannot be organized.
- The API wrapper is invoker; its internal command has an explicit auth check and empty search path. Anonymous execution and direct authenticated table access are revoked. RLS is enabled with an own-profile policy as defense in depth.
- State is attached only to live, authorized tasks. No cached data authorizes writes. Domain commands, event revision and notifications remain unchanged.
- A failed state save leaves the task available and shows the latest error immediately instead of queuing it behind old confirmations.

## Verification

- PGlite suite passed: account isolation, archive/restore, snooze expiry, invalid duration, nonexistent task, revoked capability and unchanged event revision, alongside existing signal tests.
- Hosted rollback test passed for archive → snooze → restore and unchanged event revision. All fixtures rolled back. An initial fixture had an ambiguous local variable in the assertion; corrected fixture passed.
- Focused assistant widget tests passed (15): progressive disclosure, narrow layout, archive/restore/snooze, failure feedback, navigation and stale-data behavior.
- Advisor baseline unchanged; existing leaked-password-protection warning remains.
- Full Flutter run: 552 passed; two source-format assertions failed because formatting wrapped Key constructors. Those assertions now tolerate whitespace, and both affected suites passed on rerun (12/12). All 554 cases are covered by the full run plus repaired-suite rerun (`.tmp-assistant-ux-full-tests.log`, `.tmp-assistant-ux-contract-tests.log`).
- Final Flutter analyze: no issues (`.tmp-assistant-ux-analyze-final.log`).
- Audit release web build succeeded (`.tmp-assistant-ux-web.log`); existing nonblocking font/wasm notices remain.
- `git diff --check` passed. Hosted ACL checks verified authenticated command access, anonymous denial and no direct authenticated table access.

No hosting deployment or phone installation is included.

## Follow-up: icon filters and empty context

Aktuellt/Uppskjutet/Arkiverat now use three equal-width icon buttons in one row. Tooltips retain their names and counts, and selection remains explicit. The entire Här och nu section, including its team/activity subtitle, is omitted when it has no tasks. The global empty-list message and read-error feedback remain available. The 15 assistant widget tests passed, including the one-row layout at 248 px and hiding the context after its last task clears.

The action-row follow-up also verifies aligned centers for Åtgärda, Skjut upp and Arkivera at 248 px. Localhost serves build/web; source-only changes require a fresh web build before they can be reviewed there.

## Follow-up: inline preparation checklist

The desktop panel uses 25% of the viewport, bounded to 360–480 logical pixels.
Expanding a preparation task (or pressing Åtgärda on its collapsed card) now
loads its checklist through the existing event and preparation services.
Only unfinished tasks and, for matches/training, material are shown, with the
assigned person's authorized display name. Focus and agenda are excluded,
matching the existing assistant projection. No new database command is needed.

Checking an item explicitly saves `done=true` through the ordinary endpoint.
Context logistics capability, fresh task data, event state and the preparation
response's logistics permission gate editing; the endpoint remains authoritative.
Failed saves show an error and refetch without claiming success. Successful
saves refresh the assistant projection, removing the task when its last item is
complete. A second Åtgärda on the expanded card opens the full preparation page.

Verification: 19 focused widget tests passed, including lazy loading, inline
completion and task removal, failed-save retry, permission gating and narrow
layout. Flutter analyze reported no issues. Logs:
`.tmp-assistant-checklist-tests.log`, `.tmp-assistant-checklist-analyze.log`.

## Follow-up: direct match follow-up

Both assistant entry points now route result/report actions through the same
handler. It re-reads the event, validates the task context's match capability,
the event's match action, primary/co-managing team relationship, event state and
end time, then loads the current match snapshot. The existing result dialog is
opened directly for an unfinished match. A completed match opens the existing
report dialog if its report is still empty and editable. Already-written reports
and unavailable events produce feedback and refresh the assistant instead.

Both dialogs display the match, team and club when opened from the assistant.
The existing revision checks, idempotent retry, score validation, draft default
and explicit publication switch are reused. No new database endpoints or
automatic publication are introduced. After saving or cancelling, the task
projection is reloaded: result tasks become report tasks, and a saved nonempty
draft clears the report task.

The calendar/assistant widget suites passed 41 cases, including the full direct
result-to-draft flow and read failure. Analyze reported no issues. Logs:
`.tmp-assistant-match-tests.log`, `.tmp-assistant-match-analyze.log`.
An additional permission-revocation widget test passed separately
(`.tmp-assistant-match-permission-test.log`): a card loaded before permission
changes cannot open the editor afterward. Total: 42 verified cases.

## Follow-up: assistant FAB counter

The floating assistant button now carries a small Material badge counting active
authorized task cards across the user's leader teams, using the same task loader
as the assistant. Counts inside a card (participants/checklist items) do not
inflate the badge. Snoozed and archived tasks are excluded; zero is hidden.
Unknown, incomplete or stale reads do not display a misleading count.

The badge reloads on page/context changes, event task invalidation, app resume,
return from the assistant and the next snooze expiry. Late responses from a
previous context are ignored. The count also has a screen-reader label.
There is no background notification delivery or new polling loop.

## Follow-up: calendar conflicts

Expanded conflict cards compare both activities with team/club, local start/end
and place (including pitch). The action row offers Ändra tid, Skjut upp and
Avsiktlig överlappning. The latter uses the existing personal archive command;
the full conflict route includes both event IDs, so other pairs are unaffected.
It can be restored under Arkiverat and does not alter the shared calendar.

Ändra tid re-reads both events and checks the overlap, then lets the user choose
one editable activity. Shared view-only activities are disabled. Before opening
the time dialog, event revision, state and edit permissions are read again.
The dialog saves only starts_at/ends_at through reviseEvent with scope=one,
expected revision and a retry-stable command ID. Moving the start preserves the
duration; the end can be changed separately. All-day events use date selection
and explicitly label their exclusive end date. No series or unrelated fields
are changed. After returning, the assistant re-reads the projection and removes
resolved conflicts; unresolved ones remain visible.

43 calendar/assistant tests passed, including choosing the second activity,
single-occurrence/time-only payload and retry after failure. Existing assistant
tests recheck overlap after event changes. Logs: `.tmp-conflict-tests.log`.

## Follow-up: quieter list header and action spacing

The generic “Behöver din uppmärksamhet” row is removed. Refresh now sits beside
the assistant name and settings action in both the full-page app bar and the
desktop side-panel header. The active list no longer repeats “Mina uppgifter”;
the snoozed and archived headings remain because they describe a changed state.

Card actions use a 44-pixel visual height with eight pixels between actions.
They still share the row equally and retain tooltips and the existing action
behavior. Eleven focused responsive, assistant, match and preparation tests
passed at desktop and narrow-panel sizes. Flutter analyze and diff checks passed.

The status controls (Current, Snoozed and Archived) were subsequently clarified
as the controls that needed reducing. They now use fixed 52 × 44 pixel icon
buttons with 10 pixels between them, stay on one row and keep their count in the
tooltip. A 248-pixel-wide panel test verifies their width, gaps and shared row.

## Follow-up: activity warning groups

Visible warnings with the same team context and activity ID now share one
outlined activity card. The shared header identifies the club, team, activity,
start time and number of matters to handle. Each warning remains a separate row
inside the card, with its own expandable explanation and its existing action,
snooze and archive controls. A single warning keeps the compact single-card
layout. Status and category filters run before grouping, so the displayed count
only describes the warnings currently visible to the user.

The focused assistant suite passed all 16 tests, including a two-warning group
beside an ungrouped activity. Flutter analyze reported no issues.

## Follow-up: page-aware assistant context

The assistant now separates its page-specific “Här och nu” section from the
account-wide task list with explicit relevance rules. Calendar shows the active
team's event tasks, an event page shows only that event (including the other
side of a calendar conflict), Team highlights callup and attendance work, and
Statistics highlights attendance and match follow-up. Home, Inbox and unrelated
administrative pages do not claim unrelated tasks are relevant to the page.
Changing pages updates the presentation without reloading the task projection;
changing team context still performs an authorized reload.

The 17-case assistant suite verifies each relevance rule and live page changes.
A desktop shell test also navigates Home → Calendar → event and verifies that
the persistent side panel changes from global view to Calendar and then to the
specific activity. The existing mobile event-context navigation test still
passes.
