# S00 command matrix

| Check | Command | Required on this host |
|---|---|---|
| Format | `dart format --output=none --set-exit-if-changed lib test` | Yes |
| Analyze | `flutter analyze` | Yes |
| Unit/widget | `flutter test` | Yes |
| Web build | `flutter build web` | Yes |
| Android debug | `flutter build apk --debug` | Yes |
| Android device smoke | `flutter run -d <device>` | When a device is connected |
| iOS build/sign | CI/macOS command decided later | No on Windows |

All Flutter commands need write access to the shared Flutter SDK cache. CI must pin a compatible Flutter release and commit `pubspec.lock`.
