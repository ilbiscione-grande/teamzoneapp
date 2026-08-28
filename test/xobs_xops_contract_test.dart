import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/observability/app_observability.dart';

void main() {
  test('observability drops non-allowlisted and identifying dimensions', () {
    Map<String, Object?>? record;
    final logger = AppObservability(
      environment: 'audit',
      release: 'test',
      sink: (value) => record = value,
    );
    logger.event(
      name: 'query.completed',
      severity: AppLogSeverity.info,
      correlationId: 'correlation-123',
      dimensions: {
        'operation': 'team.load',
        'email': 'person@example.com',
        'route': 'person@example.com',
        'payload': {'secret': 'value'},
      },
    );
    final dimensions = record!['dimensions']! as Map<String, Object?>;
    expect(dimensions, {'operation': 'team.load'});
    expect(jsonEncode(record), isNot(contains('person@example.com')));
    expect(jsonEncode(record), isNot(contains('secret')));
  });

  test('critical integration switches default to fail closed', () {
    const environment = AppEnvironment(name: 'audit');
    expect(environment.billingEnabled, isFalse);
    expect(environment.notificationsEnabled, isFalse);
    expect(environment.publicContactEnabled, isFalse);
  });

  test('operations manifests contain no secret values', () {
    final inventory = File('ops/secret_inventory.json').readAsStringSync();
    expect(inventory, isNot(contains('sk_')));
    expect(inventory, isNot(contains('service_role')));
    expect(inventory, isNot(contains('secretValue')));
    final environments =
        jsonDecode(File('ops/environments.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(environments['schemaVersion'], 1);
    expect(
      environments['environments']['production']['status'],
      'not_provisioned',
    );
  });

  test(
    'all observability Edge handlers propagate sanitized correlation IDs',
    () {
      for (final name in <String>[
        'billing-checkout',
        'stripe-webhook',
        'notification-worker',
        'message-retention-worker',
        'critical-flow-monitor',
        'critical-flow-command',
      ]) {
        final source = File(
          'supabase/functions/$name/index.ts',
        ).readAsStringSync();
        expect(source, contains('correlationId(request)'), reason: name);
        expect(source, contains('withCorrelation'), reason: name);
        expect(source, isNot(contains('console.')), reason: name);
      }
    },
  );

  test('critical-flow metric is private, bounded and thresholded', () {
    final migration = File(
      'supabase/migrations/20260822181735_xobs_critical_flow_metrics.sql',
    ).readAsStringSync();
    for (final flow in <String>[
      'auth',
      'checkout',
      'messaging',
      'critical_commands',
    ]) {
      expect(migration, contains("'$flow'"));
    }
    expect(migration, contains("interval '4 minutes'"));
    expect(migration, contains('>= 5'));
    expect(migration, contains("'service_role'"));
    expect(
      migration,
      contains(
        'revoke all on internal.critical_flow_outcome_buckets from public, anon, authenticated',
      ),
    );
    expect(migration, isNot(contains('actor_profile_id')));
    expect(migration, isNot(contains('club_id')));

    final keyCompatibility = File(
      'supabase/migrations/20260822223830_xobs_secret_key_counter_authorization.sql',
    ).readAsStringSync();
    expect(keyCompatibility, contains('to service_role'));
    expect(keyCompatibility, contains('from public, anon, authenticated'));
    expect(
      keyCompatibility,
      isNot(contains('perform internal.require_observability_service_role()')),
    );
  });

  test('critical-flow monitor emits only allowlisted aggregate dimensions', () {
    final helper = File(
      'supabase/functions/_shared/observability.ts',
    ).readAsStringSync();
    final monitor = File(
      'supabase/functions/critical-flow-monitor/index.ts',
    ).readAsStringSync();
    expect(helper, contains('failure_rate_percent'));
    expect(monitor, contains('critical_flow.threshold_breached'));
    expect(monitor, contains('window_minutes: 5'));
    expect(monitor, isNot(contains('console.')));
  });

  test('critical command gateway is allowlisted and never logs parameters', () {
    final gateway = File(
      'supabase/functions/critical-flow-command/index.ts',
    ).readAsStringSync();
    expect(gateway, contains('Object.freeze'));
    expect(gateway, contains('recordCriticalFlowOutcome'));
    expect(
      gateway,
      contains('global: { headers: { Authorization: authorization } }'),
    );
    expect(gateway, contains('request.method === "OPTIONS"'));
    expect(gateway, contains('access-control-allow-origin'));
    expect(gateway, contains('operation_not_allowed'));
    expect(gateway, contains('accepted_callups_required'));
    expect(gateway, isNot(contains('sanitizedLog("params')));
    expect(gateway, isNot(contains('JSON.stringify(params)')));

    final measuredClient = File(
      'lib/src/core/supabase/measured_rpc.dart',
    ).readAsStringSync();
    expect(measuredClient, contains("'critical-flow-command'"));
    expect(measuredClient, contains('MeasuredCommandException'));
    for (final feature in <String>['messaging', 'match', 'economy', 'board']) {
      final source = File(
        'lib/src/features/$feature/${feature}_services.dart',
      ).readAsStringSync();
      expect(source, contains('measuredRpc'), reason: feature);
    }
  });

  test('password sign-in is server measured without identity logging', () {
    final handler = File(
      'supabase/functions/auth-password-sign-in/index.ts',
    ).readAsStringSync();
    expect(handler, contains('signInWithPassword'));
    expect(handler, contains('recordCriticalFlowOutcome'));
    expect(handler, contains('"auth"'));
    expect(handler, contains('cache-control'));
    expect(
      handler,
      contains('authorization, apikey, content-type, x-client-info'),
    );
    expect(handler, isNot(contains('dimensions: { email')));
    expect(handler, isNot(contains('dimensions: { password')));
    expect(handler, isNot(contains('JSON.stringify(input)')));

    final bootstrap = File(
      'lib/src/core/supabase/supabase_bootstrap.dart',
    ).readAsStringSync();
    expect(bootstrap, contains("'auth-password-sign-in'"));
    expect(bootstrap, contains('setSession(refreshToken)'));
    expect(bootstrap, isNot(contains('_client.auth.signInWithPassword')));
  });

  test('advisor remediation implements replay-safe command idempotency', () {
    final migration = File(
      'supabase/migrations/20260822120244_xobs_command_idempotency.sql',
    ).readAsStringSync();
    for (final command in <String>[
      'message.thread.read.v1',
      'message.thread.mute.v1',
      'message.contact.decide.v1',
    ]) {
      expect(
        RegExp(RegExp.escape(command)).allMatches(migration).length,
        greaterThanOrEqualTo(2),
      );
    }
    expect(
      RegExp('select result into existing_result').allMatches(migration).length,
      3,
    );
    expect(
      RegExp(
        'insert into internal.command_deduplication',
      ).allMatches(migration).length,
      4,
    );
  });

  test(
    'approved operations policy is explicit and analytics stays disabled',
    () {
      final policy =
          jsonDecode(File('ops/observability_policy.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(policy['analyticsEnabled'], isFalse);
      expect(policy['retentionDays']['errors'], 30);
      expect(policy['retentionDays']['performance'], 14);
      expect(policy['alerts']['criticalFailureRatePercent'], 5);
      expect(policy['alerts']['windowMinutes'], 5);
      expect(policy['onCall']['primaryRole'], 'product_owner');
    },
  );

  test('Crashlytics boundary is Android-only and sanitizes error details', () {
    final source = File(
      'lib/src/core/observability/firebase_crash_reporter.dart',
    ).readAsStringSync();
    expect(source, contains('defaultTargetPlatform != TargetPlatform.android'));
    expect(source, contains('StackTrace.empty'));
    expect(source, contains("reason: 'sanitized_failure'"));
    expect(source, isNot(contains('firebase_analytics')));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('firebase_analytics')),
    );
  });

  test('Crashlytics audit probe is debug-only and opt-in', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('kDebugMode'));
    expect(
      source,
      contains("bool.fromEnvironment('CRASHLYTICS_TEST_ON_START')"),
    );
    expect(source, contains("operation: 'crashlytics.audit_probe'"));
    expect(source, contains('fatal: false'));
  });
}
