import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  test('event details parse archive metadata and lifecycle actions', () {
    final event = EventDetails.fromJson({
      'id': 'event-1',
      'title': 'Träning',
      'description': null,
      'event_type': 'training',
      'state': 'cancelled',
      'starts_at': '2026-08-27T17:00:00Z',
      'ends_at': '2026-08-27T18:30:00Z',
      'all_day': false,
      'timezone': 'Europe/Stockholm',
      'revision': 3,
      'caller_actions': ['archive'],
      'teams': <Map<String, dynamic>>[],
      'audiences': <Map<String, dynamic>>[],
      'archived_at': '2026-08-28T10:00:00Z',
      'archive_reason': 'Säsongen avslutad',
    });

    expect(event.can('archive'), isTrue);
    expect(event.archivedAt, DateTime.utc(2026, 8, 28, 10));
    expect(event.archiveReason, 'Säsongen avslutad');
  });

  test('CAL-04 migration separates deletion, archive and retention purge', () {
    final sql = File(
      'supabase/migrations/20260827072045_cal04_safe_event_lifecycle.sql',
    ).readAsStringSync();

    expect(sql, contains("event_row.state='draft'"));
    expect(sql, contains('event_row.recurrence_id is null'));
    expect(sql, contains('event_can_be_deleted_by_manager'));
    expect(sql, contains("token.state='issued'"));
    expect(sql, contains("state='revoked'"));
    expect(sql, contains("'callup.callup.cancelled.v1'"));
    expect(sql, contains("event_row.state not in('cancelled','completed')"));
    expect(sql, contains('retention_days<365'));
    expect(
      sql,
      contains(
        'grant execute on function internal.purge_archived_event(uuid,integer),api.purge_archived_event(uuid,integer) to service_role',
      ),
    );
  });
}
