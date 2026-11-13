import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

class _FunctionaryIdentity implements IdentityServices {
  const _FunctionaryIdentity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Ulf', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context-club',
      clubId: 'club',
      clubName: 'IF Eksjö Fotboll',
      rolePackage: 'club_functionary',
      capabilities: {'club.read'},
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

class _Calendar extends UnconfiguredCalendarServices {
  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async {
    final start = DateTime.now().add(const Duration(hours: 3));
    return [
      for (final (id, team, title) in [
        ('a', 'A', 'Träning'),
        ('b', 'B', 'Lagmöte'),
      ])
        CalendarEventSummary.fromJson({
          'event_id': 'event-$id',
          'club_id': 'club',
          'owning_team_id': 'team-$id',
          'team_name': team,
          'title': title,
          'event_type': 'training',
          'state': 'scheduled',
          'starts_at': start.toUtc().toIso8601String(),
          'ends_at': start
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          'all_day': false,
          'timezone': 'Europe/Stockholm',
          'location_name': 'Ränneborg',
          'revision': 1,
          'can_open': false,
        }),
    ];
  }
}

void main() {
  testWidgets('a club functionary sees team activities and what they are', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'cal-club'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _FunctionaryIdentity(),
          calendar: _Calendar(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Vy och filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    final item = find.textContaining('Träning');
    expect(item, findsWidgets);
    await tester.tap(item.first);
    await tester.pumpAndSettle();
    // Not the event page: a sheet with what, when and where.
    expect(
      find.byKey(const ValueKey('calendar-team-activity')),
      findsOneWidget,
    );
    expect(find.textContaining('Ränneborg'), findsWidgets);
    expect(find.textContaining('Lagets ledare och spelare'), findsOneWidget);
    // The team opens read-only from the sheet.
    await tester.tap(
      find.byKey(const ValueKey('calendar-team-activity-open-team')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-team-page-team-a')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the team filter lists the club teams and filters them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'cal-club'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _FunctionaryIdentity(),
          calendar: _Calendar(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Vy och filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Lagmöte'), findsWidgets);
    await tester.tap(find.byTooltip('Vy och filter'));
    await tester.pumpAndSettle();
    final chips = find.byKey(const Key('calendarTeamFilter'));
    expect(
      find.descendant(of: chips, matching: find.text('B')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: chips, matching: find.text('A')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendarFilterClose')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Träning'), findsWidgets);
    expect(find.textContaining('Lagmöte'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
