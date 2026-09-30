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
    await _openEditor(tester, calendar);
    // The form is split into clear sections, in this order.
    expect(find.byKey(const ValueKey('event-type-training')), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Titel'), findsNothing);
    for (final label in [
      'Typ av event',
      'När',
      'Samling före start (minuter)',
      'Återkommande serie',
      'Plats',
    ]) {
      await _scrollTo(tester, find.text(label));
      expect(find.text(label), findsWidgets);
    }
    await _scrollTo(tester, find.text('Arena A'));
    await tester.tap(find.text('Arena A'));
    for (final label in [
      'Målgrupp',
      'Detaljer',
      'Beskrivning',
      'Spara som utkast',
      'Fler inställningar',
    ]) {
      await _scrollTo(tester, find.text(label));
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Skapa').last);
    await tester.pumpAndSettle();
    expect(calendar.created?.title, 'Träning');
    expect(calendar.created?.state, 'scheduled');
    expect(calendar.created?.locationName, 'Arena A');
    expect(calendar.created?.audiences, containsAll(['players', 'leaders']));
    expect(calendar.created?.assemblyMinutesBefore, 15);
  });

  testWidgets('match asks for the opponent and keeps home or away', (
    tester,
  ) async {
    final calendar = _Calendar();
    await _openEditor(tester, calendar);
    await tester.tap(find.byKey(const ValueKey('event-type-match')));
    await tester.pumpAndSettle();
    // Save without an opponent names the problem.
    await tester.tap(find.text('Skapa').last);
    await tester.pumpAndSettle();
    expect(find.text('Ange motståndare.'), findsOneWidget);
    expect(calendar.created, isNull);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Motståndare *'),
      'Bergby FF',
    );
    await tester.tap(find.text('Borta'));
    await _scrollTo(tester, find.byKey(const ValueKey('event-save-as-draft')));
    await tester.tap(find.byKey(const ValueKey('event-save-as-draft')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skapa').last);
    await tester.pumpAndSettle();
    expect(calendar.created?.type, 'match');
    expect(calendar.created?.title, 'vs Bergby FF');
    expect(calendar.created?.homeAway, 'away');
    expect(calendar.created?.state, 'draft');
    // Matches gather earlier by default.
    expect(calendar.created?.assemblyMinutesBefore, 75);
  });

  testWidgets('saved place fills facility, pitch and surface together', (
    tester,
  ) async {
    final calendar = _Calendar();
    await _openEditor(tester, calendar);
    final chip = find.byKey(
      const ValueKey('saved-place-Bergby IP · Plan 3 · Konstgräs'),
    );
    await _scrollTo(tester, chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    String text(String key) => tester
        .widget<TextFormField>(find.byKey(ValueKey(key)))
        .controller!
        .text;
    expect(text('event-place-facility'), 'Bergby IP');
    expect(text('event-place-pitch'), 'Plan 3');
    expect(text('event-place-surface'), 'Konstgräs');
    // A new surface on the same pitch is its own saved combination.
    await tester.enterText(
      find.byKey(const ValueKey('event-place-surface')),
      'Naturgräs',
    );
    await tester.tap(find.text('Skapa').last);
    await tester.pumpAndSettle();
    expect(calendar.created?.locationName, 'Bergby IP');
    expect(calendar.created?.locationPitch, 'Plan 3');
    expect(calendar.created?.locationSurface, 'Naturgräs');
  });

  testWidgets('pitch without a facility is refused', (tester) async {
    final calendar = _Calendar();
    await _openEditor(tester, calendar);
    final pitch = find.byKey(const ValueKey('event-place-pitch'));
    await _scrollTo(tester, pitch);
    await tester.enterText(pitch, 'Plan 2');
    await tester.tap(find.text('Skapa').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Ange anläggning för planen och underlaget.'),
      findsOneWidget,
    );
    expect(calendar.created, isNull);
  });

  testWidgets('phone gets a full-screen editor without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openEditor(tester, _Calendar());
    final dialog = tester.getSize(find.byType(Dialog));
    expect(dialog.width, 390);
    expect(find.byKey(const ValueKey('event-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('event-start-time')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('event-type-match')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
    final typedSql = File(
      'supabase/migrations/20260915104026_cal02_typed_event_fields_and_assembly.sql',
    ).readAsStringSync().toLowerCase();
    expect(typedSql, contains('assembly_minutes_before'));
    expect(typedSql, contains('opponent_name'));
    expect(typedSql, contains('training_plan'));
    expect(typedSql, contains('meeting_agenda'));
    expect(typedSql, contains('revise_event_v3_for_actor'));
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

Future<void> _openEditor(WidgetTester tester, _Calendar calendar) async {
  await tester.pumpWidget(_app(calendar));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kalender'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Nytt event'));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
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
  Future<List<SavedEventPlace>> listSavedPlaces({
    required String clubId,
    required String teamId,
  }) async => const [
    SavedEventPlace(name: 'Arena A'),
    SavedEventPlace(name: 'Bergby IP', pitch: 'Plan 3', surface: 'Konstgräs'),
  ];
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
