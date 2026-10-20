import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/core/observability/firebase_crash_reporter.dart';
import 'package:teamzone_app/src/core/observability/web_error_reporter.dart';

class _AppDefect implements Exception {}

// A different runtimeType must not turn an expected timeout into a defect.
class _SlowProfileTimeout extends TimeoutException {
  _SlowProfileTimeout() : super('slow profile');
}

void main() {
  final reported = <(String, Object)>[];
  setUp(() {
    reported.clear();
    AppErrors.install((operation, error) => reported.add((operation, error)));
  });
  tearDown(AppErrors.uninstall);

  test('handled failures are reported once per window', () {
    final start = DateTime(2026, 10, 13, 12);
    AppErrors.caught('calendar._load', _AppDefect(), now: start);
    AppErrors.caught(
      'calendar._load',
      _AppDefect(),
      now: start.add(const Duration(minutes: 5)),
    );
    expect(reported, hasLength(1));
    AppErrors.caught('calendar._save', _AppDefect(), now: start);
    expect(
      reported,
      hasLength(2),
      reason: 'another operation is its own report',
    );
    AppErrors.caught(
      'calendar._load',
      _AppDefect(),
      now: start.add(AppErrors.repeatWindow),
    );
    expect(reported, hasLength(3), reason: 'reported again after the window');
  });

  test('being offline or slow is not reported', () {
    AppErrors.caught('inbox._load', TimeoutException('slow'));
    expect(reported, isEmpty);
    expect(AppErrors.isExpected(TimeoutException('slow')), isTrue);
    expect(AppErrors.isExpected(_AppDefect()), isFalse);
  });

  test('without an installed sink nothing happens', () {
    AppErrors.uninstall();
    AppErrors.caught('roster._save', _AppDefect());
    expect(reported, isEmpty);
  });

  test('timeout classification does not depend on its runtime type name', () {
    final error = _SlowProfileTimeout();
    expect(error.runtimeType.toString(), isNot('TimeoutException'));
    AppErrors.caught('product_shell._loadOwnSummary', error);
    expect(AppErrors.isExpected(error), isTrue);
    expect(reported, isEmpty);
  });

  // Option C (PAR-OPS-05, 2026-10-13): only crashes carry a stack, reduced
  // to code locations; the message never leaves the device.
  final crashStack = StackTrace.fromString(
    'Exception: Ogiltig e-post anna@example.se\n'
    '#0      _State._save (package:teamzone_app/src/x.dart:12:5)\n'
    r'#1      helper (file:///C:/Users/anna/app/lib/y.dart:3:1)',
  );

  test('only fatal reports carry a sanitized stack', () {
    expect(
      FirebaseCrashReporter.sanitizedStack(crashStack, fatal: false),
      StackTrace.empty,
    );
    final fatal = FirebaseCrashReporter.sanitizedStack(
      crashStack,
      fatal: true,
    ).toString();
    expect(
      fatal,
      '#0 _State._save (package:teamzone_app/src/x.dart:12:5)\n'
      '#1 helper (y.dart:3:1)',
    );
    final web =
        jsonDecode(
              WebErrorReporter.recordJson(
                operation: 'flutter.async',
                error: StateError('anna@example.se'),
                fatal: true,
                environment: 'audit',
                release: '0.1.0+1',
                stack: crashStack,
              ),
            )
            as Map<String, dynamic>;
    expect(web['stack'], [
      '#0 _State._save (package:teamzone_app/src/x.dart:12:5)',
      '#1 helper (y.dart:3:1)',
    ]);
    expect(jsonEncode(web), isNot(contains('anna')));
  });

  test('the web record carries only sanitized identifiers', () {
    final json =
        jsonDecode(
              WebErrorReporter.recordJson(
                operation: 'roster_surface._save',
                error: StateError('secret message about Anna'),
                fatal: false,
                environment: 'audit',
                release: '0.1.0+1',
              ),
            )
            as Map<String, dynamic>;
    expect(json, {
      'operation': 'roster_surface._save',
      'error_type': 'StateError',
      'fatal': false,
      'environment': 'audit',
      'release': '0.1.0_1',
    });
    expect(json.containsKey('stack'), isFalse, reason: 'handled: no stack');
    expect(WebErrorReporter.safeIdentifier('a b@c'), 'a_b_c');
    expect(WebErrorReporter.safeIdentifier('x' * 100), hasLength(80));
  });
}
