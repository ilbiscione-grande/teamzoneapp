import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827192907_home02_player_home.sql',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/overview/overview_surface.dart',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/calendar/calendar_services.dart',
  ).readAsStringSync();

  test('player projection is restricted to own linked person and team', () {
    expect(migration, contains("context_row.role_package<>'player'"));
    expect(migration, contains('link.profile_id=actor_id'));
    expect(migration, contains('callup.club_person_id=actor_person_id'));
    expect(migration, contains('relation.team_id=context_row.team_id'));
    expect(migration, isNot(contains('manage_roster')));
    expect(migration, isNot(contains('missing_attendance')));
  });

  test('player home contains team, next event, callups and messages', () {
    expect(migration, contains("'team'"));
    expect(migration, contains("'next_event'"));
    expect(migration, contains("'own_callups'"));
    expect(migration, contains("'unread_message_count'"));
    expect(surface, contains("this.callupTitle = 'Dina kallelser'"));
    expect(surface, contains("widget.onNavigate('/inbox')"));
  });

  test('quick response reuses revision and decline reason contract', () {
    expect(surface, contains('widget.calendar.respondCallup('));
    expect(surface, contains('expectedRevision: callup.revision'));
    expect(surface, contains('declineReasonCode: reasonCode'));
    expect(surface, contains('declineReasonText: reasonText'));
    expect(surface, contains("_respond(callup, 'tentative')"));
    expect(services, contains("'respond_callup'"));
  });

  test('player action has no guardian acting-as or leader administration', () {
    expect(
      migration,
      contains("null::uuid acting_as_person_id,'player'::text response_role"),
    );
    expect(surface, isNot(contains('respond_for_child')));
    expect(surface, isNot(contains('club.memberships.manage')));
  });
}
