# S04 squad, callup, response and attendance evidence

Date: 2026-08-08  
Project: `TeamzoneApp` (`hgcshgunvooyudvrcpig`)  
Status: complete; all applicable S04 gates verified

## Boundary

- Greenfield only; Teamzone6 was neither read nor changed.
- Android application id remains `com.teamzone.teamzone`.
- Provider delivery is fail-closed/suppressed until a separate provider and production approval exists.

## Delivered

- A single revisioned event → squad → callup write path with eligibility snapshots.
- Idempotent save/lock/send/cancel/remind commands with stale revision protection.
- Separate append-only responses, explicit guardian acting-as audit, scoped single-use response tokens and separate attendance facts/history.
- Explicit attendance states `unknown`, `present`, `late`, `partial`, `absent`; unknown is never collapsed into absent.
- Per-recipient notification outbox, delivery attempts, exponential retry/dead-letter support, dedupe and hashed provider references.
- Active JWT-verified `notification-worker` Edge Function v1 with service-role-only worker RPC.
- EventDetails UI for squad, callup delivery state and explicit attendance mutation.
- Product clarification during physical smoke: leaders with a valid temporal team roster relation are valid callup subjects alongside players. The temporary role-package narrowing was reverted by forward migration `20260808081822_s04_allow_eligible_leaders.sql`.

## Verification

- Hosted transactional matrix passed and rolled back: eligible draft/lock/send, stale revision rejection, duplicate send result, guardian acting-as response, simulated provider failure without domain rollback and explicit unknown attendance.
- Notification worker database contract passed with `SKIP LOCKED`, attempt accounting and sanitized error/reference fields.
- `flutter analyze`: no issues.
- `flutter test`: 19/19 passed.
- Release APK built successfully at `build/app/outputs/flutter-apk/app-release.apk`.
- Security/Performance Advisors reviewed; S04 deny-policy and FK covering indexes were added. The existing Free-plan leaked-password-protection warning remains.

## Physical device gate

The release APK was installed on Xiaomi Mi 9 (`cepheus`, ADB `7243fa4b`). With
Thomas's real session, `S04 fysisk verifiering` completed the visible chain:

- empty squad showed separate Callups and Attendance safe states;
- draft revision 1 contained eligible `Testspelare S04` and leader `Thomas Emilson`;
- lock removed draft mutation and exposed only send;
- send produced exactly two `pending` callups with separate `pending` delivery state;
- attendance began `unknown` for both subjects;
- changing only the test player to `present` left Thomas `unknown` and both callups/deliveries `pending`.

A final database read matched the device projection exactly. This also verified
the product clarification that temporally eligible leaders may be callup subjects.

No production release or Teamzone6/live change is authorized by this evidence.
