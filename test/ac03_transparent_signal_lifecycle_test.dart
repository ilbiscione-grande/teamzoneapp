import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827203154_ac03_transparent_signal_lifecycle.sql',
  ).readAsStringSync();
  final entry = File(
    'lib/src/features/assistant_coach/assistant_coach_entry.dart',
  ).readAsStringSync();

  test('signal actions navigate and never mutate domain data', () {
    expect(migration, contains("'requiresExplicitUserAction',true"));
    expect(migration, contains("'performsDomainMutation',false"));
    expect(migration, contains("'domainMutation',false"));
    expect(entry, contains('ändringar kräver att du själv bekräftar dem'));
  });

  test('opaque profiling and generative behavior stay disabled', () {
    for (final contract in <String>[
      "'riskScore',false",
      "'medicalInference',false",
      "'personComparison',false",
      "'generativeAi',false",
    ]) {
      expect(migration, contains(contract));
    }
    expect(entry, contains('inga dolda riskpoäng'));
  });

  test(
    'dismiss and restore are private, audited and notification-independent',
    () {
      expect(migration, contains('internal.assistant_signal_receipts'));
      expect(migration, contains('audit.assistant_signal_receipt_events'));
      expect(migration, contains('assistant.signal.dismiss.v1'));
      expect(migration, contains('assistant.signal.restore.v1'));
      expect(migration, contains('include_dismissed'));
      expect(migration, isNot(contains('notification_receipts')));
      expect(migration, isNot(contains('notification_outbox')));
      expect(entry, contains('utan att Inbox-historik ändras'));
    },
  );
}
