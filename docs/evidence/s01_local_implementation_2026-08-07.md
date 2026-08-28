# S01 implementation and audit evidence – 2026-08-07

## Assessment

S01 is implemented locally and its greenfield database foundation is deployed
and verified in the newly created Supabase project `TeamzoneApp`
(`hgcshgunvooyudvrcpig`, PostgreSQL 17.6, EU West). This project is the rebuild
environment, not the existing Teamzone6 live project. Teamzone6 was not linked,
queried, migrated or otherwise changed during this work.

## Greenfield contract

The database is rebuilt from scratch. The migrations contain no legacy member,
membership, club-member, subscription or Teamzone6 objects, and the SQL contract
test fails if such references are introduced. The remote project had no user
schema or migration history before the S01 migrations were applied.

## Delivered

| S01 area | Result |
|---|---|
| Environment contract | Publishable key only; missing configuration fails safely |
| Auth/session | Password sign-in adapter, restored-session state, timeout, retry, sanitized errors and sign-out |
| Identity/context | `get_profile` and capability-based `get_my_contexts`; no actor ID from client |
| Zero context | Explicit waiting room |
| Navigation | `/home`, `/team`, `/calendar`, `/inbox`, `/statistics`; adaptive rail/bottom navigation |
| Localization | Swedish and English S01 copy |
| Database | Greenfield `core`, `internal`, `audit` and authenticated `api` schemas |
| Security | Default revoke, no direct client table grants, RLS, invoker wrappers and fixed-search-path definers |
| Command prototype | Idempotent profile-preference command with audit event |
| Scope integrity | Composite assignment/club FK and trigger enforcement for club/team capability scopes |
| Data API | Only `api` is exposed; `public_api` is deferred until its delivery slice |

## Verification results

| Check | Result |
|---|---|
| Dart format | Clean after formatting |
| Flutter analyze | No issues found |
| Flutter tests | 8/8 passed |
| Flutter web build | Passed; Wasm dry run passed |
| Android debug build | Passed; APK 172,353,265 bytes |
| Application ID | `com.teamzone.teamzone`; generated-artifact scan clean |
| Secret-shaped value scan | No matches outside the immutable specification snapshot |
| Remote migration parity | 6/6 local migrations present remotely |
| Transactional SQL suite | Passed, including authenticated context, capability, idempotency, anonymous denial and cross-tenant negatives; rolled back |
| Remote RLS | 7/7 `core` tables have RLS enabled |
| Remote direct grants | 0 `core` table grants for both `anon` and `authenticated` |
| Remote residue | 0 fixture profiles after test rollback |
| Data API configuration | `authenticator` has `pgrst.db_schemas=api` |
| Anonymous HTTP probe | Reached `api`; RPC remained hidden/denied to `anon` (`PGRST202`) |
| Security Advisor | No findings |
| Performance Advisor | No findings after the E2E query workload |
| Real Auth/JWT E2E | Password login, JWT identity, profile RPC and two-context RPC passed |
| Command E2E | Repeating one idempotency key returned the same revision (`2`) |
| Logout E2E | Local logout revoked the session refresh token |
| E2E cleanup | Auth user, profile, clubs, links, audit event and dedupe record all verified at zero |
| Key incident closure | Legacy `anon`/`service_role` disabled; exposed legacy JWT signing key revoked |
| Key verification | Both legacy API keys and the legacy `service_role` JWT return HTTP 401 |
| Current key path | Publishable and secret API keys return HTTP 200; JWKS contains one ES256 key |
| JWT role/state matrix | Player, guardian, leader, club functionary and guest pass; anon, unknown, super-admin claim without relation, suspended, ended and cross-club fail closed; transaction rolled back |
| Hosted password policy | 12+ characters with lower/upper/digit/symbol, recent session and current password required for change |
| Weak-password check | Public signup rejected `weak` with HTTP 422 / `weak_password`; no residue |
| MFA baseline | TOTP enabled; enrolled factors must reach AAL2 within 15 minutes |
| Audit APK | Release-optimized, audit-configured, APK Signature v2 using Android Debug audit-only certificate |
| Audit APK identity | 52,641,634 bytes; SHA-256 `2601A74D1E9B97FEDD271386005FD91F43C87247CA4D0A10C3E4F794405D652E` |
| Physical Android smoke | Passed on Samsung Galaxy S25 (`SM-S931B`), Android 16 / API 36, over authorized USB ADB |
| Device Auth/context | Real login, zero-context waiting room, two-context selector and all five safe routes passed |
| Device lifecycle/navigation | Session restored after force-stop/cold start; Android back returned safely; `teamzone://app/calendar` cold deep link opened Calendar |
| Device sign-out/cleanup | Sign-out returned to audit login; temporary Auth user, clubs and assignments all verified at zero |

The web build emitted a non-blocking missing `CupertinoIcons` font warning from
the resolved dependency graph. TeamZone S01 uses Material icons and both web and
Android artifacts completed successfully; the warning should be removed or
explicitly accepted before a release build.

## Applied migrations

1. `20260807163737_s01_platform_identity_context.sql`
2. `20260807182809_s01_cover_foreign_key_indexes.sql`
3. `20260807183334_s01_enforce_capability_scope.sql`
4. `20260807183714_s01_cover_capability_assignment_fk.sql`
5. `20260807184017_s01_configure_data_api_schema.sql`
6. `20260807185456_s01_reload_data_api_schema_cache.sql`

The real JWT test exposed that PostgREST configuration reload and function
schema-cache reload are separate operations. Migration 6 makes the required
schema reload reproducible on a fresh replay. The authenticated RPC test passed
after this migration was applied.

The Supabase CLI reported a non-blocking pg-delta catalog-cache warning because
Docker Desktop is unavailable. Migration application and subsequent remote
history/catalog checks succeeded independently of that optional cache step.

## Physical-device closure

The audit APK was installed on a Samsung Galaxy S25. The first run exposed a
missing Android `INTERNET` permission; the corrected manifest was rebuilt and
the real hosted login then passed. The device run also exposed the absent native
deep-link registration. The final artifact registers canonical
`teamzone://app/<route>` links and a cold `teamzone://app/calendar` launch was
verified on-device. Waiting room, two-context selection, five routes,
force-stop/session restore, Android back and sign-out all passed.

The Auth decision is recorded in
[`../security/s01_auth_policy.md`](../security/s01_auth_policy.md). Supabase's
leaked-password control is Pro-only and therefore unavailable in the current
Free audit project; it remains a production release gate. Compensating audit
controls are active and verified.

The audit APK is signed by the Android Debug certificate solely for installation
and audit smoke. It is not a production, Play upload or distribution signature.

The CLI unexpectedly printed the complete legacy `service_role` value while
listing key metadata. Incident containment is complete: the legacy API-key pair
was disabled and its previous HS256 signing key was revoked in Supabase. The
value is now rejected both as an `apikey` and as a bearer JWT.

This runtime check did not perform or authorize any operation against Teamzone6.

## Rollback

The new `TeamzoneApp` project is still greenfield and contains no product data.
Rollback is a forward migration or recreation of this new project from the
checked-in migrations. Teamzone6 is not part of the rollback path.
