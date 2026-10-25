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
