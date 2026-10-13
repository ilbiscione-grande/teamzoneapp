# iOS builds and the App Store

TeamZone has never been built for iOS: development so far runs on Windows,
and an iOS build needs a Mac with Xcode. The project is prepared as far as
it can be without one. This page is the checklist for the first iOS build.

## Already in place

- Bundle identifier `com.teamzone.teamzone`.
- `Info.plist` has the camera and photo-library usage texts (profile
  pictures) and the `teamzone` URL scheme for sign-in redirects (PKCE).
- Crashlytics starts on iOS as soon as Firebase options for iOS exist
  (`FirebaseCrashReporter`; until then it stays off without errors). Crash
  stacks are reduced to code locations like on Android (PAR-OPS-05).

## Needs a Mac and an Apple Developer account

1. **Apple Developer Program** membership for the organisation (yearly fee),
   and an App ID for `com.teamzone.teamzone`.
2. **Firebase:** add an iOS app with the same bundle identifier in project
   `teamzoneapp-b02a2`, then on the Mac run `flutterfire configure`. It adds
   the iOS options to `lib/firebase_options.dart` and
   `ios/Runner/GoogleService-Info.plist`.
3. **Crashlytics dSYM upload:** add the Crashlytics run script build phase in
   Xcode (`${PODS_ROOT}/FirebaseCrashlytics/run`) so native crashes are
   symbolicated.
4. **Signing:** select the team in Xcode (Runner → Signing & Capabilities),
   automatic signing.
5. **Push notifications** (when push is built): enable the Push Notifications
   capability and Background Modes → Remote notifications, create an APNs key
   in the Apple Developer portal and upload it to Firebase Cloud Messaging.
6. **Build and test:** `flutter build ipa` with the same dart-defines as
   Android, upload through Xcode or Transporter, test with TestFlight first.
7. **App Store Connect:** store listing, privacy nutrition labels (match the
   Play data safety answers), age rating, and sign-in details for review.

## Verify on a device

The physical device gate for the core cards applies to iPhone too: sign-in,
deep links, the calendar, attendance, match mode, profile pictures and push.
