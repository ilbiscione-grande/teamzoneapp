# X-UX shared client foundation evidence

Date: 2026-08-22

X-UX-01 centralizes light/dark Material 3 themes, spacing, content sizing,
minimum 48 px touch targets and reduced-motion duration selection. The existing
phone/tablet/desktop boundaries remain centralized in `AppBreakpoints`.

Reusable `AppLoadingIndicator` and `AppStateCard` components provide live
loading semantics, heading semantics, consistent spacing and preserved action
controls. The existing app-wide state card now delegates to the shared
component, avoiding a risky whole-client rewrite while immediately applying
the common accessibility behavior to current empty/error states.

`test/xux_foundation_test.dart` covers theme modes, touch target baseline,
breakpoint boundaries, loading semantics, state-card content/actions and app
shell adoption. Broader extraction of remaining hard-coded feature strings and
replacement of every raw spinner remain follow-up work before X-UX-01 closes.

Verification passed on 2026-08-22: all five focused X-UX tests passed, the
complete Flutter regression suite passed all 56 tests, and static analysis
reported no issues. No backend, hosting or live Supabase state changed.

The second increment replaced every raw full-surface spinner in the Flutter
client with `AppLoadingIndicator`; the only remaining direct progress widget is
the deliberately compact sign-in button indicator, now wrapped in a labelled
live semantic region. Common cancel/continue/reason strings were added to the
Swedish/English model and adopted by both Economy and Board reason dialogs.
Focused tests, clean analysis and the full 56-test regression suite passed
again. Remaining localization work concerns feature-specific hard-coded copy,
not loading accessibility.

The Board surface is now fully domain-localized through `BoardStrings`:
headings, forms, offices, scheduled/active/ended/revoked states, approval
counts, actions, tooltips and safe error messages all have Swedish and English
variants. The pre-existing Board contract test was updated to verify the
localized contract rather than requiring Swedish copy inside the app shell.
Focused Board/X-UX tests, clean analysis and the full 56-test suite passed.

The Economy surface now follows the same domain-localization boundary through
`EconomyStrings`. Account and entry forms, inflow/outflow labels, club/team
accounts, entry categories and states, approval counts, posting/reversal
actions, tooltips and safe errors all have Swedish and English variants. The
Economy source-contract test now verifies that localized boundary. Focused
Economy/X-UX tests, static analysis and the complete 56-test suite passed.

The final localization increment migrated the remaining static copy for
calendar, roster/squad, billing, development, Match Space and messaging through
the locale boundary. Common dynamic status values, approval/delivery labels,
plan intervals/capacity, match clock/period actions and match facts now render
in Swedish or English. English mode fails loudly for a missing feature-copy
entry instead of silently falling back to Swedish.

`tool/localize_static_copy.dart` provides a deterministic mechanical migration
for exact static literals. The X-UX contract now rejects Swedish app-shell
literals that bypass the locale boundary and verifies that every referenced
feature key exists in the dictionary. The complete suite passes all 57 tests
and static analysis reports no issues. X-UX-01 is complete.

The production-configured Flutter web release then built successfully in
222.1 seconds and deployed to Firebase Hosting site `teamzoneapp-b02a2`.
A cache-busted HTTPS fetch from `app.teamzoneapp.se/main.dart.js` returned HTTP
200 and confirmed both the English Economy approval copy and the missing-key
locale guard in the live bundle.
