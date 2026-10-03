# Assistant settings — 2026-10-03

The assistant page shows its chosen name in the app bar beside Back, with a settings gear on the right. The duplicate body title and team/club context banner are removed. Each task retains its own club/team context. The desktop assistant panel also exposes the settings gear.

Settings contain eight task visibility switches, an explicit save action, and the existing name, information and other assistant settings. Visibility choices belong to the signed-in account and filter cards and the FAB counter, including snoozed/archived lists. Existing task authorization remains in force. All categories are visible by default.

The private preferences table is accessible through actor-scoped RPCs. Revision checks prevent a stale device from overwriting a newer save; identical retries are safe. Failed reads show an error rather than overwriting saved choices. Failed saves retain the current selection for retry.

## Verification

- 67 focused Flutter tests passed, including settings navigation in the app bar, removed banner, save, return navigation and card/badge refresh.
- Flutter analyze passed with no issues; `git diff --check` passed.
- Audit web release built successfully. Localhost port 5000 returned HTTP 200 for `main.dart.js`; its hash matched the new build. Build retains the existing Cupertino font-family warning.
- Local PGlite tests passed: defaults, persistence, actor isolation, validation, revision conflict, retry, reset and ACL.
- Migration `20261003063110_assistant_task_visibility_preferences.sql` applied to the audit project only. Hosted save/read smoke check used a rolled-back transaction; anonymous RPC access and direct authenticated table access are denied.
- Security advisors retain the existing private-table informational findings and leaked-password-protection warning; no preferences-table finding.

No public hosting deployment or phone installation is part of this change.
