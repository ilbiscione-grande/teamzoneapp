import 'package:flutter/services.dart';
import 'package:teamzone_app/src/features/match/match_models.dart';
import 'package:teamzone_app/src/features/match/match_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
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
  testWidgets(
    'English match planning and analysis translate system labels and keep team content',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'verification'),
          locale: const Locale('en'),
          services: AppServices(
            identity: _Identity(),
            modules: _Modules(),
            calendar: _Calendar(),
            match: _EnglishMatch(),
            isConfigured: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bottom-nav-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workspaces'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('workspace-module-module.match_workspace')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Next match · Tomorrow'), findsOneWidget);
      await tester.tap(find.byKey(const Key('module-open-next-match')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('match-preparation-part')),
          matching: find.text('Match plan'),
        ),
      );
      await tester.pumpAndSettle();
      final planScroll = find
          .ancestor(
            of: find.byKey(const Key('match-plan-tactics')),
            matching: find.byType(Scrollable),
          )
          .first;
      final segments = tester.getRect(
        find.byKey(const Key('module-match-phase')),
      );
      final analysisLabel = tester.getRect(find.text('Post-match analysis'));
      expect(analysisLabel.top, greaterThanOrEqualTo(segments.top + 4));
      expect(analysisLabel.bottom, lessThanOrEqualTo(segments.bottom - 4));
      expect(find.text('Tactics'), findsOneWidget);
      expect(find.text('Defence:'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Svensk taktik'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Set pieces'),
        200,
        scrollable: planScroll,
      );
      expect(find.text('Corners for:'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Opponent and key players'),
        200,
        scrollable: planScroll,
      );
      expect(find.text('Strengths:'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Played'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Yesterday United'));
      await tester.pumpAndSettle();
      expect(find.text('Final score'), findsOneWidget);
      expect(find.text('Shots'), findsOneWidget);
      expect(find.text('On target'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('live-timeline')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('Hugo Olofsson'), findsWidgets);
      expect(find.text('Svensk matchanteckning'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('yesterday belongs to played matches, not upcoming matches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'verification'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          modules: _Modules(),
          calendar: _Calendar(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom-nav-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbetsytor'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('workspace-module-module.match_workspace')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Yesterday United'), findsNothing);
    expect(find.textContaining('Tomorrow United'), findsWidgets);
    await tester.tap(find.text('Spelade'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Yesterday United'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Plans extends UnconfiguredMatchPlanServices {
  @override
  Future<MatchPlan?> getPlan(String eventId) async => MatchPlan(
    eventId: eventId,
    canEdit: true,
    published: false,
    revision: 1,
    tactics: const MatchPlanSection(text: 'Svensk taktik'),
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
    final today = DateTime(now.year, now.month, now.day);
    return [
          for (final entry in [
            (-1, 'Yesterday United'),
            (1, 'Tomorrow United'),
          ])
            ModuleMatch(
              eventId: '${entry.$1}',
              title: entry.$2,
              opponentName: entry.$2,
              startsAt: today.add(Duration(days: entry.$1, hours: 12)),
              state: 'scheduled',
              plan: 'none',
              lineup: 'none',
            ),
        ]
        .where(
          (match) =>
              !match.startsAt.isBefore(from) && match.startsAt.isBefore(to),
        )
        .toList();
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

class _EnglishMatch extends UnconfiguredMatchServices {
  @override
  Future<MatchSnapshot> getSnapshot(String eventId) async => MatchSnapshot(
    eventId: eventId,
    state: 'completed',
    revision: 1,
    rosterRevision: 1,
    scoreUs: 1,
    scoreOpponent: 0,
    cursor: '',
    clock: const {},
    people: const {'hugo': 'Hugo Olofsson'},
    facts: const [
      {
        'id': 'shot',
        'fact_type': 'shot',
        'minute': 10,
        'club_person_id': 'hugo',
        'side': 'us',
        'detail': {'result': 'on_target'},
      },
      {
        'id': 'note',
        'fact_type': 'note',
        'minute': 11,
        'detail': {'text': 'Svensk matchanteckning'},
      },
    ],
  );
}
