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

## Follow-up: dismissible welcome message

A compact welcome message now appears immediately above the Current, Snoozed
and Archived controls. It briefly explains what the assistant can help with and
has a close action in its top-right corner. Closing it saves
`welcome_message_visible=false` in the signed-in account's existing private
assistant preferences. Assistant settings expose “Visa välkomstmeddelande” so
the user can explicitly restore it on every device.

The v3 preference setter updates task visibility, team scope and welcome
visibility under the existing revision lock. The v1/v2 setters remain available
and preserve the new field, preventing an older installed client from silently
turning a dismissed message back on. The internal table remains inaccessible to
client roles; only the authenticated actor-scoped RPC is executable.

Verification: the PGlite contract covers defaults, account isolation, safe
retry, conflicts, invalid input, legacy preservation and ACL. Five focused
preference widget tests cover dismissing and restoring the message, all 17
assistant context/layout tests pass, the real settings navigation test passes,
and Flutter analyze reports no issues. Migration
`20261003083806_assistant_welcome_message_visibility.sql` is applied to the
audit project; the hosted column is non-null boolean with default true,
authenticated has RPC execute, anon does not, and the post-migration advisors
reported no findings related to this preference or RPC.
