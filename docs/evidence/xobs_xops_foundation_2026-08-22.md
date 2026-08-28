# X-OBS-01 / X-OPS-01 foundation evidence — 2026-08-22

## Implemented

- Provider-neutral Flutter observability boundary with structured severity,
  release, environment and correlation ID fields.
- Source-level allowlist/redaction that rejects payloads, e-mail addresses,
  arbitrary dimensions and raw exceptions/stack traces.
- Global Flutter framework and async-zone error capture through that boundary.
- Shared Edge Function correlation/logging helper and response header helper,
  wired into all four deployed billing/worker handlers.
- Fail-closed client integration switches for billing, notifications and public
  contact; billing also retains its existing server-side runtime switch.
- Versioned audit/production environment manifest and names-only secret
  inventory. Production infrastructure remains explicitly `not_provisioned`.
- Canary, smoke, rollback/roll-forward and key-rotation runbooks.

## Verification

- `flutter analyze`: no issues.
- `flutter test`: 60/60 passed.
- New OBS/OPS contract tests verify redaction, fail-closed defaults and that
  operations manifests contain no secret values. The extended Edge contract
  also verifies correlation propagation and absence of direct handler console
  logging across all four deployed handlers.
- Linked TeamzoneApp Supabase `db lint --level warning`: completed read-only.
  It reports four pre-existing PL/pgSQL hygiene warnings (one shadowed/unused
  event loop variable and three unused idempotency parameters); no change was
  made to the database in this pass.
- Current Supabase documentation/changelog was checked before implementation.
  The operations policy avoids the retiring Management API `logs.all` endpoint
  and keeps secret values in provider secret stores only.

## Remaining release gates

X-OBS-01 and X-OPS-01 remain partially complete until PAR-OPS-03 and
PAR-OPS-05 freeze the compatibility window, canary cohort, traffic threshold,
telemetry/crash provider, data region, retention, alert thresholds and on-call
ownership. No provider telemetry export, production provisioning, traffic
promotion, key rotation or key retirement was performed.

The four advisor warnings should be resolved and the linked lint rerun before
the production smoke gate. Any key rotation still requires a separately
approved secure change window and exact target.

Docker/Podman was unavailable, so the Supabase local runtime could not start.
A temporary Deno 2.9.5 runner instead applied canonical formatting and
successfully type-checked all four handlers plus their shared observability
module.

## Approved Edge release

The product owner explicitly approved the Edge deploy on 2026-08-22. The exact
four-function set was deployed to the greenfield TeamzoneApp project
`hgcshgunvooyudvrcpig`:

- `billing-checkout` version 11, active, JWT verification enabled;
- `stripe-webhook` version 10, active, JWT verification disabled as required
  for Stripe-signed ingress;
- `notification-worker` version 10, active, JWT verification enabled;
- `message-retention-worker` version 10, active, JWT verification enabled.

Read-only post-deploy smoke passed: billing exact-origin preflight returned 204
with the expected CORS allowlist and `x-correlation-id`; unsigned webhook GET
returned 405 with `x-correlation-id`; both worker GETs were rejected by the
gateway with 401 before execution. No queue, retention, Stripe-event or database
write was triggered by the smoke checks. Existing secret values were unchanged.

Advisor remediation review found that the event warning is a harmless loop
variable shadowing issue, while the three messaging/contact warnings expose
idempotency parameters that are accepted but not consumed. Those three are
behavioral command-contract work and must not be hidden by renaming variables;
they require a tested database migration before the warnings can be closed.

The local migration `20260822120244_xobs_command_idempotency.sql` now implements
deduplicated replay for thread read, thread mute and contact-request decisions,
including the expired-decision path. The focused OBS/OPS suite passes 5/5,
Flutter analysis is clean, and linked `supabase db push --dry-run` confirms that
this is the only pending migration. It has not been applied to live. The
separate harmless event loop-variable warning remains for a later cleanup so
this behavioral migration stays narrowly scoped.

The product owner then approved the live database step. Migration
`20260822120244` was applied to `hgcshgunvooyudvrcpig`; local and remote history
match. Linked lint confirms all three unused-idempotency warnings are gone and
only the separate event loop-variable warning remains. Hosted rollback test
`supabase/tests/xobs_idempotency_rollback.sql` passed read, mute and contact
replay with one deduplication row per key, then ended with `ROLLBACK`.

## Parameter approval

The product owner approved PAR-OPS-03 and PAR-OPS-05 on 2026-08-22. Frozen
values are recorded in `docs/security/xops_observability_parameter_decisions.md`
and represented by machine-readable `ops/observability_policy.json`. Google
Analytics remains disabled; no behavioral telemetry was authorized. External
Firebase/Google Cloud alert activation and receipt, production provisioning,
timed rollback and traffic/key-retirement thresholds still require operational
evidence.

## Google Cloud alert activation

- Google Cloud Monitoring email channel `TeamZone product owner` was created in
  audit project `teamzoneapp-b02a2` for `teamzone.mobileapp@gmail.com`.
- Enabled critical log-based policy `P0 audit: Google Cloud error log`, policy
  ID `10343060542624461161`, with project-scoped filter `severity>=ERROR`.
- The first matching log opens an incident immediately. Repeated notifications
  are limited to one per five minutes and incidents autoclose after 30 minutes
  without another match.
- The policy documentation explicitly requires sanitized logs and forbids user
  data and payloads. A controlled `teamzone.alert.audit_probe` entry was accepted
  by Cloud Logging with severity `ERROR` (`Created log entry.`). Delivery to
  `teamzone.mobileapp@gmail.com` was manually confirmed on 2026-08-22, verifying
  the complete Logging -> Monitoring -> email path.

## Critical-flow ratio foundation

- Local migration `20260822181735_xobs_critical_flow_metrics.sql` adds private,
  minute-bucketed counters for `auth`, `checkout`, `messaging` and
  `critical_commands`. Only aggregate success/failure counts are stored.
- The five-minute evaluator marks a flow breached at 5.00 percent or higher and
  the counters have a 30-day purge boundary. Public, anon and authenticated
  access is revoked; writes and reads require `service_role`.
- Checkout creation now records success/failure through the shared sanitized
  Edge boundary. `critical-flow-monitor` evaluates all four ratios and emits an
  ERROR aggregate containing only flow, attempts, rate and window.
- The product owner approved the live database and two-function release.
  Migration `20260822181735` was applied to the greenfield TeamzoneApp project
  `hgcshgunvooyudvrcpig`; local and remote history match. The first attempt was
  transactionally rejected because an optional evidence insert referenced a
  table absent from the greenfield schema. That insert was removed while the
  migration was still unapplied, and the corrected migration then succeeded.
- Hosted rollback test `supabase/tests/xobs_critical_flow_ratio.sql` passed the
  5/1 checkout ratio (16.67 percent, breached), five-minute expiry, invalid-flow
  rejection and authenticated-role denial, then ended with `ROLLBACK`.
- `billing-checkout` version 12 and `critical-flow-monitor` version 1 are active
  with JWT verification enabled. The product owner subsequently approved the
  Supabase-to-Google-Cloud bridge. `criticalFlowAlertBridge` is deployed as a
  Node.js 22 generation-2 function in `europe-west1`, protected by a shared
  48-byte random token stored separately in Firebase Secret Manager and
  Supabase secrets. The bridge accepts only the four approved flow names,
  attempts, a rate of at least 5 percent and the fixed five-minute window.
- `critical-flow-monitor` version 7 is active with JWT verification enabled and
  its runtime switch enabled (Supabase secret rotations incremented the hosted
  function version during this release).
  GET and tokenless POST bridge probes return 405 and 401. An authorized,
  sanitized checkout aggregate returned 202 and wrote a Google Cloud ERROR
  event. Delivery of the resulting alert email to
  `teamzone.mobileapp@gmail.com` was manually confirmed by the product owner on
  2026-08-22, verifying the complete Supabase aggregate -> protected Firebase
  bridge -> Cloud Logging -> Monitoring -> email path. Firebase Artifact
  Registry removes function images older than one day.
- Firebase function `runCriticalFlowMonitor` is deployed as a Node.js 22
  generation-2 scheduled function in `europe-west1`, running every five minutes
  in `Etc/UTC`. It calls the JWT-protected Supabase monitor with the greenfield
  project's publishable key stored in Firebase Secret Manager; no service-role
  key is exported. The initial legacy anon-JWT was rejected by the current Edge
  gateway with a sanitized 401 and was replaced after a direct publishable-key
  probe returned 200. Cloud Scheduler then reported `Success` for the ordinary
  23:52 execution and scheduled the next run for 23:57. Secure scheduling and
  the end-to-end scheduled monitor invocation are therefore verified.
- Auth, messaging and critical-command producers remain the X-OBS gates.

## Server-controlled command producers (local release candidate)

- New authenticated Edge handler `critical-flow-command` exposes a frozen RPC
  allowlist only. It forwards the caller JWT to the existing `api` command,
  records the aggregate result with a service client and returns a neutral
  command error. Parameters, payloads and database error messages are never
  logged.
- Flutter messaging mutations plus match, economy and board commands now use a
  shared `measuredRpc` boundary. Read-only queries remain direct and are not
  counted as critical attempts.
- Focused X-OBS/X-OPS contracts pass 11/11 and verify the allowlist, JWT
  forwarding, counter call, absence of parameter logging and all four client
  integrations. Diff/privacy checks pass. The targeted Flutter analyzer began
  normally but stalled without diagnostics and was stopped after 90 seconds;
  compilation is therefore not claimed from that command.
- This producer candidate is local only. `critical-flow-command` has not been
  deployed and no hosted client was rebuilt. Auth measurement remains a
  separate architecture gate because failed sign-ins do not have a trusted
  authenticated client identity.

## Server-controlled command producer release — 2026-08-23

- The product owner approved the producer release. `critical-flow-command`
  version 1 is active in greenfield project `hgcshgunvooyudvrcpig` with JWT
  verification enabled. A tokenless POST is rejected by the gateway with 401.
- Flutter web release compilation completed successfully in 217.3 seconds for
  the audit environment with the greenfield publishable key and existing
  billing/notification/contact switches enabled. Firebase Hosting deployment
  completed and `app.teamzoneapp.se` returns 200; its served `main.dart.js`
  contains the `critical-flow-command` client marker.
- Focused contracts remain 11/11. A real authenticated messaging mutation and
  critical command, followed by ratio-counter inspection, remain the live
  producer receipt gate. Auth measurement remains separately unresolved.

## Authenticated messaging producer receipt — 2026-08-23

- The first hosted browser attempt exposed a web-only gateway defect: the
  authenticated command handler did not answer the CORS `OPTIONS` preflight.
  The handler now returns the frozen CORS allowlist for `POST, OPTIONS`; a live
  preflight from `app.teamzoneapp.se` returned 200 with the expected headers.
- The next authenticated attempt completed `create_thread`, `send_message` and
  `mark_thread_read`, but sanitized logs showed the aggregate counter rejected
  with PostgreSQL code `42501`. No user, tenant, payload or backend message was
  logged.
- Root cause was an obsolete second authorization check against the legacy
  `request.jwt.claim.role` setting. Current opaque `sb_secret_*` keys map to the
  `service_role` database role but do not supply that legacy JWT claim. Migration
  `20260822223830_xobs_secret_key_counter_authorization.sql` removes only that
  redundant claim check; `EXECUTE` remains revoked from PUBLIC, anon and
  authenticated and granted only to `service_role`.
- The product owner approved the migration. It was applied to greenfield project
  `hgcshgunvooyudvrcpig`, and local/remote migration history matches. Focused
  X-OBS/X-OPS contracts pass 11/11.
- A fresh authenticated browser flow at 00:42 local time produced exactly three
  successful messaging outcomes and zero failed outcomes. Edge logs correlate
  them to `create_thread`, `send_message` and `mark_thread_read`, with no new
  `observability.counter.failed` marker. The live messaging producer receipt is
  therefore complete. A real critical-command receipt and auth measurement
  remain separate X-OBS gates.

## Critical command and auth producer release — 2026-08-23

- Repeated `freeze_match_roster` attempts without an accepted call-up reached
  the gateway and were correctly counted as failed critical commands. The
  domain precondition is now returned as the stable neutral code
  `accepted_callups_required`, and the hosted UI explains the required call-up
  instead of presenting it as a connection failure.
- After an accepted call-up existed, a real authenticated roster freeze
  succeeded. The private counter recorded `critical_commands: 1 succeeded,
  0 failed` for the success minute, completing the critical-command producer
  receipt without starting the match or changing its score.
- A server-controlled password sign-in handler now performs the existing
  Supabase password exchange, records only the aggregate auth outcome and
  returns only the refresh token needed to establish the client session.
  Passwords, email addresses, payloads and raw Auth errors are never logged.
- The handler is deployed without platform JWT verification because callers are
  unauthenticated by definition. It enforces the exact hosted web origin,
  permits native calls without an Origin header, sends `Cache-Control: no-store`
  and retains Supabase Auth's own password endpoint and rate limits. Live probes
  returned 200 for `app.teamzoneapp.se`, 403 for a foreign origin, and the
  critical gateway still rejects a tokenless command with 401.
- Focused contracts pass 12/12 and targeted Flutter analysis is clean. The
  release web build completed in 212.1 seconds and Firebase Hosting deployment
  succeeded. A cache-busted `app.teamzoneapp.se` fetch returned 200/no-cache and
  contains the auth boundary, critical gateway and accepted-callup guidance.
  One real sign-out/sign-in and private auth-counter inspection remain before
  X-OBS-01 can be closed.

## X-OBS-01 closure — 2026-08-23

- The first hosted auth response was blocked client-side because the CORS
  preflight allowlist omitted the SDK's `authorization` header. The handler was
  corrected and redeployed; a live preflight with the complete SDK header set
  returned 200, exact origin and `Cache-Control: no-store`.
- A real sign-out/sign-in completed successfully in the hosted application.
  The private auth bucket recorded two successful outcomes and zero failed
  outcomes for the minute (the first server-side authentication had succeeded
  before its response was blocked by CORS; the retry also succeeded).
- Sanitized Edge logs contain only `auth.sign_in.succeeded`, component, result,
  deployment metadata and generated correlation IDs. No email address,
  password, token, payload or raw Auth error is present.
- Auth, checkout, messaging and critical-command producers now all have live
  receipts. X-OBS-01 is complete. X-OPS-01 remains separately in progress for
  production provisioning and a timed rollback exercise.

## Android Crashlytics foundation

- Existing Firebase Android app `com.teamzone.teamzone` was reused in project
  `teamzoneapp-b02a2`; no duplicate app was created.
- Pinned `firebase_core 4.13.0` and `firebase_crashlytics 5.2.7`, Google Services
  plugin 4.5.0 and Crashlytics Gradle plugin 3.0.7 are configured.
- FlutterFire generated Android configuration. Google Analytics was not added
  or enabled.
- Crash collection is Android-only and disabled in local builds. Reports contain
  only operation, generated correlation ID and sanitized runtime type; raw error
  messages and stack traces are not sent.
- Focused OBS/OPS tests pass 8/8, Flutter analysis is clean and an opt-in audit
  probe APK builds successfully at
  `build/app/outputs/flutter-apk/teamzone-crashlytics-audit-probe.apk`.
- The probe was installed and started on a Samsung Galaxy S25 (`SM-S931B`) over
  wireless ADB. Device logs confirm successful Firebase initialization and
  `FirebaseCrashlytics 20.1.0` initialization for `com.teamzone.teamzone`.
- One sanitized non-fatal `crashlytics.audit_probe` report was submitted on
  startup. Firebase Crashlytics receipt was manually confirmed on 2026-08-22 as
  issue `907ee8b2f446697adeb635a1fab7ff90`, attributed to
  `FirebaseCrashReporter.recordSanitized` with the sanitized error text
  `Bad state: sanitized_FlutterError`; no raw backend error was exposed.
