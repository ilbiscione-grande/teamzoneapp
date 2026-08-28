import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260808072153_s04_squad_callup_attendance_notifications.sql',
  ).readAsStringSync();

  test('S04 has one revisioned squad to callup path', () {
    expect(migration, contains('core.squad_revisions'));
    expect(migration, contains('core.squad_members'));
    expect(migration, contains('member_not_eligible'));
    expect(migration, contains('api.save_squad_draft'));
    expect(migration, contains('api.send_callups'));
  });

  test('response, attendance and delivery remain separate facts', () {
    expect(migration, contains('core.callup_responses'));
    expect(
      migration,
      contains("('unknown','present','late','partial','absent')"),
    );
    expect(migration, contains('internal.notification_outbox'));
    expect(migration, contains('internal.delivery_attempts'));
    expect(migration, contains('acting_as_person_id'));
  });

  test('S04 projection preserves explicit unknown and pending delivery', () {
    final value = SquadDetails.fromJson({
      'event_id': 'event-1',
      'squad_state': 'sent',
      'squad_revision': 2,
      'members': const [],
      'callups': [
        {
          'callup_id': 'c1',
          'person_id': 'p1',
          'name': 'Kim',
          'state': 'pending',
          'delivery_state': 'failed',
          'revision': 1,
        },
      ],
      'attendance': [
        {'person_id': 'p1', 'name': 'Kim', 'status': 'unknown', 'revision': 0},
      ],
      'caller_actions': ['record_attendance'],
    });
    expect(value.callups.single.state, 'pending');
    expect(value.callups.single.deliveryState, 'failed');
    expect(value.attendance.single.status, 'unknown');
  });
}
