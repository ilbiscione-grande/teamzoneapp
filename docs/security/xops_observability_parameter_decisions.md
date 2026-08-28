# X-OPS observability and release parameter decisions

Approved by product owner: 2026-08-22  
Scope: TeamzoneApp v1, Sweden-first greenfield release

## PAR-OPS-03 — compatibility, canary and key retirement

- The current `hgcshgunvooyudvrcpig` / `teamzoneapp-b02a2` environment remains
  the audit/pilot environment. Production requires separately provisioned
  Supabase and Firebase projects and an explicit promotion approval.
- Thomas club is the first canary for at least 48 stable hours.
- Production cohorts progress 5 percent, 25 percent, then 100 percent, with at
  least 24 stable hours per stage.
- Promotion requires zero open P0/P1 defects or tenant/authorization deviations
  and passing Auth, Data API, Storage, Realtime and Edge smoke checks.
- Critical integration kill switches must be executable within 15 minutes.
- Additive schema compatibility lasts at least 30 days or two released client
  versions, whichever is longer.
- Old credentials may be retired only after at least seven stable days and 500
  verified authenticated operations across the required service matrix without
  fallback. Rotation and retirement remain separately approved secure actions.
- Roll-forward/replay is primary after new facts exist; rollback never discards
  accepted domain facts.

## PAR-OPS-05 — providers, retention and alerts

- Supabase Logs covers Database, Auth, Storage, Realtime and Edge Functions.
- Firebase Crashlytics covers Android and iOS. Google Analytics and automatic
  behavioral breadcrumbs remain disabled while PAR-PRIV-05 is open.
- Google Cloud Logging/Error Reporting covers Flutter web and public web.
- No additional external telemetry provider is used in v1.
- Telemetry is technical and sanitized at source. E-mail, free text, sports or
  health data, minors' data, tokens, headers and payload bodies are forbidden.
- Error/crash retention is 30 days. Performance retention is 14 days.
- A P0 alert is immediate. A critical flow alert triggers at 5 percent failures
  over five minutes for Auth, checkout, messaging or critical commands.
- The product owner is primary on-call owner until a named operations owner is
  approved. Billing, publication, notification and contact have independent
  fail-closed kill switches.

These decisions authorize implementation of the observability/release controls;
they do not themselves authorize production provisioning, traffic promotion or
credential retirement.
