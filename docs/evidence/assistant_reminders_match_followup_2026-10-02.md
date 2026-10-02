# Min assistent: reminders and match follow-up (2026-10-02)

## Scope

User approved reminders and match follow-up as the next deterministic assistant increment. Calendar conflicts and preparation checklists remain subsequent work.

- Pending-callup tasks lead to the event's participant list with the action “Granska och påminn”. Both the bell and “Påminn alla obesvarade” now open a recipient preview. The leader can deselect recipients or cancel; no notifications are sent before confirmation.
- The preview includes the last reminder date/time and excludes answered, expired and recently reminded callups (existing six-hour server rule). Existing manage-callup commands enforce permissions, state, revision and cooldown at send time. Retry keys are retained per callup/revision within the open participant screen. Partial failures are reported and the roster is reloaded.
- Matches whose scheduled end passed within seven days show a missing-final-result task until the match workspace is completed. A completed 0–0 result is valid; scores are never used to infer missing data.
- Once completed, an empty/whitespace/missing written report yields a report task. Any nonempty saved draft clears it; publication is not required or performed by the assistant.
- Both match actions lead to Info, where existing result/report editors live. Existing attendance tasks remain independent. Report saving now refreshes the parent event and desktop assistant.
- Queries require the actor's own active leader context, owning club/team and match.live capability at context and event level. Cancelled, draft, archived, future and older matches are excluded. No private report text is returned in tasks.

## Database

Migration `20261002132339_assistant_match_followup.sql` extends the existing authorized leader projection; no new endpoint, grants, tables or AI activation. Applied to audit project `hgcshgunvooyudvrcpig` only.

Hosted rollback verification created a temporary match using the ordinary creation command, checked missing result → missing report → cleared with a draft, then rolled back all fixtures. First fixture attempt lacked required match fields and was rolled back on error; corrected fixture passed.

Security advisor findings unchanged: existing private-table RLS information and existing leaked-password-protection warning.

## Verification

- Focused assistant/event widget tests: 35 passed, including preview cancellation, recipient deselection, no sending before confirmation, cooldown after sending and match capability/routing.
- Local PGlite suite: real leader projection and event commands, result/report transitions, time boundaries, cross-team/club exclusions, draft/archived/cancelled handling, capability denial and unauthenticated access.
- Final Flutter analyze: no issues.
- Full Flutter suite: 549/549 passed (`.tmp-assistant-followup-full-tests.log`).
- Audit web release build succeeded (`.tmp-assistant-followup-web.log`). Existing wasm dry-run/font notices remain nonblocking; no new dependencies were added.
- Formatting and `git diff --check` passed.

No hosting deployment or phone installation is included in this increment.
