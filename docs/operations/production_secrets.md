# Production secrets (phase 3, steps 4–7)

Project `zfxcblgnemuenaqjkaic` (Teamzone, eu-north-1). Names come from
`ops/secret_inventory.json`; values are made by the product owner and never
written here, in chat or in the repository. Every value is new for
production — never the test project's.

Random values: `openssl rand -hex 32` (or the password manager's generator,
64 characters, **only a–z, A–Z and 0–9**). A worker token travels in an HTTP
header from the database: a letter such as å, ä, ö or § is encoded on the way
and the worker answers 401 even though Vault and Edge hold the same value
(found 2026-11-03). Keep each one in the password manager
under "TeamZone production".

## 1. Vault (SQL editor in the production project)

Before this, the cron jobs run every minute and stop quietly, since the
workers return when a Vault value is missing.

```sql
select vault.create_secret('https://zfxcblgnemuenaqjkaic.supabase.co', 'project_url');
select vault.create_secret('<random A>', 'support_email_worker_token');
select vault.create_secret('<random B>', 'notification_worker_token');
select vault.create_secret('https://teamzoneapp.se', 'public_site_worker_url');
select vault.create_secret('<random C>', 'public_site_worker_token');
```

`push_token_key` already exists (made by migration 20261023090000).

Check (names only): `select name from vault.secrets order by name;` gives
six names.

## 2. Edge Function secrets (Dashboard → Edge Functions → Secrets)

Already set by Supabase, nothing to do: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_PUBLISHABLE_KEYS`,
`SUPABASE_SECRET_KEYS`. Check that they are listed.

Set now:

| Name | Value |
|---|---|
| `TEAMZONE_ENV` | `production` |
| `SUPPORT_WORKER_TOKEN` | the same as `<random A>` |
| `NOTIFICATION_WORKER_TOKEN` | the same as `<random B>` |
| `SUPPORT_EMAIL_FROM` | `TeamZone <support@teamzoneapp.se>` once that address works |
| `SUPPORT_PORTAL_URL` | `https://app.teamzoneapp.se/support` |
| `CONTACT_REPLY_SECRET` | a new random value |
| `CONTACT_EMAIL_FROM_ADDRESS` | `klubbsajt@teamzoneapp.se` |

Set when the service is ready (the function stays closed until then):

| Name | When |
|---|---|
| `RESEND_API_KEY` | a production key in Resend, sending from teamzoneapp.se (the same step as SMTP) |
| `RESEND_INBOUND_WEBHOOK_SECRET` | from the inbound webhook in Resend, when club-site replies go live |
| `FCM_SERVICE_ACCOUNT_JSON` | a service account for the production Firebase app, when push goes live |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SIGNING_SECRET` | live keys, when Tacticsboard billing is built (a restricted key is enough) |
| `BILLING_WEB_ORIGIN` | only for the clubs' `billing-checkout`. Tacticsboard's `tacticsboard-billing` allows `https://webtools.teamzoneapp.se` in code and needs nothing here |
| `OBSERVABILITY_BRIDGE_URL`, `OBSERVABILITY_BRIDGE_TOKEN` | when the production monitor is set up |

Never set on production:

- `TEAMZONE_EXTRA_WEB_ORIGINS`: local and test origins only.
- `NOTIFICATION_PUSH_ENABLED`, `BILLING_RUNTIME_ENABLED`: the kill switches
  stay unset until the smoke test passes (phase 6).

## 3. Functions

After the secrets above, deploy every function to production (does not
change the linked test project):

```
npx supabase functions deploy --project-ref zfxcblgnemuenaqjkaic
```

`config.toml` decides which functions skip JWT verification.
