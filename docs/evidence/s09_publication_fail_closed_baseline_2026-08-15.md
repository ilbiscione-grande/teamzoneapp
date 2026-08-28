# S09 publication fail-closed baseline

Date: 2026-08-15  
Target: greenfield TeamzoneApp only

## Initial gate result

The S09 slice requires all named P0 parameters before contract freeze:

- `PAR-PRIV-02`: initially open; approved 2026-08-15.
- `PAR-PRIV-03`: approved for all roles; contact retention/safeguarding alone
  does not authorize a public contact endpoint.
- `PAR-API-01`: initially open; approved 2026-08-15.
- `PAR-OPS-01`: initially open; approved 2026-08-15.
- `PAR-OPS-02`: initially open; approved 2026-08-15.

## Authorized preparation

S09 may create only a closed security boundary:

- dedicated `public_api` schema;
- revoked default table, sequence and function privileges;
- no schema usage or object execute/select grant for `anon`;
- an internal, disabled kill-switch state that cannot enable publishing;
- negative verification proving that no new anonymous surface exists.

The preparation does not create publication settings, consents, projections,
contact submissions, public Storage buckets, Next.js routes, DNS or hosting.
Those objects would freeze unresolved policy and are therefore prohibited.

## Deployed verification

`20260815105232_s09_closed_public_api_boundary.sql` is deployed to TeamzoneApp.
`20260815105423_s09_boundary_advisor_hardening.sql` covers the runtime-state
actor foreign key reported by the performance advisor.
Hosted checks confirm:

- `anon` schema usage: false;
- authenticated schema usage: false;
- anon runtime-state select: false;
- publication enabled: false;
- public API tables/routines: 0/0;
- an attempted `enabled=true` update is rejected by a database constraint.

The security advisor reports no S09 finding. Its only warning is the existing
project-level leaked-password-protection setting. The focused S09 contract suite
initially passed 2/2 tests.

## P0 decisions approved

On 2026-08-15 the product owner approved PAR-PRIV-02, PAR-API-01, PAR-OPS-01
and PAR-OPS-02. The exact policy is frozen in
`docs/security/s09_publication_parameter_decisions.md`. This unblocks S09
dataspec/API implementation but does not itself authorize Firebase project
creation, Blaze billing, DNS mutation or production release.

## Consent/projection foundation deployed

`20260815164018_s09_publication_consent_projection.sql` and
`20260815164233_s09_publication_fk_indexes.sql` are deployed to the new
TeamzoneApp project. They add:

- verified age bands without storing a date of birth;
- separate consent for name, profile media, position and individual statistics;
- optional guardian approval fields, maximum one-season/366-day validity and
  explicit withdrawal state;
- private-by-default club/team publication settings with opaque public IDs and
  normalized slugs;
- an internal retryable projection/invalidation queue;
- private club/team projection tables with no client grant.

Hosted verification after deployment confirms seven expected tables, no
`public_api` schema usage or projection read privilege for `anon` or
`authenticated`, `publication_enabled=false`, and the immutable
`CHECK (enabled = false)` runtime constraint. Database lint has no new S09
warning. The performance advisor's three new composite-FK findings were covered
by the second migration; older findings are outside this change.

## Authenticated consent commands deployed

`20260815164950_s09_consent_commands.sql` is deployed. Its four authenticated
API commands provide verified age-band assertion, subject consent, separate
guardian approval and consent withdrawal. Age assertions require the existing
`club.memberships.manage` capability. Consent can only be initiated by the
subject's linked account; guardian approval requires both the guardian's linked
account and an active verified guardian relation. Through age 15 the initial
state is `pending_guardian`; age 16+ becomes `active` from the subject's own
approval. Withdrawal is audited and atomically creates a retryable person
projection-removal job. Every command is idempotent and uses neutral not-found
authorization failures.

A hosted transactional matrix passed and rolled back all fixtures. It proved
minor pending state, outsider denial, verified guardian activation, duplicate
guardian-command replay, direct 16+ activation, subject withdrawal, duplicate
withdrawal replay, exactly one removal job and an unchanged disabled runtime.
The security advisor reports no S09 finding; the only project warning remains
leaked-password protection. New indexes are reported only as unused because
the feature has no production traffic yet.

## Draft projection and invalidation worker deployed

`20260815165738_s09_publication_settings_worker.sql` is deployed. Authorized
club administrators can configure only `private` or `draft` club/team settings;
there is deliberately no published state. Configuration is revision checked,
idempotent and audited, and creates a rebuild or removal job.

The worker contract is two-phase and restricted to `service_role`:

1. claim with `FOR UPDATE SKIP LOCKED` and bounded attempts;
2. build/remove the private projection;
3. enter `awaiting_invalidation` with exact affected paths;
4. complete only after an explicit successful cache-invalidation receipt.

Failed projection or CDN work enters exponential bounded backoff. Removal is
fail-safe: the private projection is deleted before cache invalidation, so a CDN
failure cannot restore database visibility. No profile-media path is projected;
the existing private message-file bucket is intentionally not reused.

The hosted rollback matrix passed draft club/team build, worker claim,
projection creation, successful invalidation, failed invalidation, simulated
backoff expiry, retry completion and a private transition with CDN failure. The
last case proved the team projection remained absent while the job stayed
retryable. All fixtures rolled back. Hosted privilege checks confirm worker
execute false for `anon`/`authenticated`, true for `service_role`; configuration
false for `anon`, true for `authenticated`; `anon` still lacks `public_api`
usage; runtime remains false. Database lint has no new warning and the security
advisor still reports only the project-level leaked-password setting.

## Server-only public API/contact boundary deployed

`20260815170442_s09_public_api_contact_boundary.sql` is deployed. It adds
private event/news/media projections and the approved server-side endpoint
allowlist: club search, club/team lookup, team events, publications and contact.
Every endpoint is executable only by `service_role`; neither `anon` nor
`authenticated` can call it or read `public_api` directly. The future Next.js
server/Edge boundary must hash IP addresses with a secret before invoking these
functions and must never expose its Supabase secret.

The database enforces maximum page sizes (10 search, 20 lists), three-character
minimum search, prefix-only search and 60/min read, 20/min search and 5/hour/IP/
club contact limits. Only a 32-byte hash is stored. Contact additionally requires
a server-verified CAPTCHA assertion, validates strict field lengths, returns no
internal recipient and retains message content for 30 days. Pseudonymized
contact abuse counters expire after 90 days, matching approved PAR-PRIV-03.
Retention erases sender, email, subject and body rather than retaining a
permanent inbox.

Because runtime remains structurally false, all read/contact functions return a
neutral unavailable result before reading projections or accepting contact.
No Edge Function or public route was deployed. A hosted rollback matrix passed
the exact 60/20/5 limits, retention erasure, service-role-only grants, anon
denial and fail-closed results. All fixtures rolled back. Database lint has no
new warning; advisor output contains only expected unused-index info before
traffic and the existing leaked-password-protection warning.

## Local Next.js server adapter implemented

`public-site/` now contains a local Next.js 16 App Router foundation for
`/api/public/v1`. It implements the approved club search, club/team lookup,
team-event, publication and contact HTTP routes. Every response is `no-store`;
database errors map to neutral Swedish responses. The Supabase secret is read
only from `SUPABASE_SECRET_KEY` in server modules and no `NEXT_PUBLIC_*` secret
exists.

The adapter derives the client address behind an explicitly configured number
of trusted proxy hops, HMAC-SHA256 hashes it before RPC, requires exact same
origin for contact POST, validates JSON/UUIDs and verifies CAPTCHA through a
configured HTTPS provider with a five-second timeout. Only the CAPTCHA result
and an HMAC assertion reach the database; its raw token does not. CSP, frame,
content-type, referrer and permissions headers are configured. The root page is
non-indexed and states that publication is inactive.

Six isolated security tests pass: spoofed leading X-Forwarded-For, missing-IP
fail-close, deterministic non-reversible HMAC shape, exact-origin contact
enforcement, and Turnstile hostname/action binding including a fail-closed
wrong-action case. Package versions are pinned and `package-lock.json` was
generated by a clean installation using the project-local npm cache. TypeScript
passes with no error and the Next 16.3.1 production build passes all static and
dynamic routes. Generated package/build/cache directories are gitignored. No
adapter was deployed and no secret was configured.

## Public page foundation implemented

The canonical local routes `/{club_slug}` and `/{club_slug}/{team_slug}` now
render responsive server-side club/team pages from the service-only adapter.
They contain no sample person or club data: runtime-off, missing configuration,
unknown routes and backend errors all render an honest non-public state. The
club page has an accessible contact form with exact approved field limits and
retention copy. Cloudflare Turnstile is selected and integrated through an
explicit managed widget. The client enables submission only after receiving a
token; the server independently verifies it and requires the canonical
`teamzoneapp.se` hostname plus the `contact` action. Missing keys keep the form
disabled and never bypass verification.

The production Turnstile widget `TeamzoneApp public contact` was created in
Cloudflare with Managed mode, `teamzoneapp.se` and `public.teamzoneapp.se` as
its approved hostnames and
pre-clearance disabled. Its site key and secret are present only in the
gitignored local environment; no credential value is recorded in evidence or
source control. Hosted Firebase runtime secrets are backend-scoped.

Firebase project `teamzoneapp-b02a2` was verified as the rebuild project; its
registered Android app retains `com.teamzone.teamzone`. Blaze is active. A
monthly alerts-only budget named `TeamzoneApp monthly guardrail` is scoped only
to this project and all services, with actual-spend email thresholds at SEK 50,
90 and 100 for billing users/admins and project owners. The budget is not an
automatic spending cap.

App Hosting uses `europe-west4` and ZIP source deployment to avoid creating a
GitHub dependency. Backend `teamzoneapp-public` is deployed with zero minimum
and two maximum instances. Its three server-only Secret Manager entries are
granted through Firebase's backend-specific access command. Temporary custom
domain `public.teamzoneapp.se` is connected; apex, `www` and `webtools` remain
unchanged.

Rollout `build-2026-08-16-000` is current. The deployment exposed and fixed a
Next.js dynamic-route parameter collision without changing external API paths.
A PowerShell-created archive was rejected while GCS unpacked the source; the
same filtered source packaged with standard `tar` passed and deployed. The
generated `hosted.app` URL returns the non-indexed foundation with
`Publicering är avstängd`, no club/team data and no raw backend error. Runtime
publication remains structurally false.

Hosted fail-closed HTTP smoke passed after rollout. Club search and publication
queries return neutral `503` with `no-store`; an origin-less contact mutation is
denied neutrally, while the canonical-origin request reaches schema validation
and rejects an empty body with `400`. All responses include CSP, frame denial,
content-type, permissions and referrer headers. A successful CAPTCHA/contact
submission cannot be tested on the generated hostname because the production
Turnstile widget is deliberately restricted to `teamzoneapp.se`; that test and
custom-domain CDN behavior remain behind the separate DNS/domain gate.

On 2026-08-16 the temporary custom-domain gate passed. Netlify DNS publishes
the Firebase A record, ownership TXT record and certificate-manager CNAME for
`public.teamzoneapp.se`; Firebase reports the domain connected. HTTPS returns
`200` with the expected CSP, frame denial, content-type, permissions and
referrer headers. Club search remains neutral `503` with `no-store`, invalid
publication input is rejected with `400`, and canonical-origin contact remains
neutral `503` while runtime publication is structurally false. No apex, `www`
or `webtools` DNS record was changed. A successful Turnstile/contact mutation
remains intentionally unavailable until a separately approved publication
activation supplies a real public club context.

The layout includes mobile behavior, visible focus states, semantic headings,
minimal TeamZone branding and privacy context. Search indexing remains disabled
for the entire foundation. A social card was intentionally omitted because the
site is not release-ready and no public origin is active. The clean production
build contains the two dynamic public pages and all six dynamic API routes.

## Current Supabase compatibility

Supabase's 2026 Data API change requires explicit grants for newly exposed
objects. S09 treats grants and RLS/authorization as separate required layers;
the closed baseline grants neither schema usage nor object access to `anon`.
