# S10A entitlement foundation evidence

Date: 2026-08-16  
Target: new greenfield TeamzoneApp Supabase project

## Authorized scope

PAR-BILL-02 is approved with a 14-day grace period, no deletion on downgrade,
read-only/export after grace, fail-closed unknown state and restoration from
existing data after reactivation. PAR-BILL-01 and PAR-BILL-03 remain open, so
prices, checkout, payment-provider selection and commercial release are absent.

## Local implementation

Migration `20260816111500_s10a_entitlement_foundation.sql` adds:

- one environment-scoped billing account per club;
- one canonical subscription with a versioned pricebook reference;
- club-scoped subscription items;
- a signature-verified, deduplicated provider-event inbox structure;
- a deterministic entitlement projection with `write`, `read_only` or `denied`;
- a server-only recompute/write-check boundary; and
- one authenticated, relation-scoped query returning no provider identifiers.

Unknown subscription state projects no entitlement. Active/trialing and an
unexpired grace period allow writes; expired grace, read-only and ended states
preserve read access but deny premium writes. No table is directly granted to
`anon` or `authenticated`.

The rollback test `s10a_entitlement_foundation.sql` covers active, grace,
expired grace, unknown state and cross-club denial. The machine-readable
privilege contract is `s10a_expected_privileges.json`.

## Hosted verification

Migration `20260816111500_s10a_entitlement_foundation.sql` was applied after a
successful linked dry-run. The first rollback matrix exposed an expired-grace
projection attempting to use an already elapsed `expires_at`; the transaction
rolled back. Forward migration
`20260816111600_s10a_fix_expired_grace_projection.sql` corrected the projection
without changing the approved policy.

The complete hosted rollback matrix then passed for active, unexpired grace,
expired grace/read-only, unknown/fail-closed and outsider denial. The separate
privilege audit passed: all four core tables have RLS, neither client role has
direct table access, the provider inbox and recompute/write-check functions are
server-only, and only the scoped API query is executable by `authenticated`.
Local and remote migration histories match.

Supabase performance advisors returned no warnings. Security advisors returned
only the already-known project-level warning that leaked-password protection is
disabled; S10A introduced no database security-advisor finding. Enabling that
Auth setting remains a separate project configuration decision.

## Draft pricebook extension

PAR-BILL-01 was approved on 2026-08-16. Local forward migration
`20260816111700_s10a_versioned_pricebook_draft.sql` defines private, RLS-enabled
pricebook/version and plan tables and seeds the five approved plans as
`se.v1-draft`. The state is structurally non-published, checkout remains absent,
money uses integer minor units and subscriptions reference an explicit version.
The accompanying hosted rollback test verifies draft-only state, all five rows,
the ten-month annual rule and absence of direct client table privileges.
Migration `20260816111700_s10a_versioned_pricebook_draft.sql` is deployed in the
greenfield project; the full entitlement/grace regression also passes after the
new pricebook foreign key. Local and remote migration histories match.

Post-deploy performance advisors report no warnings. Security advisors remain
unchanged with only the pre-existing leaked-password-protection warning. The
pricebook remains `draft`; no published pricebook, checkout endpoint, provider
secret or commercial activation exists.

## Sales-channel decision

PAR-BILL-03 was approved on 2026-08-16 after review of the current Apple and
Google payment policies. TeamZone uses authenticated web-only Stripe Checkout
for club purchases. Native apps have no price list, checkout, external purchase
link or purchase call to action and only consume existing club entitlements.
Players and guardians never buy individual access. This decision selects the
future adapter boundary but does not configure Stripe or activate commerce.

## Local Stripe adapter foundation

The local Edge Function foundation adds authenticated `billing-checkout` and
unauthenticated-but-Stripe-signed `stripe-webhook` handlers. Both require the
explicit `BILLING_RUNTIME_ENABLED=true` kill switch; no such secret or setting
is configured. Checkout enforces exact web origin, a strict four-field request,
known non-custom plan keys, UUID idempotency and a two-step database boundary so
provider price references are never returned by the authenticated client RPC.
Stripe receives a server-selected price and the same idempotency key.

The webhook reads the raw request body before parsing and verifies
`stripe-signature` with the pinned Stripe SDK and Web Crypto provider. Invalid
signatures return `400`; disabled/unconfigured runtime returns neutral `503` so
Stripe can retry. Accepted events are intended for the server-only inbox RPC;
no entitlement is derived directly from webhook JSON.

`stripe-webhook` is explicitly configured with `verify_jwt=false`; its Stripe
signature is the authentication boundary. Checkout retains JWT verification.
Pure request-contract tests are authored, but Deno/Docker is unavailable on the
current machine, so execution and the required database RPC migration remain
before any deploy. No Edge Function, Stripe key or external provider traffic
was created.

Local migration `20260816111800_s10a_checkout_webhook_commands.sql` now defines
the missing database boundary: private provider-price mappings, idempotent
15-minute checkout requests, capability-gated prepare, service-only claim and a
service-only Stripe event command. Checkout remains impossible while the only
pricebook is draft. The event command hashes provider/customer/subscription
references, deduplicates event IDs, rejects unbound payloads, ignores older
provider revisions, maps only an explicit subscription-event allowlist and
recomputes entitlements transactionally. A rollback matrix is authored for the
draft kill switch, capability, idempotency, server ACL, checkout binding,
duplicate delivery, active projection and stale-event rejection. This migration
is deployed in the greenfield project. The hosted rollback matrix passes after
two test-harness-only corrections (Management API does not support `psql`
`\\gset`, and the deliberately malformed stale-event fixture did not match the
strict Stripe event-ID format). No database-code correction was needed.

Hosted verification covers draft checkout denial, billing capability,
idempotent prepare, server-only price claim, checkout-to-account binding,
subscription activation, entitlement recompute, duplicate delivery and stale
provider revision. The privilege audit passes. Performance advisors report no
warnings; security advisors remain unchanged with only the pre-existing leaked
password protection warning. No Edge Function or Stripe secret is deployed and
no provider traffic occurred.

## Disabled Edge deployment

`billing-checkout` and `stripe-webhook` are deployed as version 1 in the
greenfield Supabase project. Function inventory verifies checkout has gateway
JWT verification enabled and the webhook has it disabled as required for an
external Stripe-signed caller. No Stripe or billing-runtime secret was set.

Negative hosted smoke passed: unauthenticated checkout is rejected by the Edge
gateway with `401`; unsigned/unconfigured webhook reaches the function and
returns neutral `503` with `no-store`. No checkout request, provider event,
entitlement or external Stripe request can result from either probe. Runtime
activation and real signature/session testing remain a separate test-pilot gate.

## Stripe sandbox configuration

The existing Stripe account now contains a dedicated `TeamzoneApp` sandbox,
one club-subscription product and six recurring SEK prices for Small, Medium and
Large monthly/annual offerings. A webhook destination targets only the deployed
`stripe-webhook` function and subscribes only to the four approved checkout and
subscription event types.

Supabase secret inventory verifies the required secret names without exposing
values: Stripe test key, webhook signing secret, canonical billing web origin
and an explicit false runtime flag. A deliberately invalid signature returns
`400`, proving the configured signature boundary executes before the runtime
gate.

Migration `20260816111900_s10a_stripe_sandbox_price_mapping.sql` maps the six
user-supplied sandbox price IDs to the private provider-price table. Hosted
verification reports exactly six active mappings while `se.v1-draft` remains
`draft`. Free has no Stripe price and Custom/XL remains quote-only. No checkout
session or accepted provider event has occurred.

## Pilot target prepared, runtime returned off

Read-only account resolution identified the active `club_functionary`
assignment for the product owner's `Thomas klubb` account. Migration
`20260816112000_s10a_stripe_sandbox_pilot_activation.sql` grants only that
assignment `club.billing.manage`, publishes immutable test version `se.v1`,
moves all six sandbox mappings to it and records an explicit audit event.
Hosted verification confirms one published version, six mappings and the scoped
capability.

Runtime was briefly set true as the next pilot step, then immediately restored
to false before any checkout attempt when the client review found that the
The local Flutter billing surface is now implemented behind
`club.billing.manage`. It exposes server-projected prices and checkout only on
Flutter web; Android and iOS show neutral subscription status without prices,
purchase controls, or external links. The local checkout function now has an
exact-origin CORS/OPTIONS contract for `app.teamzoneapp.se` and returns to the
implemented `/billing` route. A provider-neutral, capability-gated pricebook
projection is delivered by migration
`20260816112100_s10a_pricebook_query.sql`. On 2026-08-16 the migration was
applied to project `hgcshgunvooyudvrcpig` and `billing-checkout` version 9 was
deployed with JWT verification enabled. Hosted preflight returned HTTP 204 and
the exact `Access-Control-Allow-Origin: https://app.teamzoneapp.se`; no wildcard
origin was exposed. `BILLING_RUNTIME_ENABLED` remains `false` pending deployment
of the Flutter web client and an authenticated end-to-end checkout test.

On 2026-08-17 the production-configured Flutter web build was deployed only to
Firebase Hosting site `teamzoneapp-b02a2`. Both `/` and the SPA route `/billing`
returned HTTP 200 on the default `web.app` domain. Firebase accepted the CNAME
`app.teamzoneapp.se -> teamzoneapp-b02a2.web.app`; domain verification passed
and certificate minting started. Runtime remains disabled until the custom
domain serves a valid certificate and the authenticated pilot is explicitly
run.

On 2026-08-17 Firebase reported the domain connected. Independent HTTPS checks
returned HTTP 200 with a valid certificate (`ssl_verify_result=0`) for both `/`
and `/billing`. A stricter no-cache policy for SPA paths is prepared locally;
its hosting redeploy did not complete because the temporary Firebase CLI setup
stalled, so that operational hardening is not claimed as hosted yet.

The hosting hardening was subsequently deployed using the cached Firebase CLI:
all SPA paths now return `Cache-Control: no-cache`, and the bootstrap explicitly
unregisters the legacy TeamZone service worker before loading the greenfield
client. This removed the cached legacy passwordless login flow.

The approved authenticated Stripe sandbox pilot then completed on 2026-08-17.
Runtime was enabled, exact-origin preflight returned 204, unauthenticated POST
returned 401, and Thomas completed a `cs_test_` Small monthly checkout. Two
ordering defects were corrected by migrations
`20260817100000_s10a_fix_pricebook_wrapper_execution.sql` and
`20260817101000_s10a_fix_checkout_subscription_revision.sql`. A subsequent
Stripe subscription update processed successfully. Final provider-neutral
verification showed one completed checkout, an active `se.v1` `plan.small`
subscription, and `base.small` with write access. The original out-of-order
event remains auditable as `ignored_stale`; it was not deleted or rewritten.
No provider request occurred. The safe next gate is to implement and verify
those client/HTTP boundaries before re-enabling the sandbox runtime.
