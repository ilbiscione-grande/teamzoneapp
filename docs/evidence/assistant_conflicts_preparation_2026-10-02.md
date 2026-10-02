# Min assistent: calendar conflicts and preparation (2026-10-02)

User approved the next deterministic increment after reminders and match follow-up.

## Behavior

- Calendar conflicts cover scheduled, unarchived events associated with the same team (including shared events). Both must be readable by the actor, not ended, and start before the next seven-day boundary. Strict interval overlap means back-to-back events do not conflict. Each pair appears once, with both titles, intervals and links. The card is relevant on either event page. It describes a potential conflict, not an error, and never changes times automatically.
- Conflict tasks require `event.manage` in the selected leader context. This increment does not combine private personal calendars or infer conflicts from other clubs/teams.
- Preparation tasks count existing incomplete tasks plus material entries for training/matches starting within 48 hours. Focus and meeting agenda entries are excluded because they are not pre-event checklist requirements. Empty lists do not generate tasks or imply readiness. Calls and responses retain their existing separate tasks.
- Preparation tasks require `event.logistics` in the context and on the owning event, plus event read permission. The task opens the Preparation tab directly. Successful edits and checkbox updates refresh the desktop assistant; returning from the page reloads the assistant on mobile.
- If either conflict event can no longer be read, the team read fails visibly rather than revealing partial event metadata. Client metadata reads also suppress conflicts resolved since the task projection was read.

## Database and authorization

`20261002135847_assistant_conflicts_preparation.sql` extends the existing authorized leader projection. No new tables, grants, notification commands or AI activation. Existing team-event and preparation indexes are reused.

Applied to audit project `hgcshgunvooyudvrcpig`. Hosted rollback verification exercised real event creation, preparation save/complete commands and revisioned event rescheduling. The overlap appeared once, checklist completion cleared its task and rescheduling to an exact touching boundary cleared the overlap. All fixtures were rolled back.

Supabase security advisor findings remained unchanged (existing private-table RLS information and leaked-password-protection warning).

## Verification

- PGlite tests cover authorization, hidden/shared events, unique pairs, exact touching/time-window boundaries, rescheduling, preparation count/filtering and completion. Existing callup and match-follow-up tests remain in the same suite.
- Focused assistant/calendar/preparation widget suite passed (52 tests before the additional navigation test); the preparation suite including direct assistant navigation and completion passed 16 tests.
- Final Flutter analyze: no issues (`.tmp-assistant-planning-analyze-final.log`).
- Full Flutter suite: 552/552 passed (`.tmp-assistant-planning-full-tests.log`).
- Audit web release build succeeded (`.tmp-assistant-planning-web.log`); existing nonblocking font/wasm notices remain.
- Dart formatting and `git diff --check` passed.

No hosting deployment or phone installation is included.
