import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  test('sharing settings parse explicit team capabilities and audience', () {
    final settings = EventSharingSettings.fromJson({
      'event_id': 'event-1',
      'revision': 4,
      'teams': [
        {
          'team_id': 'team-2',
          'name': 'F17',
          'selected': true,
          'capabilities': ['view', 'manage_roster'],
        },
      ],
      'audiences': [
        {'type': 'players', 'team_id': 'team-2'},
      ],
    });

    expect(settings.revision, 4);
    expect(settings.teams.single.selected, isTrue);
    expect(settings.teams.single.capabilities, contains('manage_roster'));
    expect(settings.audiences.single['type'], 'players');
  });

  test('CAL-03 migration keeps audience separate from mutation rights', () {
    final migration = File(
      'supabase/migrations/20260827070512_cal03_shared_event_access.sql',
    ).readAsStringSync();

    expect(migration, contains('actor_can_manage_event_sharing'));
    expect(migration, contains("relation.relation='primary'"));
    expect(migration, contains('actor_can_manage_event_roster'));
    expect(migration, contains("array['manage_roster','co_manage']"));
    expect(migration, contains("'manage_sharing'"));
    expect(migration, contains("'event.sharing.update.v1'"));
    expect(
      migration,
      isNot(contains('actor_can_read_event(target_event_id) or')),
    );
  });
}
