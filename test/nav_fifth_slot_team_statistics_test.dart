import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/preferences/navigation_preferences.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

TeamZoneContext context0({
  required String role,
  Set<String> capabilities = const {},
  String? teamId = 'team',
}) => TeamZoneContext(
  id: 'assignment-$role',
  clubId: 'club',
  clubName: 'Testklubben',
  teamId: teamId,
  teamName: teamId == null ? null : 'F2012',
  rolePackage: role,
  capabilities: capabilities,
);

const statsJson = {
  'events': {'total': 6, 'training': 4, 'match': 2, 'other': 0},
  'attendance_rate': 75.0,
  'training_rate': 80.0,
  'match_rate': 66.7,
  'response_rate': 90.0,
  'late': 2,
  'months': [
    {'month': '2026-09', 'attendance_rate': 70.0},
    {'month': '2026-10', 'attendance_rate': 82.0},
  ],
  'people': [
    {
      'person_id': 'p1',
      'name': 'Anna',
      'role': 'player',
      'attended': 6,
      'counted': 6,
      'trainings_attended': 4,
      'trainings_counted': 4,
      'matches_attended': 2,
      'matches_counted': 2,
      'late': 0,
      'callups': 2,
      'answered': 2,
    },
    {
      'person_id': 'p2',
      'name': 'Bo',
      'role': 'player',
      'attended': 1,
      'counted': 4,
      'trainings_attended': 1,
      'trainings_counted': 3,
      'matches_attended': 0,
      'matches_counted': 1,
      'late': 1,
      'callups': 1,
      'answered': 0,
    },
    {
      'person_id': 'p3',
      'name': 'Cia',
      'role': 'player',
      'attended': 1,
      'counted': 2,
      'trainings_attended': 1,
      'trainings_counted': 2,
      'matches_attended': 0,
      'matches_counted': 0,
      'late': 0,
      'callups': 0,
      'answered': 0,
    },
    {
      'person_id': 'l1',
      'name': 'Lisa',
      'role': 'leader',
      'attended': 5,
      'counted': 6,
      'trainings_attended': 4,
      'trainings_counted': 4,
      'matches_attended': 1,
      'matches_counted': 2,
      'late': 0,
      'callups': 0,
      'answered': 0,
    },
  ],
};

void main() {
  group('fifth slot', () {
    const player = FifthSlotAccess(
      isLeader: false,
      hasEconomy: false,
      hasBoard: false,
    );
    const leader = FifthSlotAccess(
      isLeader: true,
      hasEconomy: true,
      hasBoard: false,
    );
    const treasurer = FifthSlotAccess(
      isLeader: false,
      hasEconomy: true,
      hasBoard: true,
    );
    const boardMember = FifthSlotAccess(
      isLeader: false,
      hasEconomy: false,
      hasBoard: true,
    );

    test('defaults follow the role', () {
      expect(player.roleDefault, FifthSlot.settings);
      expect(leader.roleDefault, FifthSlot.workspaces);
      expect(treasurer.roleDefault, FifthSlot.economy);
      expect(boardMember.roleDefault, FifthSlot.board);
    });

    test('only allowed options are offered', () {
      expect(player.options, [FifthSlot.settings, FifthSlot.development]);
      expect(leader.options, [
        FifthSlot.settings,
        FifthSlot.workspaces,
        FifthSlot.development,
        FifthSlot.economy,
      ]);
    });

    test('an own choice wins when allowed, else the role default', () {
      expect(player.resolve(FifthSlot.development), FifthSlot.development);
      expect(player.resolve(FifthSlot.economy), FifthSlot.settings);
      expect(player.resolve(FifthSlot.workspaces), FifthSlot.settings);
      expect(leader.resolve(null), FifthSlot.workspaces);
      expect(leader.resolve(FifthSlot.economy), FifthSlot.economy);
      expect(FifthSlot.fromName('board'), FifthSlot.board);
      expect(FifthSlot.fromName('statistics'), isNull);
    });
  });

  test('team statistics parse and rank the lowest attendance', () {
    final stats = TeamStatistics.fromJson(statsJson);
    expect(stats.events, 6);
    expect(stats.attendanceRate, 75);
    expect(stats.players.map((p) => p.name), ['Anna', 'Bo', 'Cia']);
    expect(stats.leaders.single.name, 'Lisa');
    // Cia has too few counted events to be a trend.
    expect(stats.lowestAttendance().map((p) => p.name), ['Bo', 'Anna']);
    expect(stats.people[1].rate, 25);
    expect(
      TeamStatisticsPerson.fromJson(const {
        'person_id': 'x',
        'counted': 0,
      }).rate,
      isNull,
    );
  });

  group('bottom bar', () {
    Future<void> pumpPhone(
      WidgetTester tester,
      TeamZoneContext context, {
      NavigationPreferences? preferences,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'nav'),
          locale: const Locale('sv'),
          services: AppServices(
            identity: _Identity([context]),
            roster: _Roster(),
            navigationPreferences:
                preferences ?? const StatelessNavigationPreferences(),
            isConfigured: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> labels(WidgetTester tester) => [
      for (final destination in tester.widgetList<NavigationDestination>(
        find.byType(NavigationDestination),
      ))
        destination.label,
    ];

    testWidgets('players get Inställningar, never Statistik', (tester) async {
      await pumpPhone(tester, context0(role: 'player'));
      expect(labels(tester), [
        'Laget',
        'Kalender',
        'Hem',
        'Inbox',
        'Inställningar',
      ]);
    });

    testWidgets('leaders get Arbetsytor', (tester) async {
      await pumpPhone(tester, context0(role: 'leader'));
      expect(labels(tester).last, 'Arbetsytor');
      await tester.tap(find.text('Arbetsytor'));
      await tester.pumpAndSettle();
      expect(find.text('Planerade arbetsytor'), findsOneWidget);
      expect(find.byKey(const Key('workspace-development')), findsOneWidget);
    });

    testWidgets('a club treasurer gets Ekonomi', (tester) async {
      await pumpPhone(
        tester,
        context0(
          role: 'club_functionary',
          teamId: null,
          capabilities: {'economy.read'},
        ),
      );
      expect(labels(tester).last, 'Ekonomi');
    });

    testWidgets('an own choice is used when allowed', (tester) async {
      final preferences = MemoryNavigationPreferences();
      await preferences.writeFifthSlot(FifthSlot.development);
      await pumpPhone(
        tester,
        context0(role: 'player'),
        preferences: preferences,
      );
      expect(labels(tester).last, 'Utveckling');
    });

    testWidgets('a choice the role does not allow falls back', (tester) async {
      final preferences = MemoryNavigationPreferences();
      await preferences.writeFifthSlot(FifthSlot.economy);
      await pumpPhone(
        tester,
        context0(role: 'player'),
        preferences: preferences,
      );
      expect(labels(tester).last, 'Inställningar');
    });
  });

  testWidgets('Laget → Statistik for team managers; /statistics redirects', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final roster = _Roster();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'stats'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity([
            context0(role: 'leader', capabilities: {'event.attendance.manage'}),
          ]),
          roster: roster,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The old destination now lands on the team statistics tab.
    GoRouter.of(tester.element(find.byType(Navigator).last)).go('/statistics');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Statistik'),
      ),
      findsOneWidget,
    );
    expect(find.text('75 %'), findsOneWidget);
    expect(find.text('Närvaro per månad'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('team-statistics-lowest-p2')),
      findsOneWidget,
    );
    expect(roster.requests, hasLength(1));
    final first = roster.requests.single;
    expect(first.to.difference(first.from).inDays, 90);

    await tester.tap(find.text('30 dagar'));
    await tester.pumpAndSettle();
    expect(roster.requests, hasLength(2));
    expect(
      roster.requests.last.to.difference(roster.requests.last.from).inDays,
      30,
    );
  });

  testWidgets('players see no Statistik tab in Laget', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'stats'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity([
            context0(role: 'player', capabilities: {'team.roster.view'}),
          ]),
          roster: _Roster(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Statistik'),
      ),
      findsNothing,
    );
  });
}

class _Roster extends UnconfiguredRosterServices {
  final requests = <({DateTime from, DateTime to})>[];

  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) async =>
      const TeamOverview(
        teamId: 'team',
        clubId: 'club',
        teamName: 'F2012',
        clubName: 'Testklubben',
        leaders: [],
        memberCount: 0,
        canManage: false,
        activeInvitationCount: 0,
        pendingApplicationCount: 0,
      );

  @override
  Future<TeamStatistics> getTeamStatistics({
    required String teamId,
    required DateTime from,
    required DateTime to,
  }) async {
    requests.add((from: from, to: to));
    return TeamStatistics.fromJson(statsJson);
  }
}

class _Identity implements IdentityServices {
  _Identity(this.contexts);
  final List<TeamZoneContext> contexts;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<List<TeamZoneContext>> getContexts() async => contexts;
  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'profile',
    displayName: 'Testare',
    locale: 'sv',
  );
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}
