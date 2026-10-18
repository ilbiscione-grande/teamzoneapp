import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

class _RefereeIdentity implements IdentityServices {
  const _RefereeIdentity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Anna', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context-ref',
      clubId: 'fdk',
      clubName: 'Njudungs FDK',
      teamId: 'domare',
      teamName: 'Domare',
      rolePackage: 'referee',
      capabilities: {'team.read'},
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

class _Referees extends UnconfiguredRefereeServices {
  @override
  Future<List<RefereeAssignment>> myAssignments() async {
    final start = DateTime.now().add(const Duration(hours: 3));
    return [
      RefereeAssignment.fromJson({
        'id': 'r1',
        'slot': 'main',
        'state': 'confirmed',
        'proposed_side': 'team',
        'name': 'Anna Domare',
        'match': {
          'event_id': 'other-club-match',
          'title': 'Match',
          'starts_at': start.toUtc().toIso8601String(),
          'ends_at': start
              .add(const Duration(hours: 2))
              .toUtc()
              .toIso8601String(),
          'team_name': 'J',
          'club_name': 'IF Eksjö Fotboll',
          'opponent_name': 'Vetlanda FF',
          'home_away': 'home',
          'location': 'Eksjö IP',
          'referee_slots': 1,
        },
        'awaiting_me': false,
      }),
    ];
  }
}

class _Calendar extends UnconfiguredCalendarServices {
  final _referees = _Referees();

  @override
  RefereeServices get referees => _referees;

  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

void main() {
  testWidgets('a referee sees their assignment in their own calendar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'ref02'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _RefereeIdentity(),
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
    final item = find.textContaining(
      'Domare: J (IF Eksjö Fotboll) – Vetlanda FF',
    );
    expect(item, findsWidgets);
    await tester.tap(item.first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-referee-assignment')),
      findsOneWidget,
    );
    expect(find.textContaining('Huvuddomare'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
