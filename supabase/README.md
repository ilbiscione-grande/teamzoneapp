# Supabase

The repository contains an unlinked local configuration and a greenfield S01
migration chain. Do not run linked or remote commands without an explicit
environment approval and target project.

Target application schemas from the approved specification are `api` and `public_api`. Canonical domain data will live in non-exposed schemas during S01 and later slices.

The database starts empty and never backfills or deploys to Teamzone6. Dynamic
migration/JWT verification requires either a working local PostgreSQL 17 /
Supabase runtime or a separately approved new greenfield audit project.
