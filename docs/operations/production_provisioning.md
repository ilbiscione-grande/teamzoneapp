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

Done:
- The web sign-in callback follows the origin the app runs on.
- Links to the public site use the configured `PUBLIC_SITE_URL`.
- Edge Functions allow extra origins via `TEAMZONE_EXTRA_WEB_ORIGINS`.

Still to do before production:
- `firebase.json`: one Hosting site per environment (`app` and `test`
  targets), each with its own CSP `connect-src` (its Supabase URL).
- `firebase-functions`: the critical-flow monitor calls the test project's
  URL; give it one target per environment.
- `public-site`: an `apphosting.production.yaml` (or a second backend) with the
  production `SUPABASE_URL`, `PUBLIC_ORIGIN` and secrets.
- Android: a test build with application id `com.teamzone.teamzone.test`
  registered in Firebase, so Crashlytics keeps test and production apart.

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

1. Firebase Hosting: add a site for test, deploy the test build there, connect
   `test.teamzoneapp.se`; then connect `app.teamzoneapp.se` to the production
   site. DNS records in Netlify DNS.
2. App Hosting: connect `test-public.teamzoneapp.se` to the test backend and
   `teamzoneapp.se` (and `www`) to the production backend.
3. Update `ops/environments.json` with the production project ref.

## Phase 5 — apps

- Web: build with the production `SUPABASE_URL` / publishable key and
  `TEAMZONE_ENV=production`, deploy to the production site.
- Android: `docs/operations/android_release.md` (upload key, Play App
  Signing, internal testing track first).
- iOS: `docs/operations/ios_release.md` (needs a Mac).

## Phase 6 — smoke test and promotion

Per `xops_release_runbook.md`: anonymous, authenticated, tenant isolation,
Auth, Data, Storage, Realtime and Edge checks; then the pilot cohort (Thomas
club, 48 stable hours) before wider onboarding. Switch on push
(`push_notifications.md`) and other integrations one at a time, each with its
own kill switch.
