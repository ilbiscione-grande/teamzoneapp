import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  test('callup visibility is private by default in the client model', () {
    final squad = SquadDetails.fromJson({
      'event_id': 'event-1',
      'squad_state': 'locked',
    });

    expect(squad.showCallupsToMembers, isFalse);
    expect(squad.callupVisibilityRevision, 0);
  });

  test('callup visibility and revision are parsed from the projection', () {
    final squad = SquadDetails.fromJson({
      'event_id': 'event-1',
      'squad_state': 'locked',
      'show_callups_to_members': true,
      'callup_visibility_revision': 4,
      'caller_actions': ['set_callup_visibility'],
    });

    expect(squad.showCallupsToMembers, isTrue);
    expect(squad.callupVisibilityRevision, 4);
    expect(squad.can('set_callup_visibility'), isTrue);
  });

  test('CAL-10 migration enforces private server-side projections', () {
    final sql = File(
      'supabase/migrations/20260902104510_cal10_callup_roster_visibility.sql',
    ).readAsStringSync();

    expect(sql, contains('show_to_members boolean not null default false'));
    expect(sql, contains('internal.actor_can_manage_squad(target_event_id)'));
    expect(sql, contains('internal.actor_represents_club_person'));
    expect(sql, contains('can_manage or show_to_members or'));
    expect(
      sql,
      contains(
        'can_manage or internal.actor_represents_club_person',
      ),
    );
    expect(sql, contains("'event.callup_visibility.set.v1'"));
    expect(sql, contains("'set_callup_visibility'"));
  });

  test('CAL-10 explicitly restores its response-context dependency', () {
    final sql = File(
      'supabase/migrations/20260902115000_cal10_restore_callup_response_context_dependency.sql',
    ).readAsStringSync();

    expect(sql, contains('internal.actor_callup_response_context'));
    expect(sql, contains("'response_role','self'"));
    expect(sql, contains("'response_role','guardian'"));
    expect(sql, contains("relation.state='active'"));
  });

  test('CAL-10 explicitly restores its reminder-column dependencies', () {
    final sql = File(
      'supabase/migrations/20260902120500_cal10_restore_callup_reminder_columns.sql',
    ).readAsStringSync();

    expect(sql, contains('add column if not exists last_reminded_at'));
    expect(sql, contains('add column if not exists reminder_count'));
    expect(sql, contains('check(reminder_count>=0)'));
  });
}
