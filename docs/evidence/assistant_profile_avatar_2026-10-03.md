# Assistant profile avatar

Users can choose Standard plus Woman 1–3 and Man 1–3 under Assistant settings → Appearance and name. The six supplied images are bundled assets, work offline and are not treated as user uploads. The selected avatar appears in the assistant page title, desktop side panel and mobile assistant button. Standard restores the existing assistant icon.

The choice is private to the signed-in account and follows it between devices. Migration `20261003070703_assistant_profile_avatar.sql` extends the existing assistant identity preference with an allow-listed `avatar_key` and a separate revision-checked, idempotent RPC. Saving an avatar preserves the custom assistant name. The existing name RPC preserves the avatar, so installed older clients remain compatible.

Verification:

- Local database test passed for persistence, reset, validation, stale revisions, idempotent retry, account isolation and ACL.
- Audit migration applied successfully. A rolled-back hosted smoke check saved the avatar without changing the name; anonymous RPC access and direct authenticated table access are denied.
- Focused model and widget tests passed, including choosing the woman avatar and seeing its asset in the assistant header.
- Flutter analyze passed with no issues.
- Audit web release built successfully. Localhost port 5000 returned HTTP 200, served the exact new `main.dart.js`, and contains both avatar assets. The build retains the project's existing Cupertino font warning.

The security advisor retains the project's existing informational findings for private RLS tables without direct policies and the existing leaked-password-protection warning. The assistant preference table is intentionally accessed only through actor-scoped RPCs; direct table access remains revoked.

Migration `20261003072031_expand_assistant_profile_avatars.sql` extends the allow-list with `woman_2`, `woman_3`, `man_2` and `man_3`. Local and hosted rolled-back smoke tests confirmed that a new option can be saved while preserving the assistant name. Existing avatar keys remain valid.
