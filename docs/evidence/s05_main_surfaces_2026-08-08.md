# S05 main surfaces evidence

Date: 2026-08-08  
Project: `TeamzoneApp` (`hgcshgunvooyudvrcpig`)  
Status: complete; all applicable S05 gates verified

## Boundary

- Greenfield TeamzoneApp only; Teamzone6 was neither read nor changed.
- Android application id remains `com.teamzone.teamzone`.
- No production release is authorized.

## Delivered

- Data-minimized `api.get_main_surfaces(uuid[])` for all five main surfaces,
  with exact actor-context validation, multi-context event deduplication,
  explicit contextual actions and a versioned opaque sync cursor.
- Real Home counts/next event, callups and actions; real notification count with
  an honest unavailable message state; attendance statistics for the actor.
- Last-verified stale fallback with timestamp/retry and no raw backend errors.
- Central phone/tablet/desktop tokens, stable routes, sv/en and light/dark/system.

## Verification

- Migrations `20260808093425_s05_main_surface_projection.sql` and forward fix
  `20260808095006_s05_fix_club_person_status.sql` are deployed.
- Thomas's authenticated projection returned two upcoming events, one pending
  callup, one pending notification, one context/two members and only the
  server-approved `create_event` and `manage_roster` actions.
- Execute ACL passed: `anon=false`, `authenticated=true`.
- Security Advisor has only the existing Free-plan leaked-password warning;
  Performance Advisor has informational unused-index findings only.
- `flutter analyze` passes; `flutter test` passes 22/22.
- Debug Android APK and web target build; APK installation on Xiaomi Mi 9 passed.

## Physical gate completed

The latest debug APK was installed on Xiaomi Mi 9 (`7243fa4b`) and verified with
Thomas's restored real session:

- Home matched the hosted projection: two upcoming events, one pending callup,
  next event, and only `create_event`/`manage_roster` actions.
- Team showed Testspelare S04 and Thomas Emilson in Thomas lag plus the expected
  capability-adapted management actions.
- Calendar showed both real events with distinct completed/scheduled states and
  the authorized create action.
- Inbox showed a safe real empty state. Compose returned no allowed recipients;
  the unlinked roster-only test player was not exposed.
- Statistics showed Thomas's correct empty personal attendance projection and
  did not leak the test player's attendance.
- After force-stop, `teamzone://app/inbox` launched cold, restored session/context
  and landed directly on Inbox. Android reported `LaunchState: COLD`.

S05 is therefore closed as `[x]`.
