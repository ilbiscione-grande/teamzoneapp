import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

void main() {
  testWidgets('leader creates a complete event using a saved club location', (
    tester,
  ) async {
    final calendar = _Calendar();
    await tester.pumpWidget(_app(calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nytt event'));
    await tester.pumpAndSettle();
    for (final label in [
      'Titel',
      'Beskrivning',
      'Typ',
      'Status',
      'Start',
      'Slut',
      'Tidszon',
      'Plats',
      'Audience',
      'Återkommande serie',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Arena A'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Titel'),
      'Träning A',
    );
    await tester.ensureVisible(find.text('Arena A'));
    await tester.tap(find.text('Arena A'));
    await tester.ensureVisible(find.text('Skapa').last);
    await tester.tap(find.text('Skapa').last);
    await tester.pumpAndSettle();
    expect(calendar.created?.title, 'Träning A');
    expect(calendar.created?.locationName, 'Arena A');
    expect(calendar.created?.audiences, containsAll(['players', 'leaders']));
  });

  test('CAL-02 SQL scopes saved places and shifts series relatively', () {
    final sql = File(
      'supabase/migrations/20260827063902_cal02_event_editor_locations.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('list_saved_event_locations_for_actor'));
    expect(sql, contains('location.club_id=target_club_id'));
    expect(sql, contains("'one','forward','all'"));
    expect(sql, contains('target.starts_at+start_delta'));
    expect(sql, contains('new_start+new_duration'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('expected_revision'));
    expect(sql, contains("'audience_types'"));
    expect(sql, contains("'event_type'"));
    expect(sql, contains("'location_name'"));
    expect(sql, contains('revoke all on function'));
  });

  test('create input retains explicit state, audience and recurrence', () {
    final input = CreateEventInput(
      clubId: 'club',
      teamId: 'team',
      title: 'Match',
      type: 'match',
      state: 'draft',
      startsAt: DateTime(2026, 8, 28, 18),
      endsAt: DateTime(2026, 8, 28, 20),
      timezone: 'Europe/Stockholm',
      audiences: const ['players', 'guardians'],
      recurrenceFrequency: 'weekly',
      recurrenceInterval: 2,
      recurrenceCount: 6,
    );
    expect(input.state, 'draft');
    expect(input.audiences, ['players', 'guardians']);
    expect(input.recurrenceInterval, 2);
    expect(input.recurrenceCount, 6);
  });
}

Widget _app(_Calendar calendar) => TeamZoneApp(
  environment: const AppEnvironment(name: 'cal02'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: const _Identity(),
    calendar: calendar,
    isConfigured: true,
  ),
);

class _Calendar extends UnconfiguredCalendarServices {
  CreateEventInput? created;
  @override
  Future<List<String>> listSavedLocations({
    required String clubId,
    required String teamId,
  }) async => const ['Arena A'];
  @override
  Future<String> createEvent(
    CreateEventInput input,
    String idempotencyKey,
  ) async {
    created = input;
    return 'event';
  }
}

class _Identity implements IdentityServices {
  const _Identity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'leader',
      capabilities: {'team.read', 'event.manage'},
    ),
  ];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}
