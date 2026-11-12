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
      CalendarEventSummary.fromJson({
        'event_id': 'event-a',
        'club_id': 'club',
        'owning_team_id': 'team-a',
        'team_name': 'A',
        'title': 'Träning',
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
    expect(tester.takeException(), isNull);
  });
}
