# TeamZone App

Greenfield Flutter rebuild of TeamZone.

## Status

S00 through S10 are implemented and verified within their approved greenfield
scope. This includes the platform, roster, calendar, squad/callups, main
surfaces, messaging, Match Space, development, publication, billing
entitlements, Economy and Board. Fee/payment settlement remains closed by
PAR-FIN-03. Later decisions have opened module and webtool development:
Workspaces now opens Match, Team Development Plan and Training; Webtools has
Tacticsboard, Booking Manager and Tournament Planner betas. The complete S11
target is not closed, and the new full IDP module is not delivered.

**Current status (2026-10-25):**
[`docs/implementation/current_status.md`](docs/implementation/current_status.md)
is the consolidated delivery, environment and release-gate overview, backed by
the [25 October review](docs/evidence/app_status_review_2026-10-25.md).
Production is not provisioned. After the local
[localization fix](docs/evidence/localization_modules_2026-10-25.md), Flutter
analysis is clean and all 810 tests pass. Webtools now has its own CI job for
typecheck, tests, build and production-dependency audit. A fresh verification
found critical Next.js advisories, so both sites are pinned to 16.4.3;
clean installations, all 148 web tests, both builds and audits now pass.
See [CI/security evidence](docs/evidence/webtools_ci_2026-10-25.md).
The app, both sites and the Functions dependency patch are deployed to audit.
GitHub verification and deployment checks are recorded in the
[release receipt](docs/evidence/audit_release_2026-10-25.md).
Manual and production release gates remain open.

Since 2026-09-27 the core app has been extended with team roles and permissions,
event preparations and match mode, member profiles, follower accounts on the
public site, a club-site design with club colours, club settings, main positions
and titles, and temporary contact pages with QR codes (wave 10 in
[`docs/implementation/core_app_delivery_cards.md`](docs/implementation/core_app_delivery_cards.md)).
The earlier consolidated delta covers the deterministic personal assistant,
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
An attendance rate over expected people with callup corrections after the event,
team and place in the week and day views, a simpler event editor with sharing
when creating and monthly series, and match format and periods per team and
match (2026-10-10 – 2026-10-11) are in
[`docs/evidence/core_app_iteration_2026-10-10_10-11.md`](docs/evidence/core_app_iteration_2026-10-10_10-11.md).

Current progress is tracked in
[`docs/implementation/slice_status.md`](docs/implementation/slice_status.md).
The approved files under `docs/specification/source/` remain an immutable input
snapshot rather than a mutable progress tracker.

## Applications

- `lib/` – the Flutter app (Android, prepared iOS project, web at `app.teamzoneapp.se`).
- `public-site/` – the Next.js public site (`teamzoneapp.se`, alias `public.teamzoneapp.se`): club and
  team pages, TeamZone's start page, sign-in and follower sign-up, search and
  temporary contact pages (`/anmalan/<token>`), matchpool and public match live.
- `webtools/` – standalone Next.js beta tools; see its [README](webtools/README.md)
  for the current Firebase URL. `webtools.teamzoneapp.se` still serves the older site.
- `supabase/` – migrations, Edge Functions and isolated SQL tests.

## Targets

- Android production: `com.teamzone.teamzone`; local/audit: `com.teamzone.teamzone.test`
- iOS: `com.teamzone.teamzone`
- Flutter web

Native desktop is not a v1 target. iOS has not yet been built or verified;
build/signing and device testing require macOS/Xcode and Apple configuration.

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

### Webtools (`webtools/`)

Webtools uses the same local checks (`npm ci`, `npm run lint`, `npm test`,
`npm run build`) in `webtools/`. The full check inventory and current CI
coverage are in [command_matrix.md](docs/development/command_matrix.md).

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
npx firebase-tools deploy --only hosting:test --project teamzoneapp-b02a2
npx firebase-tools deploy --only apphosting:teamzoneapp-public --project teamzoneapp-b02a2
```

The Flutter web build for hosting uses `--release` with the `audit` defines
below, into `build/web`. Firebase is shared with production: always name the
target (`hosting:test`, never plain `hosting`). A predeploy check
(`ops/check_web_build.mjs`) refuses a build made for another environment.
Production builds go to `build/web-production` and `hosting:production`; see
[`docs/operations/production_provisioning.md`](docs/operations/production_provisioning.md).

## Security

Never commit `.env`, signing material, access tokens, secret keys or service-role keys. Public clients may eventually contain only a publishable key.

## Database boundary

The TeamZone database is rebuilt from an empty database. S01 migrations do not
read, backfill, shadow, dual-write or otherwise depend on legacy Teamzone6
objects. The repository is linked only to the new greenfield `TeamzoneApp`
audit project; Teamzone6 is not a migration source or deployment target and
must not be changed without separate approval.
