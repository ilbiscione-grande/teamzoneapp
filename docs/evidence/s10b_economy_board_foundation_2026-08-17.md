# S10B economy and board foundation evidence

PAR-FIN-01 and PAR-FIN-02 were approved on 2026-08-17. TeamZone v1 is limited
to confidential internal cash tracking/export and is not presented as a legal
bookkeeping system. Reversals, mandate changes and entries of at least SEK
10,000 require two different approvers with initiator separation.

Migration `20260817154441_s10b_economy_board_foundation.sql` was deployed to
greenfield project `hgcshgunvooyudvrcpig`. It introduces tenant-bound economy
accounts, append-only ledger entries and reversals, separate approvals, fee
obligations, immutable pledge terms and time-bound board mandates. All six
tables have RLS enabled and no direct `anon` or `authenticated` table grants.
The internal ledger protection trigger is not client-executable.

Hosted rollback verification passed the privilege boundary and demonstrated
that a posted entry cannot be edited. Security advisors reported only the
previously known project-level leaked-password-protection warning; performance
advisors returned no warnings. No S10B client or API is active. PAR-FIN-03
remains closed, so fee runs, automated payment confirmation, reminders and
pledge settlement are absent.

Migration `20260817155109_s10b_economy_commands.sql` subsequently deployed six
authenticated API functions for account creation, entry creation, independent
approval, posting, reversal requests and a minimized economy projection. Every
write checks `module.economy` write entitlement plus a specific capability and
uses an idempotency key. Entries at or above 1,000,000 minor units (SEK 10,000)
and every reversal are high risk; posting requires two distinct approvals and
the creator cannot approve.

Hosted rollback verification passed entitlement denial, idempotent account
creation, regular posting below the threshold, denial at the threshold without
two approvals, creator self-approval denial, denial after only one independent
approval and API-only reads. Advisors remained unchanged: no performance
warnings and only the pre-existing leaked-password-protection Auth warning.

The Flutter Economy surface was then implemented using only `api` RPCs. It
shows a neutral locked state without read capability or active module access,
and capability-adapts account creation, entry creation, approval, posting and
reversal controls. Targeted analysis passed and a production-configured web
release compiled and deployed to Firebase Hosting. Hosted `/economy` returned
HTTP 200 with valid TLS, `Cache-Control: no-cache` and the expected security
headers. No commercial Economy entitlement was granted for this UI deploy.

After explicit approval, migration
`20260817200611_s10b_economy_sandbox_pilot.sql` activated a sandbox-only
`module.economy` subscription item for Thomas club and recomputed the canonical
entitlement to `write`. Thomas received read/manage/post/approve/reverse pilot
capabilities; the coach received read/approve. Rollback validation passed before
deployment. Hosted verification showed exactly one Economy write entitlement
and the intended 2 read, 2 approve, 1 manage, 1 post and 1 reverse grants.

On 2026-08-22 the physical dual-control walkthrough exposed a projection gap:
the coach approval was persisted but the client could not display approval
progress. Hosted read-only verification confirmed the SEK 10,000 entry remained
`pending`, was `high` risk and had exactly one approved decision. Migration
`20260817201850_s10b_economy_approval_visibility.sql` was then deployed. The
minimized API projection now includes required/recorded approvals, the current
actor's decision and approver display names; duplicate approval attempts return
a stable domain error. The client shows `n av 2 godkännanden`, disables repeat
approval and maps the approval guard errors to safe Swedish messages.

Targeted Flutter analysis passed with no issues. Security/performance advisors
remained unchanged: only the known Auth leaked-password-protection warning was
reported. Migration history confirmed the local and remote `20260817201850`
versions match. The release web bundle was deployed to Firebase Hosting and a
live HTTPS fetch from `app.teamzoneapp.se` returned HTTP 200, `no-cache`, and
contained the new approval error contract.

The user then reloaded the hosted Economy surface and confirmed that the new
approval projection works live. The physical walkthrough therefore verifies
the persisted coach decision and its visible `1 av 2` state. Completing the
high-risk posting still requires a third eligible test profile because the
entry creator is intentionally prohibited from supplying either approval.

After the user created `eksjoj18@gmail.com`, migration
`20260821224238_s10b_third_economy_approver_pilot.sql` was rollback-tested and
deployed. The confirmed Auth profile is linked to Thomas club as active
`club_functionary` with display name `Eksjö J18` and exactly
`economy.read,economy.approve`; no manage, post or reverse capability was
granted. Hosted verification passed. Advisors remained unchanged with only the
known leaked-password-protection Auth warning.

The complete physical high-risk walkthrough then passed: Thomas posted the
SEK 10,000 entry after two independent approvals, requested a reversal, the
coach and Eksjö J18 supplied the two reversal approvals, and Thomas posted the
counter-entry. Hosted verification confirmed both entries are `posted`, both
carry two approvals, their directions are opposite and their net is zero.

The walkthrough also confirmed that the original entry incorrectly retained a
visible Reversera action after a child reversal existed. Migration
`20260822075945_s10b_hide_completed_reversal_action.sql` was rollback-tested and
deployed to expose `reversal_state` in the minimized projection. The client now
shows the child reversal state and suppresses the action whenever any reversal
already exists. The release build succeeded, advisors remained unchanged, and
the Firebase release was verified live with HTTP 200, `no-cache` and the new
projection contract in the hosted bundle. Final visual confirmation remains.

The user reloaded the hosted Economy surface and confirmed that the original
entry displays `Reversering: posted` and no longer exposes the Reversera action.
S10B-CLI-01 is therefore physically verified and complete.

The next Board foundation increment deployed migration
`20260822082158_s10b_board_mandate_commands.sql`. Mandate changes are modeled
as separate pending requests with append-only approval facts; active mandates
are changed only by an explicit apply command after two different approvers.
The initiator cannot approve, every decision carries a reason and audit event,
and board titles grant no implicit capability. Direct table access remains
revoked; authenticated clients receive only four capability- and
entitlement-scoped RPCs for create, approve, apply and minimized reads.

Hosted rollback verification passed creator denial, one-of-two denial, two
independent approvals and successful mandate application, then removed every
test row. Foreign-key and query-path indexes were added for the new tables.
Advisors reported no new performance or security findings; only the known Auth
leaked-password-protection warning remains. No Board pilot grants or client UI
were activated in this increment, and PAR-FIN-03 remains closed.

The separately approved Board sandbox pilot then deployed migration
`20260822082824_s10b_board_sandbox_pilot.sql`. Thomas has exactly
`board.read,board.manage`, while coach and Eksjö J18 each have exactly
`board.read,board.approve`. Hosted verification counted three read, two approve
and one manage grants; no board title was translated into an implicit grant.
The rollback test `supabase/tests/s10b_board_pilot_rollback.sql` passed.

An API-only responsive `/board` client surface is now deployed. It lists
mandates and lets authorized users propose grants or revocations, approve a
pending change and apply it after two independent approvals. Controls adapt to
the caller's capabilities and backend errors are mapped to safe domain text.
Targeted Flutter analysis passed with no issues and the release web build
succeeded. Firebase Hosting release completed on 2026-08-22; a fresh HTTPS
request to `app.teamzoneapp.se/main.dart.js` returned HTTP 200 and confirmed
the deployed bundle contains `create_board_mandate_change` and `get_board`.
The physical multi-account Board walkthrough remains the final client gate.

The physical multi-account Board walkthrough subsequently passed. Thomas
proposed a time-bound Chair mandate for coach and could not approve his own
request. Coach and Eksjö J18 supplied the two independent approvals, after
which Thomas applied the change and the client showed the active Chair mandate
with the selected dates. Thomas then proposed revocation; the same two-person
approval separation passed, Thomas applied it, and the mandate was displayed
as `revoked`. The Board client gate is therefore complete.

The remaining period-boundary gate passed with rollback test
`supabase/tests/s10b_board_effective_period_rollback.sql`. Migration
`20260822090354_s10b_board_effective_period.sql` derives mandate status at read
time: a future mandate is `scheduled`, a current mandate is `active`, and an
expired mandate is `ended`; explicit `revoked`/`ended` history remains
unchanged. This avoids mutable clock-driven rows and requires no cron worker.
The isolated hosted test inserted future and expired fixtures, asserted both
projections and rolled back all writes before the migration was deployed.
Post-deploy security advisors remain unchanged with only the known leaked
password protection warning, and performance advisors report no issues.
S10B-TEST-01 is complete.
