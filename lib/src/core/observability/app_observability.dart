import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

enum AppLogSeverity { debug, info, warning, error, fatal }

typedef AppLogSink = void Function(Map<String, Object?> record);

/// Provider-neutral, data-minimized observability boundary.
///
/// Callers may only provide allowlisted scalar dimensions. Errors, stack
/// traces, tokens, payloads, e-mail addresses and user-entered text are never
/// accepted by this API.
final class AppObservability {
  AppObservability({
    required this.environment,
    required this.release,
    AppLogSink? sink,
  }) : _sink = sink ?? _debugSink;

  final String environment;
  final String release;
  final AppLogSink _sink;

  static const _allowedDimensions = <String>{
    'operation',
    'route',
    'component',
    'result',
    'duration_bucket',
    'error_type',
  };

  static String correlationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  void event({
    required String name,
    required AppLogSeverity severity,
    required String correlationId,
    Map<String, Object?> dimensions = const {},
  }) {
    final safeDimensions = <String, Object?>{};
    for (final entry in dimensions.entries) {
      if (_allowedDimensions.contains(entry.key) &&
          _isSafeScalar(entry.value)) {
        safeDimensions[entry.key] = entry.value;
      }
    }
    _sink(<String, Object?>{
      'event': _safeIdentifier(name),
      'severity': severity.name,
      'release': _safeIdentifier(release),
      'environment': _safeIdentifier(environment),
      'correlation_id': _safeIdentifier(correlationId),
      'dimensions': safeDimensions,
    });
  }

  void failure({
    required String operation,
    required Object error,
    String? correlationId,
  }) {
    event(
      name: 'operation.failed',
      severity: AppLogSeverity.error,
      correlationId: correlationId ?? AppObservability.correlationId(),
      dimensions: {
        'operation': _safeIdentifier(operation),
        'error_type': _safeIdentifier(error.runtimeType.toString()),
        'result': 'failed',
      },
    );
  }

  static bool _isSafeScalar(Object? value) =>
      value == null ||
      value is bool ||
      value is num ||
      (value is String && value.length <= 80 && !value.contains('@'));

  static String _safeIdentifier(String value) => value
      .replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_')
      .substring(0, value.length.clamp(0, 80));

  static void _debugSink(Map<String, Object?> record) {
    if (kDebugMode) debugPrint(jsonEncode(record));
  }
}
