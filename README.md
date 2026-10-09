# TeamZone App

Greenfield Flutter rebuild of TeamZone.

## Status

S00 through S10 are implemented and verified within their approved greenfield
scope. This includes the platform, roster, calendar, squad/callups, main
surfaces, messaging, Match Space, development, publication, billing
entitlements, Economy and Board. Fee/payment settlement remains closed by
PAR-FIN-03, and S11 workspaces/webtools are explicitly deferred while the core
application is stabilized.

Since 2026-09-27 the core app has been extended with team roles and permissions,
event preparations and match mode, member profiles, follower accounts on the
public site, a club-site design with club colours, club settings, main positions
and titles, and temporary contact pages with QR codes (wave 10 in
[`docs/implementation/core_app_delivery_cards.md`](docs/implementation/core_app_delivery_cards.md)).
The latest consolidated delta covers the deterministic personal assistant,
account/contact privacy and the official-club support operation through 2026-10-04:
[`docs/evidence/core_app_iteration_2026-10-02_10-04.md`](docs/evidence/core_app_iteration_2026-10-02_10-04.md).
The 2026-10-05 worklist (leaner navigation menu, calendar navigation, theme
mode, page-aware quick actions and event deletion before callups) is in
[`docs/evidence/core_app_iteration_2026-10-05.md`](docs/evidence/core_app_iteration_2026-10-05.md).
Public page administration and news images, event KPIs and follow-up, the
event "⋮" menu, a Hem that follows the day for every role, audience-based
event visibility and the demo club (2026-10-07 – 2026-10-08) are in
[`docs/evidence/core_app_iteration_2026-10-07_10-08.md`](docs/evidence/core_app_iteration_2026-10-07_10-08.md).
The temporary, removable attendance export to laget.se with member import, a
local sync agent and automatic activity lookup, team statistics under Laget, a
role-aware fifth menu button and attendance fixes (2026-10-08 – 2026-10-09) are in
[`docs/evidence/core_app_iteration_2026-10-08_10-09.md`](docs/evidence/core_app_iteration_2026-10-08_10-09.md).

Current progress is tracked in
[`docs/implementation/slice_status.md`](docs/implementation/slice_status.md).
The approved files under `docs/specification/source/` remain an immutable input
snapshot rather than a mutable progress tracker.

## Applications

- `lib/` – the Flutter app (Android, iOS, web at `app.teamzoneapp.se`).
- `public-site/` – the Next.js public site (`public.teamzoneapp.se`): club and
  team pages, TeamZone's start page, sign-in and follower sign-up, search and
  temporary contact pages (`/anmalan/<token>`).
- `supabase/` – migrations, Edge Functions and isolated SQL tests.

## Targets

- Android: `com.teamzone.teamzone`
- iOS: `com.teamzone.teamzone`
- Flutter web

Native desktop is not a v1 target. iOS build/signing requires a later macOS or CI environment.

## Local checks

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Use `--dart-define=TEAMZONE_ENV=audit` to select a non-secret environment name.
An approved non-live environment can be connected with:

```powershell
--dart-define=SUPABASE_URL=https://project-ref.supabase.co
--dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME
```

Without both values the app deliberately shows a safe unconfigured state.

### Public site (`public-site/`)

```powershell
npm ci
npx tsc --noEmit
npm test
npm run build
```

Server configuration lives in `public-site/apphosting.yaml` and secrets in
Firebase App Hosting; see [`docs/development/environment.md`](docs/development/environment.md).

### External services and support email

The current service inventory is recorded in
[`ops/service_inventory.json`](ops/service_inventory.json). Support case email
uses Supabase for the private queue and scheduled worker, Resend for outbound
delivery, Netlify DNS for the domain's MX records and ImprovMX for forwarding
`support@teamzoneapp.se` to the operational inbox. Configuration, security,
rotation and troubleshooting are documented in
[`docs/operations/support_email_runbook.md`](docs/operations/support_email_runbook.md).

### Isolated SQL tests

Migrations are checked in an in-memory PostgreSQL (PGlite) before they are run
against the audit project:

```powershell
node supabase/tests/<name>.local.mjs
```

### Deployment (audit project)

Only after the matching migrations are applied:

```powershell
npx firebase-tools deploy --only hosting --project teamzoneapp-b02a2
npx firebase-tools deploy --only apphosting:teamzoneapp-public --project teamzoneapp-b02a2
```

The Flutter web build for hosting uses `--release` with the `audit` defines below.

## Security

Never commit `.env`, signing material, access tokens, secret keys or service-role keys. Public clients may eventually contain only a publishable key.

## Database boundary

The TeamZone database is rebuilt from an empty database. S01 migrations do not
read, backfill, shadow, dual-write or otherwise depend on legacy Teamzone6
objects. The repository is linked only to the new greenfield `TeamzoneApp`
audit project; Teamzone6 is not a migration source or deployment target and
must not be changed without separate approval.
