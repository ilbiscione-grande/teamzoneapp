# Supabase

The repository contains the greenfield TeamzoneApp migration chain, Edge
Functions and isolated SQL tests. The configured audit project is
`hgcshgunvooyudvrcpig` (TeamzoneApp, `eu-west-1`); separate production is not
provisioned. Do not run linked or remote commands without the appropriate
environment authorization and an explicit target project.

The client API boundary is `api`; canonical application data is held in
non-exposed schemas such as `core`, `internal`, `audit` and `attendance_export`.
Public projections use the server-side publication boundary; presence of a
schema named `public_api` is not permission to expose its tables to clients.

The database starts empty and never backfills or deploys to Teamzone6. Dynamic
migration/JWT verification requires either a working local PostgreSQL 17 /
Supabase runtime or the separately authorized greenfield audit project.

## Status checked 2026-10-25

- 389 local migration versions, 387 recorded in the audit migration log.
  Missing log entries: `20261022090000` (sign-in limits) and `20261128090000`
  (inactive Tacticsboard live sessions). Central objects exist, but exact
  migration equivalence has not been established. Do not blindly rerun or
  mark these migrations applied; first compare all affected objects and grants.
- All 84 `tests/*.local.mjs` files exited without errors in the review, plus
  the direct-result, written-report and team-notification test modes.
  These use PGlite fixtures, not a full replay of the hosted schema.
- The last documented empty-database replay covered 320 migrations on
  2026-10-13. Repeat for the current chain before production provisioning.
- Private buckets and direct-table denial were confirmed; these checks do
  not replace API authorization tests. Leaked-password protection remains off.
- `message-retention-worker` is deployed, but automatic execution was not
  established: no matching database cron job was found, and an external
  scheduler has not been verified.

See [current status](../docs/implementation/current_status.md), the
[review](../docs/evidence/app_status_review_2026-10-25.md) and
[production provisioning](../docs/operations/production_provisioning.md).
