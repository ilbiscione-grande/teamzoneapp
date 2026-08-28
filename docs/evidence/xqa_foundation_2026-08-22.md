# X-QA shared verification foundation evidence

Date: 2026-08-22

X-QA-01 now has a shared, transaction-local SQL fixture foundation at
`supabase/tests/support/xqa_fixtures.sql`. It standardizes actor JWT claims,
claim clearing and deterministic fixture UUIDs without persisting helper
functions or credentials in the database.

`docs/evidence/xqa_manifest_2026-08-22.json` is the machine-readable evidence
index for S00 through S10B. It binds the greenfield Supabase/Firebase targets,
migration range, evidence files, privilege manifests and known exceptions. A
source revision cannot yet be recorded because this workspace has no initial
Git commit; the manifest records that fact explicitly rather than inventing a
revision.

`test/xqa_repository_contract_test.dart` verifies evidence coverage and file
existence, privilege-manifest parsing, absence of direct client table grants,
absence of custom anon grants across migrations, and the safety contract of the
shared SQL fixtures.

`supabase/tests/xqa_privilege_diff.sql` performs the live catalog diff without
writes. It requires RLS on every `core` table, rejects direct client table
privileges across `core`, `internal` and `audit`, rejects anonymous execution
of custom `api` functions and rejects anonymous usage of the custom API and
internal schemas.

Verification completed on 2026-08-22: the new X-QA contract passed, the full
Flutter regression suite passed all 51 tests, and `flutter analyze --no-pub`
reported no issues. The first full run exposed one whitespace-sensitive legacy
source-contract assertion; it was made formatting-tolerant without changing
product behavior, and the complete suite then passed. The hosted privilege
diff passed and rolled back without changing database state.
