import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/observability/app_observability.dart';
import 'package:teamzone_app/src/core/observability/firebase_crash_reporter.dart';
import 'package:teamzone_app/src/core/routing/app_url_strategy.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppUrlStrategy();
  const environment = AppEnvironment.fromDefines();
  final observability = AppObservability(
    environment: environment.name,
    release: '0.1.0+1',
  );
  var crashReporter = FirebaseCrashReporter.disabled;
  try {
    crashReporter = await FirebaseCrashReporter.initialize(environment);
    if (kDebugMode && const bool.fromEnvironment('CRASHLYTICS_TEST_ON_START')) {
      await crashReporter.recordSanitized(
        operation: 'crashlytics.audit_probe',
        error: const FormatException('redacted'),
        fatal: false,
      );
    }
  } catch (error) {
    observability.failure(operation: 'firebase.initialize', error: error);
  }
  FlutterError.onError = (details) {
    observability.failure(
      operation: 'flutter.framework',
      error: details.exception,
    );
    unawaited(
      crashReporter.recordSanitized(
        operation: 'flutter.framework',
        error: details.exception,
        fatal: true,
      ),
    );
  };
  await runZonedGuarded(
    () async {
      final services = await SupabaseBootstrap.initialize(environment);
      runApp(TeamZoneApp(environment: environment, services: services));
    },
    (error, _) {
      observability.failure(operation: 'flutter.async', error: error);
      unawaited(
        crashReporter.recordSanitized(
          operation: 'flutter.async',
          error: error,
          fatal: true,
        ),
      );
    },
  );
}
