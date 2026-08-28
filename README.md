# TeamZone App

Greenfield Flutter rebuild of TeamZone.

## Status

S00 through S10 are implemented and verified within their approved greenfield
scope. This includes the platform, roster, calendar, squad/callups, main
surfaces, messaging, Match Space, development, publication, billing
entitlements, Economy and Board. Fee/payment settlement remains closed by
PAR-FIN-03, and S11 workspaces/webtools are explicitly deferred while the core
application is stabilized.

Current progress is tracked in
[`docs/implementation/slice_status.md`](docs/implementation/slice_status.md).
The approved files under `docs/specification/source/` remain an immutable input
snapshot rather than a mutable progress tracker.

## Targets

- Android: `com.teamzone.teamzone`
- iOS: `com.teamzone.teamzone`
- Flutter web

Native desktop is not a v1 target. iOS build/signing requires a later macOS or CI environment.

## Local checks

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Use `--dart-define=TEAMZONE_ENV=audit` to select a non-secret environment name.
An approved non-live environment can be connected with:

```powershell
--dart-define=SUPABASE_URL=https://project-ref.supabase.co
--dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME
```

Without both values the app deliberately shows a safe unconfigured state.

## Security

Never commit `.env`, signing material, access tokens, secret keys or service-role keys. Public clients may eventually contain only a publishable key.

## Database boundary

The TeamZone database is rebuilt from an empty database. S01 migrations do not
read, backfill, shadow, dual-write or otherwise depend on legacy Teamzone6
objects. The repository is linked only to the new greenfield `TeamzoneApp`
audit project; Teamzone6 is not a migration source or deployment target and
must not be changed without separate approval.
