import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/match_workspace/lineup_suggestion_services.dart';
import 'package:teamzone_app/src/features/match_workspace/match_plan_services.dart';
import 'package:teamzone_app/src/features/team_development/team_development_services.dart';
import 'package:teamzone_app/src/features/workspaces/module_services.dart';

void main() {
  testWidgets(
    'Föreslå fills the line-up from the team formation, with reasons',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final suggestions = _Suggestions();
      LineupSuggestionFeature.services = suggestions;
      addTearDown(
        () => LineupSuggestionFeature.services =
            const UnconfiguredLineupSuggestionServices(),
      );
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
      await tester.tap(find.byKey(const Key('module-open-next-match')));
      await tester.pumpAndSettle();

      // Without a team formation: by position, from everyone not declined.
      await tester.tap(find.byKey(const Key('lineup-suggest')));
      await tester.pumpAndSettle();
      expect(
        suggestions.calls.single.toString(),
        "(null, 2-3-1, 7v7, [ali, mia])",
      );
      final reasons = find.byKey(const Key('lineup-suggestion-reasons'));
      expect(reasons, findsOneWidget);
      expect(
        find.descendant(of: reasons, matching: find.textContaining('Mia')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: reasons,
          matching: find.textContaining('Huvudposition · + Huvudspel'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: reasons,
          matching: find.textContaining('− Långa inkast'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '2/7 på planen · tryck för att välja spelare, dra för att flytta',
        ),
        findsOneWidget,
      );

      // The team's formation is offered and used.
      await tester.tap(find.byKey(const Key('lineup-formation')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press (3-2-1)').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lineup-suggestion-reasons')), findsNothing);
      await tester.tap(find.byKey(const Key('lineup-suggest')));
      await tester.pumpAndSettle();
      expect(suggestions.calls.last.$1, 'f1');
      expect(suggestions.calls.last.$2, '3-2-1');
      expect(tester.takeException(), isNull);
    },
  );
}

class _Suggestions implements LineupSuggestionServices {
  final calls = <(String?, String, String, List<String>)>[];
  @override
  Future<TeamFormationList> formations(
    String eventId,
  ) async => TeamFormationList.fromJson({
    'formations': [
      {'id': 'f1', 'name': 'Press', 'lines': '3-2-1', 'match_format': '7v7'},
      {'id': 'f2', 'name': 'Elva', 'lines': '4-3-3', 'match_format': '11v11'},
    ],
    'custom': [
      {'id': 'c1', 'label': 'Långa inkast'},
    ],
  });
  @override
  Future<List<SuggestedPlace>> suggest({
    required String eventId,
    String? formationId,
    required String lines,
    required String matchFormat,
    required List<String> candidates,
  }) async {
    calls.add((formationId, lines, matchFormat, candidates));
    return suggestedPlacesFromJson({
      'slots': [
        {
          'code': 'GK',
          'person_id': 'mia',
          'score': 16,
          'position_fit': 'main',
          'strengths': ['heading'],
          'development': <String>[],
        },
        {
          'code': '1A',
          'person_id': 'ali',
          'score': 1,
          'position_fit': 'none',
          'strengths': <String>[],
          'development': ['c1'],
        },
        {'code': '1B', 'person_id': null},
      ],
    });
  }
}

class _Plans extends UnconfiguredMatchPlanServices {
  @override
  Future<MatchLineup?> getLineup(String eventId) async =>
      MatchLineup.fromJson(const {
        'can_edit': true,
        'published': false,
        'revision': 1,
        'formation': '2-3-1',
        'match_format': '7v7',
        'players': [
          {
            'person_id': 'mia',
            'name': 'Mia Målvakt',
            'main_position': 'goalkeeper',
          },
          {'person_id': 'ali', 'name': 'Ali Back'},
        ],
      });

  @override
  Future<List<ModuleMatch>> listMatches({
    required String teamId,
    required DateTime from,
    required DateTime to,
  }) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 12);
    return [
      if (!tomorrow.isBefore(from) && tomorrow.isBefore(to))
        ModuleMatch(
          eventId: 'match',
          title: 'Imorgon IF',
          opponentName: 'Imorgon IF',
          startsAt: tomorrow,
          state: 'scheduled',
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
