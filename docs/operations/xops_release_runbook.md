# X-OPS-01 release runbook

## Preconditions

- Identify audit/production target from `ops/environments.json`; never infer it.
- Record commit, schema/API version, artifact checksum and approver.
- Run analyze, tests, empty-database migration, privilege diff and provider advisors.
- Confirm secret names from `ops/secret_inventory.json`; never print values.

## Canary and smoke

1. Deploy additively to an isolated preview/audit target.
2. Keep new writes and integrations off by default.
3. Run anonymous, authenticated, tenant-isolation, Auth, Data, Storage,
   Realtime and Edge smoke checks.
4. Enable only the approved pilot cohort and observe sanitized health signals.
5. Promote the exact verified artifact; do not rebuild between canary and promotion.

Approved gates: Thomas club for 48 stable hours, then production cohorts 5%,
25% and 100% with at least 24 stable hours per stage. Promotion requires zero
P0/P1 defects or tenant/authorization deviations.

## Rollback / roll-forward

- Disable the affected route or integration kill switch first.
- Roll back client traffic only while additive schema remains compatible.
- Never delete newly written facts. Prefer corrected roll-forward/replay.
- Record correlation IDs, artifact versions, decision owner and timestamps.

Credential retirement requires seven stable days, at least 500 verified
authenticated operations across Auth, Data, Storage, Realtime and Edge, and no
fallback traffic. Compatibility remains for 30 days or two client versions.

Production provisioning, traffic promotion and key retirement still require
their own explicit approval.
