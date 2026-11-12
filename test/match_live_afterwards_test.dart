import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/match/match_models.dart';
import 'package:teamzone_app/src/features/match/match_services.dart';
import 'package:teamzone_app/src/features/match_workspace/match_plan_services.dart';
import 'package:teamzone_app/src/features/team_development/team_development_services.dart';
import 'package:teamzone_app/src/features/workspaces/module_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'));
    await font.load();
  });

  Future<_Match> openLive(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final match = _Match();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'verification'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          modules: _Modules(),
          calendar: _Calendar(),
          match: match,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-workspace-match_workspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spelade'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Yesterday United'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('module-match-phase')),
        matching: find.text('Live'),
      ),
    );
    await tester.pumpAndSettle();
    return match;
  }

  testWidgets('a played match is filled in afterwards in Live', (tester) async {
    final match = await openLive(tester);
    expect(find.byKey(const Key('live-afterwards')), findsOneWidget);
    expect(find.byKey(const Key('live-clock')), findsNothing);

    // A shot with its minute typed in.
    await tester.tap(find.text('Avslut').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-sheet-minute')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '37');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'OK').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-sheet-result-on_target')));
    await tester.tap(find.byKey(const Key('live-sheet-save')));
    await tester.pumpAndSettle();
    expect(match.recorded.single, ('shot', 37, 'us', null, null));

    // A second yellow card is a red one.
    await tester.tap(find.text('Foul').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live-sheet-result-yellow')));
    await tester.tap(find.byKey(const Key('live-sheet-Spelare')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hugo Olofsson').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-sheet-second-yellow')), findsOneWidget);
    await tester.tap(find.byKey(const Key('live-sheet-save')));
    await tester.pumpAndSettle();
    expect(match.details.last, {'color': 'red', 'second_yellow': true});

    // An opponent's own goal.
    await tester.tap(find.byKey(const Key('live-goal-us')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-sheet-own-goal')));
    await tester.pumpAndSettle();
    expect(match.recorded.last.$1, 'goal');
    expect(match.details.last, {'own_goal': true});
    expect(find.textContaining('Självmål'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _Match extends UnconfiguredMatchServices {
  final recorded = <(String, int, String?, String?, String?)>[];
  final details = <Map<String, Object?>>[];
  final _facts = <Map<String, dynamic>>[
    {
      'id': 'yellow',
      'fact_type': 'card',
      'minute': 20,
      'side': 'us',
      'club_person_id': 'hugo',
      'detail': {'color': 'yellow'},
    },
  ];

  @override
  Future<MatchSnapshot> getSnapshot(String eventId) async => MatchSnapshot(
    eventId: eventId,
    state: 'completed',
    revision: 1,
    rosterRevision: 1,
    scoreUs: 1,
    scoreOpponent: 0,
    cursor: '',
    clock: const {
      'period_minutes': [30, 30],
    },
    canManage: true,
    roster: const [
      MatchRosterMember(
        personId: 'hugo',
        name: 'Hugo Olofsson',
        sourceState: 'accepted',
      ),
    ],
    people: const {'hugo': 'Hugo Olofsson'},
    facts: [..._facts],
  );

  @override
  Future<void> recordEvent(
    String id,
    String eventId, {
    required String type,
    required int minute,
    String? side,
    String? playerId,
    String? secondaryId,
    Map<String, Object?> detail = const {},
  }) async {
    recorded.add((type, minute, side, playerId, secondaryId));
    details.add(detail);
    _facts.add({
      'id': id,
      'fact_type': type,
      'minute': minute,
      'side': side,
      'club_person_id': playerId,
      'secondary_club_person_id': secondaryId,
      'detail': detail,
      'source_command_id': id,
    });
  }
}

class _Plans extends UnconfiguredMatchPlanServices {
  @override
  Future<MatchPlan?> getPlan(String eventId) async => MatchPlan(
    eventId: eventId,
    canEdit: true,
    published: false,
    revision: 1,
    tactics: const MatchPlanSection(),
    setPieces: const MatchPlanSection(),
    opponent: const MatchPlanSection(),
  );

  @override
  Future<List<ModuleMatch>> listMatches({
    required String teamId,
    required DateTime from,
    required DateTime to,
  }) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
    return [
      if (!yesterday.isBefore(from) && yesterday.isBefore(to))
        ModuleMatch(
          eventId: 'played',
          title: 'Yesterday United',
          opponentName: 'Yesterday United',
          startsAt: yesterday,
          state: 'completed',
          plan: 'none',
          lineup: 'none',
        ),
    ];
  }
}

class _Calendar extends UnconfiguredCalendarServices {
  @override
  final MatchPlanServices matchPlans = _Plans();
}

class _Modules implements ModuleServices {
  @override
  TeamDevelopmentServices get teamDevelopment =>
      const UnconfiguredTeamDevelopmentServices();
  @override
  Future<TeamModules> getTeamModules({required String teamId}) async =>
      TeamModules.fromJson(const {
        'modules': [
          {
            'key': 'module.match_workspace',
            'title': 'Match',
            'description': 'Matchplan',
            'beta': true,
            'access': 'write',
          },
        ],
      });
}

class _Identity implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'leader',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'P2012',
      rolePackage: 'leader',
      capabilities: {'event.manage'},
    ),
  ];
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
