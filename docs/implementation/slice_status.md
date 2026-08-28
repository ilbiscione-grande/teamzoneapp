# TeamZone implementation slice status

Updated: 2026-08-22

This is the mutable execution status for the rebuild. The approved specification
under `docs/specification/source/` is an immutable snapshot and is not edited to
record implementation progress. Where the snapshot assumes migration from a
legacy database, the later product-owner decision applies: both application and
database are greenfield, with no backfill or compatibility path from Teamzone6.

## Status notation

- `[ ]` not started
- `[~]` in progress or only partly verified
- `[x]` verified and linked to evidence
- `[n/a]` superseded by an explicit decision

## Slice overview

| Slice | Status | Evidence / next gate |
|---|---|---|
| S00 | `[x]` | [Bootstrap evidence](../evidence/s00_bootstrap_2026-08-07.md) |
| S01 | `[x]` | [Implementation and audit evidence](../evidence/s01_local_implementation_2026-08-07.md) |
| S02 | `[x]` | [Roster lifecycle evidence](../evidence/s02_roster_lifecycle_2026-08-07.md) |
| S03 | `[x]` | [Event/calendar evidence](../evidence/s03_event_calendar_2026-08-08.md) |
| S04 | `[x]` | [S04 implementation and physical evidence](../evidence/s04_squad_callup_attendance_2026-08-08.md) |
| S05 | `[x]` | [Implementation, hosted and physical evidence](../evidence/s05_main_surfaces_2026-08-08.md) |
| S06 | `[x]` | [Messaging, files, moderation and retention verified](../evidence/s06_messaging_progress_2026-08-08.md) |
| S07 | `[x]` | [Hosted, client and physical Match Space evidence](../evidence/s07_match_v2_baseline_2026-08-15.md) |
| S08 | `[x]` | [Development signals evidence](../evidence/s08_development_signals_baseline_2026-08-15.md) |
| S09 | `[x]` | [Publication and custom-domain evidence](../evidence/s09_publication_fail_closed_baseline_2026-08-15.md) |
| S10 | `[~]` | PAR-BILL-02 approved 2026-08-16; entitlement foundation unlocked, checkout remains gated |
| S11 | `[ ]` | Workspaces/webtools explicitly deferred |

## Cross-cutting stabilization

| Status | Task | Current result |
|---|---|---|
| `[x]` | X-QA-01 | Shared transaction-local JWT/test UUID helpers, machine-readable S00-S10B evidence manifest, repository contract checks and hosted privilege diff are implemented. All 51 Flutter tests pass and static analysis reports no issues. |
| `[x]` | X-UX-01 | Central themes/tokens, 48 px touch targets, reduced-motion behavior, accessible loading/state components, explicit breakpoints and sv/en localization across the core client are implemented. A contract blocks untranslated Swedish app-shell literals and missing English feature keys. All 57 Flutter tests pass and analysis is clean. |
| `[x]` | X-OBS-01 | PAR-OPS-05 is approved. Sanitized logging, Android Crashlytics, 5-minute/5% ratios, monitor v7, protected Firebase/Google Cloud bridge, threshold email and five-minute Scheduler are live-verified. Checkout emits outcomes. JWT-protected command gateway and the hosted measured client are deployed for messaging plus match/economy/board commands; CORS, 401 boundary and bundle receipt pass. Authenticated messaging produced three live successes with zero failures, a real `freeze_match_roster` produced the critical-command success, and server-measured password auth produced two live successes with zero failures under exact-origin/no-store controls. All X-OBS producer receipts are complete. |
| `[~]` | X-OPS-01 | PAR-OPS-03 is approved. Environment manifests, 48-hour audit canary, staged 5/25/100 promotion, compatibility, smoke, rollback and 7-day/500-operation key-retirement gates are specified. Production provisioning and a timed rollback exercise remain separate. |

## S01 – platform foundation, identity and context

The task identifiers below preserve traceability to the approved snapshot while
recording the greenfield scope actually authorized and implemented.

| Status | Task | Current result |
|---|---|---|
| `[x]` | S01-BASE-01 | New `TeamzoneApp` Supabase project verified empty before migration; PostgreSQL version, schema and migration baseline recorded. The snapshot's Teamzone6 object-count fingerprint is intentionally outside greenfield scope. |
| `[x]` | S01-DB-01 | `core`, `internal`, `audit` and `api` created with explicit revokes, grants and privilege manifest. |
| `[x]` | S01-DB-02 | Foundational identity/context tables, tenant constraints, capability scope enforcement and RLS deployed from an empty database. |
| `[x]` | S01-DB-03 | Command deduplication, audit, provenance and invoker-to-internal command prototype verified. |
| `[x]` | S01-API-01 | `get_profile`, `get_my_contexts` and profile-preference command verified through the hosted Data API with a real JWT. |
| `[n/a]` | S01-MIG-01 | Superseded by the explicit greenfield database decision: no legacy mapping, backfill or exception queue. |
| `[x]` | S01-CLI-01 | Session bootstrap, safe unconfigured state, loading/timeout/retry, waiting room and context selection implemented and widget-tested. |
| `[x]` | S01-CLI-02 | Five stable routes and adaptive navigation implemented and tested; audit APK installed on a Galaxy S25 and login, waiting room, context selection, all routes, cold deep-link, session restore, Android back and sign-out passed. |
| `[x]` | S01-TEST-01 | Real password/JWT E2E plus hosted transactional matrix passes for player, guardian, leader, club functionary, guest, anon, unknown, super-admin claim without relation, suspended, ended and cross-club cases. |
| `[x]` | S01-TEST-02 | Empty hosted replay, transactional rollback, ACL/RLS checks, secret scan and Security/Performance Advisor checks pass. Legacy old-client regression is not applicable to the greenfield rebuild. |

## S01 closure

All S01 implementation and verification gates are complete. The audit artifact
uses an audit-only Android Debug certificate and is not a production or Play
distribution artifact.

The hosted Auth policy is recorded in
[`../security/s01_auth_policy.md`](../security/s01_auth_policy.md). The audit
project uses the strongest controls available on Free; Supabase leaked-password
protection remains an explicit production gate because it requires Pro.

This closure does not authorize a change to Teamzone6 or a production release.

## S02 – club, team and roster lifecycle

| Status | Task | Current result |
|---|---|---|
| `[x]` | S02-DB-01 | Person, tenant roster, temporal assignment, eligibility, guardian storage, invite and transfer schema deployed with composite tenant FKs. |
| `[x]` | S02-API-01 | Capability-scoped, PII-minimized roster projection deployed. |
| `[x]` | S02-CMD-01 | Idempotent create, end, invite and atomic claim commands deployed and transactionally verified. |
| `[x]` | S02-CMD-02 | Guardian invite/accept is capability-scoped and single-use; safeguarding transfer requires source, target and active guardian approval. |
| `[n/a]` | S02-MIG-01 | Superseded by the explicit greenfield database decision; no legacy backfill is permitted or required. |
| `[x]` | S02-CLI-01 | Roster list/detail, safe states, capability-adapted actions, waiting-room claim and guardian invite acceptance are implemented. |
| `[x]` | S02-TEST-01 | Claim replay/race, guardian account binding/replay, idempotency, cross-club denial, overlap, three-party minor transfer and history attribution pass in a rolled-back hosted matrix. |
| `[n/a]` | S02-REL-01 | Legacy-read rollback/cohort is not applicable to the greenfield rebuild; no production release is authorized. |

All applicable S02 gates are verified. Greenfield supersedes legacy backfill and
legacy-read rollback; this does not authorize Teamzone6 or production changes.

## S03 – event and calendar

| Status | Task | Current result |
|---|---|---|
| `[x]` | S03-DB-01 | Event, recurrence, revision, event-team, audience, location and outbox schema deployed with composite tenant FKs and exact primary-team enforcement. |
| `[x]` | S03-API-01 | Multi-context calendar and EventDetails/caller-actions are deployed and physically verified with stable opaque cursor pagination. |
| `[x]` | S03-CMD-01 | Idempotent create/revise/transition with one/forward/all scope, expected revision, audit and atomic outbox is deployed and transactionally verified. |
| `[n/a]` | S03-MIG-01 | Superseded by the explicit greenfield database decision; no legacy event backfill is permitted or required. |
| `[x]` | S03-CLI-01 | Calendar safe states, create, EventDetails, edit, cancel and complete are implemented; release APK smoke passed on Galaxy S25. |
| `[x]` | S03-TEST-01 | DST, overnight, all-day boundaries, stable cursor, stale revision, shared leader, audience-not-edit, atomic series failure and final ACL/residue gates pass. |
| `[x]` | S03-RT-01 | Scoped private club invalidation and full resync fallback are implemented; live database-to-Galaxy-S25 refresh passed without app resume or manual refresh. |

All applicable S03 gates are verified. Greenfield supersedes legacy backfill;
this does not authorize Teamzone6 or production changes. Evidence:
[S03 event/calendar evidence](../evidence/s03_event_calendar_2026-08-08.md).

## S04 – squad, callup, response and attendance

| Status | Task | Current result |
|---|---|---|
| `[x]` | S04-DB-01 | Revisioned squad/member snapshots, callup, append-only response, attendance facts/history and notification delivery schema are deployed with tenant FKs and RLS. |
| `[x]` | S04-CMD-01 | Manual/all/group/generator converge on one save-draft command; lock revalidates eligibility and stale revisions fail atomically. |
| `[x]` | S04-CMD-02 | Send/cancel/remind, explicit guardian acting-as response, single-use response tokens and all-or-nothing attendance commands are deployed. |
| `[n/a]` | S04-MIG-01 | Superseded by the explicit greenfield database decision; no preliminary/group/generated legacy mapping is permitted or required. |
| `[x]` | S04-CLI-01 | EventDetails squad/callup/attendance UI is implemented, release-built and physically verified on Xiaomi Mi 9. |
| `[x]` | S04-NOT-01 | Authenticated Edge worker v1, service-role-only claim/finish RPC, retry/dead-letter/dedupe and sanitized provider-reference hashing are deployed. Provider delivery remains safely suppressed until separately configured. |
| `[x]` | S04-TEST-01 | Hosted rollback matrix covers eligibility, stale/duplicate commands, guardian acting-as, delivery/domain separation and explicit unknown attendance; Flutter analyze and 19/19 tests pass. |
| `[n/a]` | S04-REL-01 | Superseded by greenfield; no legacy shadow comparison or write-stop exists. |

All applicable S04 gates are verified. Greenfield supersedes legacy migration
and release rows; this does not authorize Teamzone6 or production changes.

## S05 – main surfaces and responsive state

| Status | Task | Current result |
|---|---|---|
| `[x]` | S05-API-01 | Data-minimized multi-context projection is deployed with exact context validation, deduplication, explicit actions and versioned opaque cursor. |
| `[x]` | S05-CLI-01 | Home, Inbox and Statistics consume real projections; Team and Calendar retain their real S02/S03 flows. Writes keep an explicit context target. |
| `[x]` | S05-CLI-02 | Stable routes, central phone/tablet/desktop tokens, adaptive navigation, sv/en and light/dark/system are implemented. |
| `[x]` | S05-STATE-01 | Loading, safe error/retry, honest empty state and timestamped stale-cache fallback are implemented without raw backend text. |
| `[x]` | S05-TEST-01 | Hosted ACL/projection, Flutter tests, analyze, Android/web builds and authenticated Xiaomi walkthrough pass; cold Inbox deep link restored session/context after force-stop. |

S05 is closed. This does not authorize Teamzone6 changes or a production release.

## S06 – Inbox, files and notifications

| Status | Task | Current result |
|---|---|---|
| `[x]` | S06-DB-01 | Scoped thread/message/version/read/mute/block/report schema and approved retention classes deployed with RLS deny defaults. |
| `[x]` | S06-FILE-01 | Private bucket, staged/final metadata, thread-bound RLS, upload, inline thumbnails, signed download and retention worker are verified. |
| `[x]` | S06-API-01 | Shared recipient/access helper, direct/group/cross-club commands, request center, blocking and abuse boundaries are verified. |
| `[n/a]` | S06-MIG-01 | Superseded by the approved greenfield database decision; no legacy messages, settings or attachments are imported. |
| `[x]` | S06-CLI-01 | Inbox/thread/compose/send/read/mute, attachments, recall/report, requests and notification center are implemented. |
| `[x]` | S06-RT-01 | Private topic authorization and minimal thread-ID/revision invalidation are deployed. |
| `[x]` | S06-TEST-01 | Physical two-account messaging/file smoke and hosted ACL, withdrawn URL, cross-club, rate-limit, moderation and idempotency matrices pass; analyze and 27 Flutter tests pass. |
| `[x]` | S06-RET-01 | Expiry, orphan cleanup, retry-safe worker behavior and legal-hold preservation pass in a rolled-back hosted matrix. |

S06 is closed. This does not authorize Teamzone6 changes, S07 implementation or
a production release.

## S07 – Match Space v2 adapter

| Status | Task | Current result |
|---|---|---|
| `[x]` | S07-BASE-01 | Ten verified v2 RPC signatures, command/state/revision semantics and prior rollback regressions are frozen in evidence. |
| `[x]` | S07-API-01 | All ten frozen v2 mutation signatures, authorized roster-freeze and full snapshot with deterministic resync cursor are deployed. |
| `[x]` | S07-DB-01 | Event/team binding, accepted-callup roster revisions, append-only commands, fact-derived projections and configurable 2–8-period clock anchors are deployed and verified. |
| `[x]` | S07-CLI-01 | Calendar-launched Match Space supports roster freeze, visible clock/timeline, goals, generic periods, fulltime, reasoned unlock, pending and same-command retry with server-authoritative snapshot. |
| `[x]` | S07-TEST-01 | Hosted plan/live/retry/score/edit/void/KPI/fulltime/unlock/reset/roster matrix, 3×20 period rollback, 32 Flutter tests and physical Xiaomi flow pass. |
| `[x]` | S07-REL-01 | `MATCH_SPACE_V2` feature flag selects the full UI or compact read-only fallback; both read the same v2 snapshot backend. |

S07 is closed. TeamZone/live was not changed and remains out of scope.

## S08 – development, signals and Assistant Coach v1

| Status | Task | Current result |
|---|---|---|
| `[x]` | S08-DB-01 | Tenant-bound revisioned development plans/actions and versioned signal definitions are deployed. Non-raw definitions are database-constrained inactive; health/sanction schema remains blocked by PAR-METHOD-02. |
| `[x]` | S08-API-01 | Capability-scoped plan projection and deterministic AC preview expose only transparent attendance/match raw counts. |
| `[x]` | S08-CMD-01 | Idempotent audited create-plan/add-action commands enforce expected plan revision and `development.manage`. Check-in and health/sanction commands remain absent behind their gates. |
| `[n/a]` | S08-MIG-01 | Superseded by the approved greenfield database decision; no legacy development/health/signal backfill is performed. |
| `[x]` | S08-AC-01 | Deterministic raw-fact preview is deployed with explicit blocked-gate metadata; generative processing remains disabled by PAR-AI-01/02. |
| `[x]` | S08-CLI-01 | Development surface exposes raw-fact chips, disabled-feature explanation, honest states and capability-adapted team-plan/action creation with immediate reload and safe errors. |
| `[x]` | S08-TEST-01 | Three migrations deployed; direct/anon checks, authenticated rollback matrix, 35/35 Flutter tests, clean analysis, configured Xiaomi install and physical preview/plan/action walkthrough pass. |

S08 is authorized with parameter gates enforced fail-closed. No health/sanction
schema, self-rating activation, signal thresholds or generative AI may be
invented while the corresponding parameter decisions remain open.

S08 is closed for its currently authorized fail-closed scope. The gated feature
areas above remain deliberately unimplemented and do not prevent slice closure.

## S09 – publication and public web

| Status | Task | Current result |
|---|---|---|
| `[x]` | S09-DB-01 | Locked boundary, age-band/field consent, private settings/projections, consent commands and two-phase projection/cache worker are deployed and remain impossible to publish. |
| `[x]` | S09-API-01 | Service-only club/team/event/content/contact allowlist plus the deployed Next.js server adapter enforce limits, IP hashing, CAPTCHA assertion, neutral errors and retention; activation remains structurally false. |
| `[x]` | S09-WEB-01 | Canonical club/team pages and contact foundation are deployed to App Hosting `teamzoneapp-public` in `europe-west4`; Turnstile, security headers, IP-HMAC and same-origin controls are configured fail-closed. Generated hosted.app smoke shows publication inactive with no private data. |
| `[n/a]` | S09-MIG-01 | Greenfield decision: no legacy public data import exists or is permitted. |
| `[x]` | S09-TEST-01 | Hosted DB matrices, 6/6 local request/CAPTCHA tests, TypeScript, Next compilation, hosted inactive-page/API/header/origin/schema smoke and `public.teamzoneapp.se` HTTPS/CDN tests pass. Successful real contact remains correctly unavailable while publication is structurally false. |
| `[x]` | S09-REL-01 | Firebase/Blaze, SEK 100 alerts-only budget, three backend-scoped secrets, `europe-west4` App Hosting backend, rollout `build-2026-08-16-000` and connected temporary domain `public.teamzoneapp.se` are verified. Apex, `www`, `webtools` and publication activation remain unchanged/separately gated. |

S09 P0 parameters PAR-PRIV-02, PAR-PRIV-03, PAR-API-01, PAR-OPS-01 and
PAR-OPS-02 are approved as of 2026-08-15. Dataspec/API implementation is
unblocked. Firebase project creation, Blaze billing, DNS changes and production
release remain separate external actions.

## S10 – billing, entitlements and economy

PAR-BILL-01, PAR-BILL-02 and PAR-BILL-03 were approved on 2026-08-16. The entitlement foundation uses a
14-day grace period, preserves all data, becomes read-only after grace, denies
premium writes for unknown state and restores access from existing data.
Sales are web-only through Stripe Checkout; native apps contain no purchase CTA
or external purchase link. Checkout/webhook activation remains a separate pilot
release gate. Economy writes remain gated by PAR-FIN-01 and PAR-FIN-02.

| Status | Task | Current result |
|---|---|---|
| `[x]` | S10A-DB-01 | Provider-inbox, canonical billing account/subscription/items and deterministic club-entitlement projection are deployed and verified fail-closed in the greenfield project. |
| `[x]` | S10A-API-01 | Capability-scoped entitlement and published provider-neutral `se.v1` pricebook queries are deployed; server-only provider mappings and write checks remain outside the client boundary. |
| `[x]` | S10A-WEBHOOK-01 | Database commands and Edge adapters are deployed. Exact-origin CORS, checkout JWT, Stripe signature ingress and authenticated checkout/webhook processing are verified in the dedicated sandbox. |
| `[n/a]` | S10A-MIG-01 | Greenfield decision: no legacy subscriptions, plans, modules or webtool rows may be imported. |
| `[x]` | S10A-TEST-01 | Hosted rollback matrix passes active, grace, expired grace/read-only, unknown and outsider states; privilege audit passes and performance advisors report no warnings. |
| `[x]` | S10A-REL-01 | Stripe sandbox, scoped webhook/secrets, published `se.v1`, six mappings and Thomas-club pilot capability are configured. Web billing UI is deployed on valid TLS; authenticated Small checkout completed and projected `plan.small`/`base.small` write access. Runtime is enabled for the approved sandbox pilot only. |

PAR-FIN-01 and PAR-FIN-02 were approved on 2026-08-17. S10B is limited to
confidential internal cash tracking/export with SEK 10,000 dual-control and
initiator separation. PAR-FIN-03 remains closed.

| Status | Task | Current result |
|---|---|---|
| `[x]` | S10B-DB-01 | Deny-by-default scoped accounts, append-only ledger/reversal, approvals, obligations, pledge snapshots and board mandates are deployed and rollback-verified. |
| `[~]` | S10B-API-01 | Entitlement/capability-scoped account, post, approve, reverse and minimized query APIs are deployed with idempotency and SEK 10,000 dual control. Board mandate request/approve/apply/query APIs now enforce initiator separation and 2-of-2 approval. PAR-FIN-03 fee/payment/settlement commands remain absent. |
| `[n/a]` | S10B-MIG-01 | Greenfield decision: no legacy economy or board import. |
| `[x]` | S10B-CLI-01 | Responsive Economy and Board routes are deployed with neutral locks and capability-adapted API-only controls. Physical multi-account walkthroughs passed Economy posting/reversal and Board mandate grant/revoke with initiator separation and 2-of-2 approval. |
| `[x]` | S10B-TEST-01 | Hosted rollback plus physical walkthrough verify Economy entitlement denial, idempotency, high-risk posting/reversal, initiator separation, 2-of-2 approvals, direct-table denial and immutable history. Board rollback and physical walkthrough verify creator denial, one-of-two denial, grant, apply, revocation and time-derived scheduled/active/ended boundaries. Exact pilot grants and hosted client bundle are verified. PAR-FIN-03 remains closed. |
