# S06 messaging progress evidence

Date: 2026-08-08  
Project: `TeamzoneApp` (`hgcshgunvooyudvrcpig`)  
Status: complete; server, client, physical and abuse/retention gates verified

## Boundary and approvals

- Greenfield only; Teamzone6 was neither read nor changed.
- PAR-PRIV-01 and PAR-PRIV-03 were approved unchanged in all roles by the
  project owner on 2026-08-08. The signed-in-task record is mirrored in
  `docs/security/s06_privacy_retention_decision_proposal.md`.
- Player-to-player direct messaging remains disabled. Cross-club discovery is
  unavailable unless both parties have trusted adult-leader verification.

## Implemented and deployed

- Scoped threads, participants, messages, audit versions, monotonic reads,
  fail-closed mute, contact controls, reports and approved retention classes.
- One server recipient helper shared by discovery and create validation; every
  send rechecks active participant, temporal relation, scope and blocks.
- Direct/group create, list threads/messages, send with idempotency and atomic
  notification outbox, mark read and mute APIs.
- Private `message-files` bucket, staged metadata, MIME/10 MiB limits, owner and
  active-thread RLS, atomic staged-file finalization with send and withdrawn file
  state on recall. No bucket-wide authenticated read exists.
- Five-minute signed URLs are generated on demand and never carried by Realtime.
  The client supports staged upload, atomic send, inline thumbnails and opening
  authenticated attachments.
- Private Realtime invalidation contains only thread ID and revision.
- Cross-club verified-leader directory/request/accept/decline/block foundation,
  3/day and 10/30-day request limits, 14-day expiry, recall window and report
  evidence/block/close behavior.
- JWT-verified `message-retention-worker` v1 plus service-role-only claim/finish
  and body/version retention functions. Storage deletion uses Storage API rather
  than direct writes to `storage.objects`.
- Flutter Inbox now lists real threads, provides honest empty/error states,
  resolves allowed recipients, creates direct threads, reads/sends messages,
  marks read and changes mute state.

## Verification

- Hosted rollback matrix created a temporary second Auth leader and proved:
  recipient discovery, direct thread creation, send revision 2, exactly one
  notification outbox record, recipient read, anon execute denial and immediate
  send denial after the recipient assignment ended. All fixture data rolled back.
- Service-role retention claim completed with no expired files.
- Security Advisor is clean except the existing Free-plan leaked-password
  protection warning.
- `flutter analyze`: no issues. `flutter test`: 26/26 passed.
- Physical Xiaomi smoke passed for real Inbox empty state, compose recipient
  denial and cold deep-link/session restore. The roster-only test player was not
  leaked as a recipient.
- Positive two-account messaging passed with Thomas Emilson sending `hej från
  Thomas` to the separately linked Coach Emilson leader account. The server
  recorded one message and exactly one notification outbox row; Coach opened the
  thread and advanced the monotonic read marker through revision 2.
- Device testing exposed an unread-baseline defect and a pull-to-refresh
  lifecycle defect. Forward migration `20260808164316_s06_fix_unread_baseline.sql`
  corrected the unread projection. The Inbox refresh now preserves the visible
  list while fetching, terminates with a bounded safe error, and was physically
  re-tested successfully on the Xiaomi Mi 9 with the read badge absent.

## Closure verification 2026-08-15

- Physical Xiaomi testing passed two-account send/read/refresh, notification and
  request-center navigation, attachment upload, inline thumbnail and signed open.
- Rolled-back hosted matrices passed known foreign UUID and anon denial,
  withdrawn-file denial, staged orphan claim, ordinary expiry, legal-hold
  preservation, same-club cross-club denial, daily request limiting,
  report/block/close and recall/file-withdrawal idempotency.
- Closure testing found and fixed three issues with forward migrations: legal
  hold retention exclusion, explicit cross-club separation, and monotonic recall
  revisions with recall/report command deduplication.
- `flutter analyze` reports no issues and `flutter test` passes 27/27.
- Security Advisor is clean except Supabase Free's existing leaked-password
  protection warning. Local and hosted migration versions are aligned.

S06 is closed. No production release, S07 authorization or Teamzone6 change is
implied.
