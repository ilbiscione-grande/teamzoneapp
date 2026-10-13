# Production provisioning (X-OPS-01)

Decisions by the product owner, 2026-10-13:

| Decision | Choice |
|---|---|
| Supabase region | Stockholm, `eu-north-1` |
| Firebase | Shared with the test (audit) environment for now; separate hosting sites, an own app id for test builds and the `environment` field keep them apart. Split later if the team grows. |
| Addresses | Production `app.teamzoneapp.se` (app) and `teamzoneapp.se` (public site); test moves to `test.teamzoneapp.se` and `test-public.teamzoneapp.se`. |
| Empty-database check | Locally with Docker before the project is created. |

The data lives only in Supabase, which is separate per environment from the
start. Production provisioning, traffic promotion and key retirement still
need explicit approval (`xops_release_runbook.md`).

## Phase 1 — code ready for two environments

**Done 2026-10-13.**
- The web sign-in callback follows the origin the app runs on.
- Links to the public site use the configured `PUBLIC_SITE_URL`.
- Edge Functions allow extra origins via `TEAMZONE_EXTRA_WEB_ORIGINS`.
- **Hosting:** `firebase.json` has two targets (`.firebaserc`): `test` on
  the existing site `teamzoneapp-b02a2` (build `build/web`) and `production`
  on site `teamzoneapp-production` (build `build/web-production`), each
  with its own CSP. The production CSP says `PRODUCTION_REF` until phase 3.
  A predeploy check (`ops/check_web_build.mjs`) refuses a build or CSP that
  names another environment's Supabase project, and refuses production until
  `ops/environments.json` has its project ref. Deploy with
  `--only hosting:test` or `--only hosting:production`, never plain
  `hosting`.
- **Functions:** one critical-flow monitor per Supabase project.
  `runCriticalFlowMonitor` (test) is unchanged;
  `runProductionCriticalFlowMonitor` is deployed once
  `firebase-functions/.env.teamzoneapp-b02a2` sets
  `TEAMZONE_PRODUCTION_SUPABASE_URL` and the secret
  `TEAMZONE_PRODUCTION_SUPABASE_ANON_KEY` is set (the production project's
  legacy anon key: the monitor endpoint verifies a JWT). The web error sink
  accepts `app.` and `test.teamzoneapp.se`.
- **Public site:** `public-site/apphosting.production.yaml` overrides the
  Supabase URL, publishable key and secret names (`teamzoneapp-production-*`)
  for a backend whose environment name is `production`; `firebase.json`
  lists the backend `teamzoneapp-public-production`. `PRODUCTION_REF` and
  the key are filled in after phase 3.
- **Android:** only a `TEAMZONE_ENV=production` build is
  `com.teamzone.teamzone`; every other build is `com.teamzone.teamzone.test`
  ("TeamZone Test"), and Firebase on Android reads `google-services.json` for
  the built id. A Play bundle refuses to build for any other environment.

Product owner, before the next Android test build:
- Register the Android app `com.teamzone.teamzone.test` ("TeamZone Test") in
  Firebase (project settings → Your apps → Add app), then download the
  project's `google-services.json` again (it then lists both apps) to
  `android/app/google-services.json`. Until then an audit Android build stops
  with "No matching client found for package name
  'com.teamzone.teamzone.test'". The test app installs beside the old one;
  uninstall the old `com.teamzone.teamzone` test install from the phone.

## Phase 2 — prove the migrations on an empty database

**Done 2026-10-13.** All 320 migrations replay on an empty local database
(`npx supabase start`, Docker). Twelve migrations were test-project data —
Stripe sandbox prices and pilots for the Thomas club, MSG/TEAM walkthrough
fixtures bound to fixed test accounts. They are now marked `audit-only:` and
do nothing where the pilot club does not exist, so an empty database and
production skip them. One mixed migration
(`20260921203502_msg02_direct_thread_counterparty_name_fallback`) keeps its
function fix and skips only its fixture. The test project, where they already
ran, is unaffected.

Compared with the test project, the replayed schema has the same functions,
tables, columns, policies, grants, indexes, buckets and triggers, except:
- the push migration (`20261023090000`), not yet run in the test project;
- four functions differ only in a trailing semicolon, and one calls
  `extensions.digest` instead of `digest` (the same function);
- `publication_runtime_state_enabled_check` exists on a new database (the
  test project removed it with `ops/pub02_enable_audit_public_runtime.sql`):
  publication starts locked, as intended;
- a duplicate `reminder_count >= 0` check on `core.callups` (harmless);
- three Supabase-managed triggers on `storage.buckets` in the hosted project.

To repeat it: `npx supabase start -x studio,imgproxy,mailpit,logflare,vector,supavisor,postgres-meta,edge-runtime`
applies every migration to a fresh local database; compare with the test
project using read-only catalog queries (functions with body hash, security
mode and grants; columns; constraints; indexes; policies; RLS; table grants;
triggers; buckets; cron jobs). Nothing may depend on dashboard-made state
except the Vault secrets listed below.

## Phase 3 — create and configure the Supabase project (product owner)

1. Put the organisation on **Pro** (leaked-password protection, daily backups,
   no pausing). Create project `TeamzoneApp Production` in **eu-north-1** with
   a generated database password kept in the password manager.
2. **Auth** (Dashboard → Authentication), as in `docs/security/s01_auth_policy.md`:
   - Site URL `https://app.teamzoneapp.se`; redirect URLs
     `https://app.teamzoneapp.se/auth/callback` and
     `teamzone://app/auth/callback`.
   - Minimum password length 12, leaked-password protection on, e-mail
     confirmation on, secure e-mail change on.
   - Custom SMTP through Resend with a production API key and sender.
   - Review rate limits (sign-in is additionally limited per e-mail and
     address by `auth-password-sign-in`).
3. **Schema:** `npx supabase link --project-ref <prod ref>` then
   `npx supabase db push`. This runs every migration and records them in the
   migration log. Verify with `npx supabase migration list` and
   `npx supabase db push --dry-run` ("up to date").
4. **Vault** (SQL editor):
   ```sql
   select vault.create_secret('https://<prod ref>.supabase.co', 'project_url');
   select vault.create_secret('<random>', 'support_email_worker_token');
   select vault.create_secret('<random>', 'notification_worker_token');
   ```
   `push_token_key` is created by its migration.
5. **Edge secrets** (`npx supabase secrets set … --project-ref <prod ref>`),
   names from `ops/secret_inventory.json`; production values only, never the
   test project's.
6. **Edge Functions:** `npx supabase functions deploy --project-ref <prod ref>`
   (all functions; `config.toml` sets which skip JWT verification).
7. **Kill switches stay off** until the smoke test passes:
   `NOTIFICATION_PUSH_ENABLED` unset, billing runtime off, publication
   runtime off (`ops/pub02_*`).

## Phase 4 — addresses and hosting

1. Fill in the production project ref: `ops/environments.json`
   (`supabaseProjectRef`), `PRODUCTION_REF` in `firebase.json` and
   `public-site/apphosting.production.yaml`, and the publishable key there.
2. Firebase Hosting: `npx firebase-tools hosting:sites:create teamzoneapp-production`.
   Connect `test.teamzoneapp.se` to the existing site `teamzoneapp-b02a2`
   (test); add the test origin to the test project's Supabase Auth redirect
   URLs and `TEAMZONE_EXTRA_WEB_ORIGINS`. Then move `app.teamzoneapp.se` to
   `teamzoneapp-production`. DNS records in Netlify DNS.
3. App Hosting: create backend `teamzoneapp-public-production` (same region
   as the test backend, root `/public-site`) with environment name
   `production`, and its three `teamzoneapp-production-*` secrets
   (`npx firebase-tools apphosting:secrets:set <name>`). Connect
   `teamzoneapp.se` (and `www`) and `public.teamzoneapp.se` to it, and
   `test-public.teamzoneapp.se` to the test backend; then set `PUBLIC_ORIGIN`
   and `PUBLIC_SITE_ORIGINS` in `apphosting.yaml` to the test addresses.
   Add the new hostnames to the Turnstile widget.
4. Functions: add `TEAMZONE_PRODUCTION_SUPABASE_URL` to
   `firebase-functions/.env.teamzoneapp-b02a2`, set the secret
   `TEAMZONE_PRODUCTION_SUPABASE_ANON_KEY`, deploy functions.

## Phase 5 — apps

- Web: `flutter build web --release --output build/web-production` with the
  production `SUPABASE_URL` / publishable key and `TEAMZONE_ENV=production`,
  then `npx firebase-tools deploy --only hosting:production`.
- Android: `docs/operations/android_release.md` (upload key, Play App
  Signing, internal testing track first).
- iOS: `docs/operations/ios_release.md` (needs a Mac).

## Phase 6 — smoke test and promotion

Per `xops_release_runbook.md`: anonymous, authenticated, tenant isolation,
Auth, Data, Storage, Realtime and Edge checks; then the pilot cohort (Thomas
club, 48 stable hours) before wider onboarding. Switch on push
(`push_notifications.md`) and other integrations one at a time, each with its
own kill switch.
