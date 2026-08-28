# S01 greenfield foundation

## Decision boundary

S01 starts both the application and database from scratch. Teamzone6 is a
read-only historical/specification reference, not a schema source, migration
source or deployment target. No backfill, dual-write, shadow read or legacy
compatibility object belongs in the new migration chain.

The foundation is deployed to the separately created greenfield Supabase
project `TeamzoneApp`. Deploying to Teamzone6 or any future production project
always requires separate approval.

## Client foundation

- `TEAMZONE_ENV` names the environment without carrying credentials.
- `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are the only client backend
  defines. Missing values produce a safe unconfigured state.
- Auth session state is server/SDK-derived and uses timeout, retry and sanitized
  user errors.
- Authenticated startup loads `api.get_profile()` and
  `api.get_my_contexts()`; the client never supplies an actor/profile ID.
- An account with no active context enters a waiting room rather than a false
  onboarding or player context.
- Contexts carry server-derived capabilities. Unknown or malformed capability
  projections fail closed.
- Stable routes are `/home`, `/team`, `/calendar`, `/inbox` and `/statistics`.
  Phone uses bottom navigation and wide layouts use a navigation rail.
- All S01 copy is available in Swedish and English.

## Database foundation

The first repository migration creates non-exposed `core`, `internal` and
`audit` schemas plus authenticated `api` wrappers. It includes profiles, clubs,
teams, tenant-owned club people, verified account links, temporal assignments,
capability grants, command deduplication, audit events and greenfield migration
provenance.

Default privileges and direct table privileges are revoked. Core tables have
RLS as defense in depth. Exposed functions are `SECURITY INVOKER`; narrow
internal functions are `SECURITY DEFINER`, use an empty `search_path`, derive
the actor with `auth.uid()` and have explicit execute grants. A versioned
profile-preference command demonstrates idempotent wrapper-to-internal-command,
audit and retry behavior.

The expected ACL surface is machine-readable in
`supabase/privileges/s01_expected_privileges.json`.

## Hosted audit verification

- Six migrations replayed from an empty Supabase/PostgreSQL 17 project.
- Real password/JWT profile, multi-context, idempotency and logout flow passed.
- Transactional anon, cross-tenant and invalid-role negatives passed.
- Privilege/RLS checks and Security/Performance Advisors are clean.
- Legacy API keys are disabled and the exposed legacy HS256 signing key is
  revoked; only the modern publishable/secret and ES256 paths remain active.

## Remaining gates

- Signed audit artifact and device-level deep-link/refresh/back/sign-out smoke.
- Leaked-password protection and future step-up/MFA operations decisions.
- Production domains and release/canary decisions.

S01 is hosted-audit verified but remains in progress and is not
production-release-approved. See
[`../implementation/slice_status.md`](../implementation/slice_status.md) for the
authoritative mutable execution status.
