import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260807224555_s03_event_calendar.sql',
  ).readAsStringSync();

  test('S03 schema binds event owner, teams, audience and recurrence', () {
    expect(migration, contains('foreign key (owning_team_id, club_id)'));
    expect(migration, contains('event_teams_one_primary_idx'));
    expect(migration, contains('event_primary_team_guard'));
    expect(migration, contains('unique (recurrence_id, occurrence_key)'));
    expect(migration, contains("relation in ('primary', 'shared')"));
  });

  test('S03 commands are revisioned, idempotent and atomic with outbox', () {
    for (final command in [
      'create_event',
      'revise_event',
      'transition_event',
    ]) {
      expect(migration, contains('create function api.$command'));
    }
    expect(migration, contains('internal.command_deduplication'));
    expect(migration, contains('internal.domain_outbox'));
    expect(migration, contains("message='stale_revision'"));
  });

  test('S03 closure adds opaque cursor, all-day guard and private realtime', () {
    final closure = File(
      'supabase/migrations/20260807231022_s03_cursor_all_day_private_realtime.sql',
    ).readAsStringSync();
    expect(closure, contains('events_all_day_local_boundaries_check'));
    expect(closure, contains('list_calendar_page'));
    expect(closure, contains("'base64'"));
    expect(closure, contains('realtime.send'));
    expect(closure, contains('teamzone_calendar_broadcast_select'));
    expect(closure, contains("'calendar:club:'"));
  });

  test('calendar projection parses UTC timestamps and caller-safe fields', () {
    final event = CalendarEventSummary.fromJson({
      'event_id': 'event-1',
      'club_id': 'club-1',
      'owning_team_id': 'team-1',
      'team_name': 'F2012',
      'title': 'Träning',
      'event_type': 'training',
      'state': 'scheduled',
      'starts_at': '2026-08-08T16:00:00Z',
      'ends_at': '2026-08-08T18:00:00Z',
      'all_day': false,
      'timezone': 'Europe/Stockholm',
      'location_name': 'Plan A',
      'revision': 1,
    });
    expect(event.startsAt.isUtc, isTrue);
    expect(event.locationName, 'Plan A');
    expect(event.revision, 1);
  });
}
