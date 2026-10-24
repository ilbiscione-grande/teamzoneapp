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

  test('the players see only what is shared, and the suggestion reads', () {
    final shared = SharedTeamPlan.fromJson(const {
      'title': 'Säsong 2026',
      'starts_on': '2026-01-01',
      'ends_on': '2026-12-31',
      'vision': null,
      'periods': null,
      'principles': [
        {'id': 'p', 'area': 'regaining', 'title': 'Fem sekunder'},
      ],
      'goals': [
        {
          'id': 'g',
          'horizon': 'season',
          'title': 'Alla spelar',
          'links': [
            {
              'id': 'l',
              'title': 'Film',
              'url': 'https://x.se',
              'visible': true,
            },
          ],
        },
      ],
    });
    expect(shared.periods, isNull, reason: 'not shared');
    expect(shared.principles!.single.area, PrincipleArea.regaining);
    expect(PrincipleArea.regaining.withBall, isFalse);
    expect(PrincipleArea.regaining.opposite, PrincipleArea.counter);
    expect(shared.goals!.single.links.single.title, 'Film');
    final suggestion = TeamPlanSuggestion.fromJson(const {
      'plan_title': 'Säsong 2026',
      'period': {'name': 'Vår', 'phase': 'competition', 'focus': 'Press'},
      'principles': [
        {'area': 'build_up', 'title': 'Via backlinjen'},
      ],
      'goals': [
        {'horizon': 'period', 'title': 'Vinn bollen högt'},
      ],
    });
    expect([suggestion.periodName, suggestion.periodFocus], ['Vår', 'Press']);
    expect(suggestion.principles.single.area, PrincipleArea.buildUp);
    expect(suggestion.goals, ['Vinn bollen högt']);
    expect(
      TeamPlanSuggestion.fromJson(const {'plan_title': 'x'}).isEmpty,
      isTrue,
    );
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

    // Checking the goal from its sheet.
    await tester.tap(find.text('Alla spelar mycket'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-goal-checkin')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I farozonen'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-checkin-save')));
    await tester.pumpAndSettle();
    final checkin = services.plan!.checkins.single;
    expect(checkin.status, CheckinStatus.atRisk);
    expect(checkin.goalId, services.plan!.goals.single.id);
    expect(find.byKey(ValueKey('tdp-checkin-${checkin.id}')), findsOneWidget);
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    // Spelidé: a principle and a key figure with a value.
    await tester.tap(find.text('Spelidé'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-new-principle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tdp-principle-title')),
      'Spela framåt när det går',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-principle-save')));
    await tester.pumpAndSettle();
    expect(find.text('Spela framåt när det går'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tdp-new-kpi')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tdp-kpi-title')), 'Avslut');
    await tester.enterText(find.byKey(const Key('tdp-kpi-target')), '12');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-kpi-save')));
    await tester.pumpAndSettle();
    final kpi = services.plan!.kpis.single;
    expect([kpi.title, kpi.target], ['Avslut', 12]);
    await tester.tap(find.byKey(ValueKey('tdp-kpi-${kpi.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-kpi-value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tdp-checkin-value')), '14,5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-checkin-save')));
    await tester.pumpAndSettle();
    expect(services.plan!.checkinsOfKpi(kpi.id).single.value, 14.5);
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    // Sharing with the players, per part, under Säsongen.
    await tester.tap(find.text('Säsongen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tdp-share-goals')));
    await tester.tap(find.byKey(const Key('tdp-share-goals')));
    await tester.pumpAndSettle();
    expect(services.plan!.sharing.goals, isTrue);
    expect(services.plan!.sharing.vision, isFalse);

    // A link on the goal, shown to the players.
    await tester.tap(find.text('Mål'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alla spelar mycket'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tdp-goal-add-link')));
    await tester.tap(find.byKey(const Key('tdp-goal-add-link')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tdp-link-title')), 'Film');
    await tester.enterText(
      find.byKey(const Key('tdp-link-url')),
      'https://example.com/film',
    );
    await tester.pump();
    await tester.tap(find.text('Visa för spelarna'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-link-save')));
    await tester.pumpAndSettle();
    final link = services.plan!.goals.single.links.single;
    expect([link.title, link.visible], ['Film', true]);
    expect(tester.takeException(), isNull);
  });
}

class _Plans implements TeamDevelopmentServices {
  SeasonPlan? plan;
  SeasonPlan? created;
  var _ids = 0;

  SeasonPlan _with({
    List<DevelopmentPeriod>? periods,
    List<TeamGoal>? goals,
    List<TeamPrinciple>? principles,
    List<TeamKpi>? kpis,
    List<TeamCheckin>? checkins,
    PlanSharing? sharing,
    bool revise = true,
  }) => plan = SeasonPlan(
    id: plan!.id,
    title: plan!.title,
    vision: plan!.vision,
    startsOn: plan!.startsOn,
    endsOn: plan!.endsOn,
    revision: plan!.revision + (revise ? 1 : 0),
    checkinEveryDays: plan!.checkinEveryDays,
    sharing: sharing ?? plan!.sharing,
    periods: periods ?? plan!.periods,
    goals: goals ?? plan!.goals,
    principles: principles ?? plan!.principles,
    kpis: kpis ?? plan!.kpis,
    checkins: checkins ?? plan!.checkins,
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
    int? checkinEveryDays,
  }) async => this.plan = SeasonPlan(
    id: plan.id,
    title: title,
    vision: vision,
    startsOn: startsOn,
    endsOn: endsOn,
    revision: plan.revision + 1,
    checkinEveryDays: checkinEveryDays,
    periods: plan.periods,
    goals: plan.goals,
  );

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

  @override
  Future<SeasonPlan> savePrinciple(
    SeasonPlan plan, {
    String? principleId,
    required PrincipleArea area,
    required String title,
    required String description,
  }) async => _with(
    principles: [
      ...plan.principles.where((p) => p.id != principleId),
      TeamPrinciple(
        id: principleId ?? 'principle-${_ids++}',
        area: area,
        title: title,
        description: description,
      ),
    ],
  );

  @override
  Future<SeasonPlan> deletePrinciple(SeasonPlan plan, String id) async =>
      _with(principles: [...plan.principles.where((p) => p.id != id)]);

  @override
  Future<SeasonPlan> saveKpi(
    SeasonPlan plan, {
    String? kpiId,
    required String title,
    required String unit,
    double? target,
    required bool higherIsBetter,
  }) async => _with(
    kpis: [
      ...plan.kpis.where((k) => k.id != kpiId),
      TeamKpi(
        id: kpiId ?? 'kpi-${_ids++}',
        title: title,
        unit: unit,
        target: target,
        higherIsBetter: higherIsBetter,
      ),
    ],
  );

  @override
  Future<SeasonPlan> deleteKpi(SeasonPlan plan, String id) async =>
      _with(kpis: [...plan.kpis.where((k) => k.id != id)]);

  @override
  Future<SeasonPlan> addCheckin(
    SeasonPlan plan, {
    String? goalId,
    String? kpiId,
    required DateTime checkedOn,
    CheckinStatus? status,
    double? value,
    required String note,
  }) async => _with(
    revise: false,
    checkins: [
      TeamCheckin(
        id: 'checkin-${_ids++}',
        goalId: goalId,
        kpiId: kpiId,
        checkedOn: checkedOn,
        status: status,
        value: value,
        note: note,
      ),
      ...plan.checkins,
    ],
  );

  @override
  Future<SeasonPlan> deleteCheckin(SeasonPlan plan, String id) async => _with(
    revise: false,
    checkins: [...plan.checkins.where((c) => c.id != id)],
  );

  @override
  Future<SeasonPlan> setSharing(SeasonPlan plan, PlanSharing sharing) async =>
      _with(sharing: sharing);

  @override
  Future<SeasonPlan> addGoalLink(
    SeasonPlan plan, {
    required String goalId,
    required String title,
    required String url,
    required bool visible,
  }) async => _with(
    revise: false,
    goals: [
      for (final goal in plan.goals)
        goal.id != goalId
            ? goal
            : TeamGoal(
                id: goal.id,
                horizon: goal.horizon,
                periodId: goal.periodId,
                title: goal.title,
                description: goal.description,
                state: goal.state,
                links: [
                  ...goal.links,
                  GoalLink(
                    id: 'link-${_ids++}',
                    title: title,
                    url: url,
                    visible: visible,
                  ),
                ],
              ),
    ],
  );

  @override
  Future<SeasonPlan> changeGoalLink(
    SeasonPlan plan,
    String linkId, {
    required bool? visible,
  }) async => _with(revise: false);

  @override
  Future<SharedTeamPlan?> getShared(String teamId) async => null;
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
