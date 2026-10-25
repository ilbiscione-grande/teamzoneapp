# Development environment

## Verified S00 baseline

- Windows 10 Pro 22H2
- Flutter 3.44.8 / Dart 3.12.2
- Java 17.0.20
- Android SDK 36.0.0; licenses accepted
- Chrome available for Flutter web
- Node 24.19.0 / npm 11.17.0
- Supabase CLI 2.111.0
- Git 2.55.0.windows.3

Visual Studio is intentionally absent because native Windows desktop is not a v1 target. Android and web are buildable on this host. iOS project files are maintained here, while building/signing requires macOS or suitable CI.

Routine isolated SQL tests do not require Docker or a local PostgreSQL server:
they use PGlite (`supabase/tests/*.local.mjs`) with fixtures for the objects
they touch. This is not a full migration replay. The empty-database release
check uses Docker/Supabase; the last documented replay covered 320 migrations
on 13 October and must be repeated for the current chain. See
[production provisioning](../operations/production_provisioning.md).

## Environment contract

Status checked 2026-10-25: [current delivery status](../implementation/current_status.md).
Separate production is not provisioned. Current public addresses still run
against the audit project; planned address moves are not completed deployments.

| Surface | Current origin | Hosting |
|---|---|---|
| Flutter audit | `https://app.teamzoneapp.se` | Firebase Hosting target `test` |
| Public site, audit | `https://teamzoneapp.se` (canonical), `https://public.teamzoneapp.se` (alias) | App Hosting `teamzoneapp-public` |
| New Webtools, audit | `https://teamzoneapp-webtools--teamzoneapp-b02a2.europe-west4.hosted.app` | App Hosting `teamzoneapp-webtools` |
| Old Webtools | `https://webtools.teamzoneapp.se` | Older deployment; domain not moved to new backend |

`ops/environments.json` remains the build/deployment guard manifest; its audit
`publicOrigin` records the alias while the site's `PUBLIC_ORIGIN` is now the
apex domain. The current origin table above records that distinction without
changing the build guard as part of this documentation update. Planned
`test.`/`test-public.` addresses and production Stockholm database are described
in the production runbook.

`TEAMZONE_ENV` accepts `local`, `audit`, `staging` or `production`. Unknown values parse fail-safe to `local`. `local` does not wire a Supabase project — a plain `flutter build`/`flutter run` therefore shows "Backend är inte ansluten" by design, not as a bug. See [command_matrix.md](command_matrix.md) for the exact `--dart-define` flags needed for a backend-connected build against a real (e.g. `audit`) project.

## Public site environment

`public-site/apphosting.yaml` sets the runtime values; secrets come from Firebase App Hosting.

| Variable | Purpose |
|---|---|
| `PUBLIC_ORIGIN` | Canonical origin used for canonical URLs and sitemaps |
| `PUBLIC_SITE_ORIGINS` | Further addresses the site is served on (comma-separated, `https://`). Requests and Turnstile tokens from these are accepted; currently `https://public.teamzoneapp.se` |
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Supabase project and public key (sign-in and follower sign-up) |
| `SUPABASE_SECRET_KEY` (secret) | Server-only service key for public reads and marking follower accounts |
| `PUBLIC_API_IP_HMAC_SECRET` (secret) | IP hashing for rate limits |
| `NEXT_PUBLIC_TURNSTILE_SITE_KEY`, `CAPTCHA_SECRET_KEY` (secret) | Cloudflare Turnstile for contact and sign-up |
| `PUBLIC_PERSONAL_HOME_ENABLED` | Enables the personal start page |
| `NEXT_PUBLIC_WEBTOOLS_URL` | New Webtools origin linked by the public portal; currently the Firebase hosted.app origin |

Current `PUBLIC_ORIGIN` is `https://teamzoneapp.se`. The alias may return a
canonical 308; use the canonical origin for the strict PUB-06 smoke runner.

External settings for the public site must match its origins: the Turnstile
widget's allowed hostnames and Supabase Auth's follower-confirmation redirect
allow list must include the actual callback origin. Recheck these when moving
domains; an App Hosting variable alone does not update external allow lists.

## Webtools environment

`webtools/apphosting.yaml` points to the audit project with public Supabase
configuration, TeamZone site/app links and a server-only secret for public
tournament reads. The secret is never browser configuration. See
[Webtools README](../../webtools/README.md) for commands and route scope.
The signup confirmation origin must be in Auth's redirect allow list.
`TACTICS_DEMO=1` is an optional local demo switch, not a required production setting.

## Secret handling

Secrets are supplied outside Git. Flutter/web/mobile clients may only receive a Supabase publishable key; secret/service-role keys remain server-side. There is no committed `.env` file in this repo (only `.env.example` with placeholders) and no `.vscode/launch.json` — get the real `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` values from the Supabase dashboard or `supabase projects list`/CLI access to the linked project.

## Support email environment

Support notifications use Supabase, Resend, Netlify DNS and ImprovMX. The
complete topology, secret names, DNS records, recipient rules, rotation and
troubleshooting procedure are documented in
[support_email_runbook.md](../operations/support_email_runbook.md). The
machine-readable service list is [ops/service_inventory.json](../../ops/service_inventory.json),
and secret names without values are kept in
[ops/secret_inventory.json](../../ops/secret_inventory.json).

`RESEND_API_KEY` and `SUPPORT_WORKER_TOKEN` are backend-only secrets.
`SUPPORT_EMAIL_FROM` and `SUPPORT_PORTAL_URL` are non-secret runtime
configuration stored with the Edge Function settings. None of these values are
Flutter build defines or public-site variables.
