# Review fixes and account contact approval — 2026-10-02

Product-owner decision: account contact details are shared across clubs and teams.
An intake submission for an existing account must be approved by the account holder
or a currently authorized guardian before changing these shared details.

## Delivered behavior

- Match visibility and results follow team settings. Individual matches expose
  metadata editing, not an independent private/published override.
- Intake contact updates for linked accounts create a proposal with old/new email,
  phone and address. Review it in Settings → Profile → Contact updates.
- Approval rechecks current guardian authority and the original contact snapshot.
  Changed details block stale approval. Requests expire after 14 days. Rejection
  leaves contact details unchanged. Decided requests discard their contact snapshots.
- Approval updates the shared profile and all actively linked club records in one
  transaction. Login email is not changed. Current leaders in affected teams receive
  in-app notices without contact values in notification payloads.
- People without accounts retain direct club-record updates. Legacy intake endpoints
  also enforce approval for linked accounts; the old direct-write helper is revoked.
- Replayed team-detail commands cannot overwrite newer main positions or titles.
- Profile and address save atomically, including safe retry after a lost response.
- Turnstile is removed and recreated when submitting details for another person.

## Verification

- Local SQL suites `review_fixes.local.mjs` and `intake_contact_approval.local.mjs`
  passed: atomic rollback/replay, team publication rules, owner/guardian decisions,
  revoked authority, expiry, conflicts, cross-club updates and private notifications.
- Flutter analyze: no issues. The 51 affected widget tests passed across the main
  run and a corrected scrolling-test rerun. Approval and conflict/rejection are covered.
- Public site: 59 tests, TypeScript check and production build passed.
- Both migrations applied successfully to audit project `hgcshgunvooyudvrcpig`.
  Hosted checks confirm anon cannot decide, authenticated can invoke the guarded
  endpoint, and neither direct table reads nor the old bypass helper are granted.
- Security advisor adds only the expected deny-direct-access RLS INFO for the new
  table; the existing leaked-password-protection warning remains unchanged.

Hosted migration history before this change did not include all existing migration
versions, so prerequisites were checked against `internal.migration_provenance`
and actual installed functions rather than assuming the history table was complete.

Physical-device and real-mail delivery checks are not part of this verification.
Contact notices in this iteration are in-app only.

## Deployment

- Flutter release web build passed. Firebase Hosting release completed for
  `teamzoneapp-b02a2`; downloaded `app.teamzoneapp.se/main.dart.js` matches the local
  build, SHA-256 `927b3c2b036811475d6dba4ec8ca8caa37165e2a04094b213f999f11f32415e2`.
- Firebase App Hosting rollout completed for `teamzoneapp-public`; the public
  custom domain returned HTTP 200 after rollout.
- No Android installation was performed in this iteration.
