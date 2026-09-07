# S00 command matrix

| Check | Command | Required on this host |
|---|---|---|
| Format | `dart format --output=none --set-exit-if-changed lib test` | Yes |
| Analyze | `flutter analyze` | Yes |
| Unit/widget | `flutter test` | Yes |
| Web build | `flutter build web` | Yes |
| Android debug | `flutter build apk --debug` (see note below for a backend-connected build) | Yes |
| Android device smoke | `flutter run -d <device>` (see note below for a backend-connected build) | When a device is connected |
| iOS build/sign | CI/macOS command decided later | No on Windows |

All Flutter commands need write access to the shared Flutter SDK cache. CI must pin a compatible Flutter release and commit `pubspec.lock`.

**Backend-connected builds:** the plain commands above build against environment `local`, which has no Supabase project wired (see [environment.md](environment.md#environment-contract)) — the app runs but shows "Backend är inte ansluten" instead of real data. This is expected, not a bug. To build/run against an actual hosted project, append:

```
--dart-define=TEAMZONE_ENV=audit
--dart-define=SUPABASE_URL=https://<project-ref>.supabase.co
--dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

Get `<project-ref>` from `supabase projects list` (the currently linked project is `hgcshgunvooyudvrcpig`) and the publishable key from the Supabase dashboard → that project → Project Settings → API. Both are safe to embed in a client build (they are the public/anon-style keys, not secret/service-role keys) but are kept out of this repo and out of committed docs so they can be rotated without a doc update — never commit them to `.env` (git-ignored) or paste them into checked-in files.
