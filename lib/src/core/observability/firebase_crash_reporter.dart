import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:teamzone_app/firebase_options.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/observability/app_observability.dart';
import 'package:teamzone_app/src/core/observability/stack_sanitizer.dart';

final class FirebaseCrashReporter {
  const FirebaseCrashReporter._(this.enabled);

  static const disabled = FirebaseCrashReporter._(false);

  final bool enabled;

  static Future<FirebaseCrashReporter> initialize(
    AppEnvironment environment,
  ) async {
    // Crashlytics covers Android and iOS (PAR-OPS-05); web reports through
    // WebErrorReporter. iOS stays off until `flutterfire configure` adds its
    // options (DefaultFirebaseOptions throws UnsupportedError until then).
    final mobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (kIsWeb || !mobile) return disabled;
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android reads google-services.json for the built application id, so
      // the test app (com.teamzone.teamzone.test) and production each report
      // to their own Firebase app.
      await Firebase.initializeApp();
    } else {
      final FirebaseOptions options;
      try {
        options = DefaultFirebaseOptions.currentPlatform;
      } on UnsupportedError {
        return disabled;
      }
      await Firebase.initializeApp(options: options);
    }
    final enabled = environment.parsedName != AppEnvironmentName.local;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
    return FirebaseCrashReporter._(enabled);
  }

  /// Records the error's type, never its message. A fatal (unhandled) error
  /// also carries its stack reduced to code locations ([StackSanitizer]);
  /// handled failures send StackTrace.empty.
  Future<void> recordSanitized({
    required String operation,
    required Object error,
    required bool fatal,
    StackTrace? stack,
  }) async {
    if (!enabled) return;
    await FirebaseCrashlytics.instance.setCustomKey(
      'correlation_id',
      AppObservability.correlationId(),
    );
    await FirebaseCrashlytics.instance.setCustomKey('operation', operation);
    await FirebaseCrashlytics.instance.recordError(
      StateError('sanitized_${error.runtimeType}'),
      sanitizedStack(stack, fatal: fatal),
      fatal: fatal,
      reason: 'sanitized_failure',
    );
  }

  static StackTrace sanitizedStack(StackTrace? stack, {required bool fatal}) {
    final frames = fatal ? StackSanitizer.sanitize(stack) : '';
    return frames.isEmpty ? StackTrace.empty : StackTrace.fromString(frames);
  }
}
