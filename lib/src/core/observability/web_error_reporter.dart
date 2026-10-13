import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/observability/stack_sanitizer.dart';
import 'package:teamzone_app/src/core/observability/web_error_sink.dart';

/// Flutter web's error reports: the observability policy routes web errors
/// to Google Cloud Logging, which the clientErrorSink Firebase function
/// writes to. The record is sanitized like a Crashlytics report: operation,
/// error type, fatal flag, release and environment; a fatal error also
/// carries its stack reduced to code locations ([StackSanitizer]).
final class WebErrorReporter {
  const WebErrorReporter._(this.url, this.environment, this.release);

  static const disabled = WebErrorReporter._('', '', '');

  static const sinkUrl =
      'https://europe-west1-teamzoneapp-b02a2.cloudfunctions.net/clientErrorSink';

  final String url, environment, release;

  bool get enabled => url.isNotEmpty;

  /// On for Flutter web outside local development.
  static WebErrorReporter forEnvironment(
    AppEnvironment environment, {
    required String release,
  }) => kIsWeb && environment.parsedName != AppEnvironmentName.local
      ? WebErrorReporter._(sinkUrl, environment.name, release)
      : disabled;

  /// The JSON body sent to the sink; also used by tests.
  static String recordJson({
    required String operation,
    required Object error,
    required bool fatal,
    required String environment,
    required String release,
    StackTrace? stack,
  }) {
    final frames = fatal ? StackSanitizer.sanitize(stack) : '';
    return jsonEncode({
      'operation': safeIdentifier(operation),
      'error_type': safeIdentifier(error.runtimeType.toString()),
      'fatal': fatal,
      'environment': safeIdentifier(environment),
      'release': safeIdentifier(release),
      if (frames.isNotEmpty) 'stack': frames.split('\n'),
    });
  }

  static String safeIdentifier(String value) {
    final safe = value.replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_');
    return safe.length > 80 ? safe.substring(0, 80) : safe;
  }

  void record({
    required String operation,
    required Object error,
    required bool fatal,
    StackTrace? stack,
  }) {
    if (!enabled) return;
    try {
      sendWebErrorRecord(
        url,
        recordJson(
          operation: operation,
          error: error,
          fatal: fatal,
          environment: environment,
          release: release,
          stack: stack,
        ),
      );
    } catch (_) {
      // Reporting must never become a failure of its own.
    }
  }
}
