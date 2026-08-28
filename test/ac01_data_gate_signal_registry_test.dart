import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827195852_ac01_data_gate_signal_registry.sql',
  ).readAsStringSync();

  test('AC-01 registers the five approved deterministic signals', () {
    for (final key in <String>[
      'callup.unanswered',
      'event.near_without_participants',
      'event.missing_attendance',
      'event.responses_complete',
      'calendar.future_gap',
    ]) {
      expect(migration, contains("'$key'"));
    }
    expect(migration, contains('source_tables text[] not null'));
    expect(migration, contains('owner_capability text not null'));
    expect(migration, contains('freshness interval not null'));
  });

  test('each emitted signal is transparent and safely actionable', () {
    expect(migration, contains("'sourceUpdatedAt'"));
    expect(migration, contains("'freshUntil'"));
    expect(migration, contains("'explanation'"));
    expect(migration, contains("'safeAction'"));
    expect(migration, contains("'ownerCapability'"));
    expect(migration, contains("'authorized'"));
  });

  test(
    'authorization is capability scoped and AC activation remains blocked',
    () {
      expect(migration, contains("'event.squad.manage'"));
      expect(migration, contains("'event.attendance.manage'"));
      expect(migration, contains("'event.manage'"));
      expect(migration, contains("'development.manage'"));
      expect(migration, contains("'generativeAiEnabled',false"));
      expect(migration, contains("'activationAllowed',false"));
      expect(migration, isNot(contains("state='ready'")));
      expect(
        migration,
        contains('revoke all on table internal.assistant_signal_registry'),
      );
    },
  );
}
