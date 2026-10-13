# Android release builds and Google Play

The release build is shrunk with R8 and signed with the **upload key** from
`android/key.properties`. Without that file, local and audit release builds
use the debug key, and a Play bundle (`flutter build appbundle`) refuses to
build. The key and its passwords never go into git (`.gitignore` covers
`key.properties`, `*.jks` and `*.keystore`).

## 1. Create the upload key (once, by the product owner)

Run this yourself; `keytool` asks for a new keystore password and the
certificate details. Store the password in a password manager.

```powershell
& "C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot\bin\keytool.exe" -genkey -v -keystore "$env:USERPROFILE\teamzone-upload.jks" -keyalg RSA -keysize 4096 -validity 10000 -alias upload
```

Back up `teamzone-upload.jks` and the password separately (for example an
encrypted cloud backup plus the password manager). With Play App Signing a
lost upload key can be reset through Play Console support, but it takes time.

## 2. Point the build at the key

Create `android/key.properties` (never committed):

```properties
storeFile=C:/Users/<you>/teamzone-upload.jks
storePassword=<the keystore password>
keyAlias=upload
keyPassword=<the key password, often the same>
```

## 3. Google Play Console

1. Create the app (`com.teamzone.teamzone`) and enrol in **Play App Signing**:
   Google keeps the app signing key, you upload with the upload key.
2. Under *App integrity*, copy the SHA-1 and SHA-256 of the **app signing**
   certificate. Add them to the Android app in the Firebase project, and
   restrict the Firebase API key (Google Cloud → Credentials) to Android apps
   with package `com.teamzone.teamzone` and those fingerprints.
3. Fill in the store listing, content rating, data safety form (see
   `docs/security/` and the privacy policy) and target audience. The app is
   used by minors' teams: answer the families questions accordingly.

## 4. Build and upload

Raise `version` in `pubspec.yaml` (`x.y.z+build`; the build number must grow
for every upload), then build with the production dart-defines:

```powershell
flutter build appbundle --release --dart-define=TEAMZONE_ENV=production --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_PUBLISHABLE_KEY=<key>
```

Only a `TEAMZONE_ENV=production` build is `com.teamzone.teamzone`; every
other build is the test app `com.teamzone.teamzone.test` ("TeamZone Test"),
which reports to its own Firebase app. A Play bundle refuses to build for
any other environment.

Upload `build/app/outputs/bundle/release/app-release.aab` to an internal
testing track first.

## Crash reports from release builds

- R8 renames the Android (Java/Kotlin) side; the Crashlytics Gradle plugin
  uploads the mapping file during the release build, so native crashes stay
  readable.
- Dart code is **not** obfuscated (`--obfuscate` / `--split-debug-info` are not
  used). Obfuscated Dart traces are non-symbolic addresses that
  `StackSanitizer` (crash stacks reduced to code locations, PAR-OPS-05 option
  C) does not pass, so crash reports would lose their stack. The app's logic
  and data rules live on the server; revisit if Dart obfuscation becomes a
  requirement, together with symbol upload and a sanitizer for address frames.
