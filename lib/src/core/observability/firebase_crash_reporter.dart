import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:teamzone_app/firebase_options.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/observability/app_observability.dart';

final class FirebaseCrashReporter {
  const FirebaseCrashReporter._(this.enabled);

  static const disabled = FirebaseCrashReporter._(false);

  final bool enabled;

  static Future<FirebaseCrashReporter> initialize(
    AppEnvironment environment,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return disabled;
    }
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final enabled = environment.parsedName != AppEnvironmentName.local;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
    return FirebaseCrashReporter._(enabled);
  }

  Future<void> recordSanitized({
    required String operation,
    required Object error,
    required bool fatal,
  }) async {
    if (!enabled) return;
    await FirebaseCrashlytics.instance.setCustomKey(
      'correlation_id',
      AppObservability.correlationId(),
    );
    await FirebaseCrashlytics.instance.setCustomKey('operation', operation);
    await FirebaseCrashlytics.instance.recordError(
      StateError('sanitized_${error.runtimeType}'),
      StackTrace.empty,
      fatal: fatal,
      reason: 'sanitized_failure',
    );
  }
}
