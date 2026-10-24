import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/team_development/team_development_services.dart';
import 'package:teamzone_app/src/features/workspaces/module_services.dart';

void main() {
  test('the plan reads its season, periods and goals', () {
    final plan = SeasonPlan.fromJson(const {
      'id': 'p',
      'title': 'Säsong 2026',
      'vision': 'Modigt',
      'starts_on': '2026-01-01',
      'ends_on': '2026-12-31',
      'revision': 3,
      'periods': [
        {
          'id': 'a',
          'name': 'Försäsong',
          'phase': 'preseason',
          'starts_on': '2026-01-01',
          'ends_on': '2026-03-31',
        },
        {
          'id': 'b',
          'name': 'Uppehåll',
          'phase': 'break',
          'starts_on': '2026-07-01',
          'ends_on': '2026-07-31',
        },
      ],
      'goals': [
        {'id': 'g', 'horizon': 'period', 'period_id': 'b', 'title': 'Vila'},
        {
          'id': 's',
          'horizon': 'short',
          'title': 'Hörnor',
          'target_on': '2026-05-01',
          'state': 'achieved',
        },
      ],
    });
    expect(plan.periods[1].phase, PeriodPhase.breakTime);
    expect(PeriodPhase.breakTime.key, 'break');
    expect(plan.periodOn(DateTime(2026, 2, 10))?.id, 'a');
    expect(plan.periodOn(DateTime(2026, 5, 1)), isNull);
    expect(plan.currentOrNext(DateTime(2026, 5, 1))?.id, 'b');
    expect(
      plan.goalsOf(GoalHorizon.period, periodId: 'b').single.title,
      'Vila',
    );
    expect(plan.goalsOf(GoalHorizon.short).single.state, GoalState.achieved);
  });

  testWidgets('a leader plans the season in the module', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = _Plans();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'tdp'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          modules: _Modules(services),
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
      find.byKey(const Key('workspace-module-module.team_development')),
    );
    await tester.pumpAndSettle();

    // The first season.
    expect(find.byKey(const Key('tdp-first-season')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tdp-create-season')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tdp-season-vision')),
      'Ett modigt lag',
    );
    await tester.tap(find.byKey(const Key('tdp-season-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-season-card')), findsOneWidget);
    expect(find.text('Ett modigt lag'), findsOneWidget);
    expect(services.created?.startsOn, DateTime(DateTime.now().year));

    // A period on the timeline, named after its phase.
    await tester.tap(find.text('Säsongen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-new-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Använd förslag'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-period-save')));
    await tester.pumpAndSettle();
    expect(services.plan!.periods.single.name, 'Försäsong');
    expect(services.plan!.periods.single.focus, startsWith('Grundspel'));

    // A goal of the season, marked achieved from its row.
    await tester.tap(find.text('Mål'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-new-goal')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tdp-goal-title')),
      'Alla spelar mycket',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-goal-save')));
    await tester.pumpAndSettle();
    expect(find.text('Alla spelar mycket'), findsOneWidget);
    await tester.tap(find.byTooltip('Markera som uppnått'));
    await tester.pumpAndSettle();
    expect(services.plan!.goals.single.state, GoalState.achieved);
  });
}

class _Plans implements TeamDevelopmentServices {
  SeasonPlan? plan;
  SeasonPlan? created;
  var _ids = 0;

  SeasonPlan _with({List<DevelopmentPeriod>? periods, List<TeamGoal>? goals}) =>
      plan = SeasonPlan(
        id: plan!.id,
        title: plan!.title,
        vision: plan!.vision,
        startsOn: plan!.startsOn,
        endsOn: plan!.endsOn,
        revision: plan!.revision + 1,
        periods: periods ?? plan!.periods,
        goals: goals ?? plan!.goals,
      );

  @override
  Future<TeamDevelopment> get(String teamId, {String? planId}) async =>
      TeamDevelopment(
        canEdit: true,
        seasons: [
          if (plan != null)
            SeasonSummary(
              id: plan!.id,
              title: plan!.title,
              startsOn: plan!.startsOn,
              endsOn: plan!.endsOn,
            ),
        ],
        plan: plan,
      );

  @override
  Future<SeasonPlan> createPlan({
    required String teamId,
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
  }) async => created = plan = SeasonPlan(
    id: 'plan',
    title: title,
    vision: vision,
    startsOn: startsOn,
    endsOn: endsOn,
    revision: 1,
  );

  @override
  Future<SeasonPlan> savePlan(
    SeasonPlan plan, {
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
  }) async => _with();

  @override
  Future<SeasonPlan> savePeriod(
    SeasonPlan plan, {
    String? periodId,
    required String name,
    required PeriodPhase phase,
    required DateTime startsOn,
    required DateTime endsOn,
    required String focus,
  }) async => _with(
    periods: [
      ...plan.periods.where((p) => p.id != periodId),
      DevelopmentPeriod(
        id: periodId ?? 'period-${_ids++}',
        name: name,
        phase: phase,
        startsOn: startsOn,
        endsOn: endsOn,
        focus: focus,
      ),
    ],
  );

  @override
  Future<SeasonPlan> deletePeriod(SeasonPlan plan, String periodId) async =>
      _with(periods: [...plan.periods.where((p) => p.id != periodId)]);

  @override
  Future<SeasonPlan> saveGoal(
    SeasonPlan plan, {
    String? goalId,
    required GoalHorizon horizon,
    String? periodId,
    required String title,
    required String description,
    DateTime? targetOn,
    required GoalState state,
  }) async => _with(
    goals: [
      for (final goal in plan.goals)
        if (goal.id != goalId) goal,
      TeamGoal(
        id: goalId ?? 'goal-${_ids++}',
        horizon: horizon,
        periodId: periodId,
        title: title,
        description: description,
        targetOn: targetOn,
        state: state,
      ),
    ],
  );

  @override
  Future<SeasonPlan> deleteGoal(SeasonPlan plan, String goalId) async =>
      _with(goals: [...plan.goals.where((g) => g.id != goalId)]);
}

class _Modules implements ModuleServices {
  _Modules(this.teamDevelopment);
  @override
  final TeamDevelopmentServices teamDevelopment;
  @override
  Future<TeamModules> getTeamModules({required String teamId}) async =>
      TeamModules.fromJson(const {
        'modules': [
          {
            'key': 'module.team_development',
            'title': 'Team Development Plan',
            'description': 'Säsongsmål och perioder',
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
      capabilities: {'development.manage', 'event.manage'},
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
