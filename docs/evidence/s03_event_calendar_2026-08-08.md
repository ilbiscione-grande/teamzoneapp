# S03 event and calendar evidence

Date: 2026-08-08  
Project: `TeamzoneApp` (`hgcshgunvooyudvrcpig`)  
Status: complete; all applicable S03 gates verified

## Boundary

- Greenfield only. No Teamzone6 source objects, reads or writes.
- Android application id remains `com.teamzone.teamzone`.
- Only the new TeamzoneApp audit project was migrated.

## Implemented and deployed

- Canonical events, recurrence rules, locations, event teams, audiences and append-only event revisions.
- Composite tenant foreign keys and a deferred exact-primary-team guard.
- `draft`, `scheduled`, `cancelled` and `completed` event state machine.
- Idempotent create, revise (`one`/`forward`/`all`) and transition commands.
- Atomic audit and domain outbox writes.
- Multi-context calendar and EventDetails projections with caller actions and revision.
- Stable `(starts_at, id)` opaque cursor pagination and explicit local-midnight all-day boundaries, including DST-spanning dates.
- Scoped private Realtime invalidation per club, protected by authenticated membership policy.
- Flutter calendar safe states, private invalidation plus resume fallback, create, details, edit, cancel and complete UI.

Hosted migrations:

- `20260807224555_s03_event_calendar.sql`
- `20260807225928_s03_cover_foreign_key_indexes.sql`
- `20260807231022_s03_cursor_all_day_private_realtime.sql`
- `20260807231844_s03_realtime_policy_execute.sql`

## Verification

- Full migration syntax was first executed inside an explicit hosted transaction and rolled back.
- Hosted S03 matrix passed and rolled back: DST wall-clock recurrence, overnight event, exact primary relation, shared co-manager, audience without mutation access, stale revision, idempotency/outbox and atomic series failure.
- `flutter analyze`: no issues.
- Final closure matrix passed and rolled back: valid DST-spanning all-day event, invalid all-day boundaries, cursor continuation without repeats, malformed cursor rejection, private Realtime policy/trigger presence and zero test residue.
- `flutter test`: 16/16 passed.
- Security Advisor: no S03 database finding. The existing Free-plan leaked-password-protection warning remains documented.
- Performance Advisor: no remaining S03 unindexed-foreign-key finding after the covering-index migration.
- Galaxy S25 release smoke passed with Thomas's real session: calendar loaded, an event was created for `Thomas lag`, and EventDetails exposed revision plus edit/cancel/complete actions.
- Physical private-Realtime gate passed: while the calendar remained open, event `92a89f3a-5297-4d60-9fd0-d8e53ed03122` changed from revision 3 to 4 in the hosted database and the phone displayed `S03 realtime verifierad` within five seconds, without navigation, app resume or manual refresh.

No production release or Teamzone6/live change is authorized by this evidence.
