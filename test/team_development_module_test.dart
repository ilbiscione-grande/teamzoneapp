import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';
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

  test('blocks, their goals, and check-ins due when things end', () {
    final plan = SeasonPlan.fromJson(const {
      'id': 'p',
      'title': 'Säsong 2027',
      'starts_on': '2027-01-01',
      'ends_on': '2027-12-31',
      'revision': 1,
      'periods': [
        {
          'id': 'pre',
          'name': 'Försäsong',
          'phase': 'preseason',
          'starts_on': '2027-02-15',
          'ends_on': '2027-04-25',
        },
      ],
      'blocks': [
        {
          'id': 'b1',
          'period_id': 'pre',
          'name': 'Grund',
          'starts_on': '2027-02-15',
          'ends_on': '2027-03-14',
        },
        {
          'id': 'b2',
          'period_id': 'pre',
          'name': 'Speluppbyggnad',
          'starts_on': '2027-03-15',
          'ends_on': '2027-03-28',
          'principles': [
            {'id': 'pr', 'area': 'build_up', 'title': 'Spelbarhet'},
          ],
        },
      ],
      'goals': [
        {
          'id': 'g1',
          'horizon': 'block',
          'block_id': 'b1',
          'title': 'Två tillslag',
        },
        {
          'id': 'g2',
          'horizon': 'block',
          'block_id': 'b2',
          'title': 'Ur egen zon',
        },
        {'id': 'g3', 'horizon': 'period', 'period_id': 'pre', 'title': 'Press'},
      ],
      'sharing': {'blocks': true},
    });
    expect(plan.blockOn(DateTime(2027, 3, 17))?.name, 'Speluppbyggnad');
    expect(plan.blocks[1].principleIds, ['pr']);
    expect(plan.blocksOf('pre').length, 2);
    expect(
      plan.goalsOf(GoalHorizon.block, blockId: 'b2').single.title,
      'Ur egen zon',
    );
    expect([plan.sharing.blocks, plan.sharing.any], [true, true]);
    // The first block ended three days ago: its goal is due; the others are not yet.
    expect(plan.goalsDue(DateTime(2027, 3, 17)).map((g) => g.id), ['g1']);
    // Five weeks after the end it is no longer asked for.
    expect(plan.goalsDue(DateTime(2027, 4, 20)).map((g) => g.id), ['g2']);
  });

  test('the suggestion names the day\'s block first', () {
    final suggestion = TeamPlanSuggestion.fromJson(const {
      'plan_title': 'Säsong 2027',
      'period': {'name': 'Försäsong', 'focus': 'Grund'},
      'block': {
        'name': 'Speluppbyggnad',
        'focus': 'Från målvakt',
        'principles': [
          {'area': 'build_up', 'title': 'Spelbarhet'},
        ],
      },
      'goals': [
        {'title': 'Ur egen zon'},
      ],
    });
    expect(
      [suggestion.blockName, suggestion.blockFocus],
      ['Speluppbyggnad', 'Från målvakt'],
    );
    expect(suggestion.blockPrinciples.single.area, PrincipleArea.buildUp);
    expect(suggestion.isEmpty, isFalse);
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

  testWidgets(
    'English TDP keeps team content and translates views and goal choices',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = _Plans();
      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'tdp'),
          locale: const Locale('en'),
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
      await tester.tap(find.text('Workspaces'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('workspace-module-module.team_development')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tdp-create-season')));
      await tester.pumpAndSettle();
      expect(find.text('New season'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('tdp-season-title')),
        'Säsong 2026',
      );
      await tester.enterText(
        find.byKey(const Key('tdp-season-vision')),
        'Ett modigt lag',
      );
      await tester.tap(find.byKey(const Key('tdp-season-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Säsong 2026'), findsWidgets);
      expect(find.text('Ett modigt lag'), findsOneWidget);
      expect(find.text('Team development'), findsOneWidget);
      expect(find.text('Season goals'), findsOneWidget);
      expect(find.textContaining('Day '), findsOneWidget);
      await tester.tap(find.byKey(const Key('tdp-open-planner')));
      await tester.pumpAndSettle();
      expect(find.text('Season goals (long-term)'), findsOneWidget);
      expect(find.text('Shared with players'), findsOneWidget);
      expect(find.textContaining('Nothing is shared yet.'), findsOneWidget);
      await tester.tap(find.text('Playing philosophy'));
      await tester.pumpAndSettle();
      expect(find.text('Playing principles'), findsOneWidget);
      expect(find.text('New principle'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tdp-new-principle')));
      await tester.pumpAndSettle();
      expect(find.text('Stage'), findsOneWidget);
      expect(find.text('Creating chances and scoring'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Add goal').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add goal').first);
      await tester.pumpAndSettle();
      expect(find.text('New goal'), findsWidgets);
      expect(find.text('Short term'), findsOneWidget);
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the year calendar zooms from the season to a day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final today = DateUtils.dateOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final services = _Plans()
      ..plan = SeasonPlan(
        id: 'plan',
        title: 'Säsong 2026',
        startsOn: today.subtract(const Duration(days: 200)),
        endsOn: today.add(const Duration(days: 200)),
        revision: 1,
        periods: [
          DevelopmentPeriod(
            id: 'p1',
            name: 'Seriespel',
            phase: PeriodPhase.competition,
            startsOn: today.subtract(const Duration(days: 30)),
            endsOn: today.add(const Duration(days: 30)),
          ),
        ],
        blocks: [
          DevelopmentBlock(
            id: 'b1',
            periodId: 'p1',
            name: 'Speluppbyggnad',
            focus: 'Bygga upp från målvakten',
            startsOn: monday.subtract(const Duration(days: 7)),
            endsOn: monday.add(const Duration(days: 13)),
          ),
        ],
      );
    DateTime at(DateTime day, int hour) =>
        DateTime(day.year, day.month, day.day, hour);
    final calendar = _Activities([
      _activity('t1', 'Träning A', 'training', at(today, 17)),
      _activity(
        'm1',
        'Match mot Vetlanda',
        'match',
        at(today.add(const Duration(days: 2)), 18),
      ),
    ]);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'tdp'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          modules: _Modules(services),
          calendar: calendar,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('drawer-workspace-team_development')),
    );
    await tester.pumpAndSettle();

    // The block's activities on the home page.
    expect(find.text('Aktiviteter i blocket'), findsOneWidget);
    expect(find.byKey(const Key('tdp-block-activity-t1')), findsOneWidget);
    expect(find.textContaining('Kommande ('), findsOneWidget);
    // The season's timeline across the top, the block now under it.
    final strip = tester.getRect(find.byKey(const Key('tdp-season-strip')));
    expect(
      strip.bottom,
      lessThan(tester.getTopLeft(find.byKey(const Key('tdp-now'))).dy),
    );
    expect(strip.width, greaterThan(1250));

    // The season's months, then the month with the activities.
    await tester.tap(find.byKey(const Key('tdp-open-calendar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-calendar')), findsOneWidget);

    // A hover over a day lists its activities, gone when the mouse moves on.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(
          Key('tdp-cal-mini-${today.year}-${today.month}-${today.day}'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('17:00  Träning A', findRichText: true),
      findsOneWidget,
    );
    await mouse.moveTo(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('17:00  Träning A', findRichText: true),
      findsNothing,
    );

    await tester.tap(
      find.byKey(Key('tdp-cal-month-${today.year}-${today.month}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('tdp-calendar')),
        matching: find.textContaining('Träning A'),
      ),
      findsOneWidget,
    );

    // The week with the plan for it, and the day.
    await tester.tap(find.byKey(Key('tdp-cal-week-${_isoWeek(today)}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-cal-plan')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('tdp-cal-plan')),
        matching: find.text('Bygga upp från målvakten'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        Key('tdp-cal-weekday-${today.year}-${today.month}-${today.day}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Planen den här dagen'), findsOneWidget);
    expect(find.byKey(const Key('tdp-cal-activity-t1')), findsOneWidget);

    // Back up to the season by the crumbs.
    await tester.tap(find.byKey(const Key('tdp-cal-crumb-year')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('tdp-cal-month-${today.year}-${today.month}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('tdp-cal-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-calendar')), findsNothing);

    // A tap on an activity opens its day; Öppna leaves for its page.
    await tester.tap(find.byKey(const Key('tdp-block-activity-m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-cal-activity-m1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tdp-cal-open-m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-calendar')), findsNothing);
    expect(find.text('Lagets utveckling'), findsNothing);
    expect(calendar.from, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a month across the end of summer time keeps its weeks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = _Plans()
      ..plan = SeasonPlan(
        id: 'plan',
        title: 'Säsong 2026',
        startsOn: DateTime(2026),
        endsOn: DateTime(2026, 12, 31),
        revision: 1,
      );
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'tdp'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          modules: _Modules(services),
          calendar: _Activities(const []),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('drawer-workspace-team_development')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-open-calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-cal-month-2026-10')));
    await tester.pumpAndSettle();
    // Summer time ends on Sunday 25 October: Monday the 26th starts week 44.
    for (final week in [40, 41, 42, 43, 44]) {
      expect(find.byKey(Key('tdp-cal-week-$week')), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.byKey(const Key('tdp-cal-day-2026-10-26'))).dx,
      tester.getTopLeft(find.byKey(const Key('tdp-cal-day-2026-10-19'))).dx,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a leader plans the season on the timeline', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
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
    await tester.tap(
      find.byKey(const Key('drawer-workspace-team_development')),
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
    expect(find.byKey(const Key('tdp-season-strip')), findsOneWidget);
    expect(services.created?.startsOn, DateTime(DateTime.now().year));

    // A period dragged out on the timeline, then a block inside it.
    await tester.tap(find.byKey(const Key('tdp-open-planner')));
    await tester.pumpAndSettle();
    final periods = find.byKey(const Key('tdp-lane-periods'));
    await tester.dragFrom(
      tester.getTopLeft(periods) + const Offset(20, 24),
      const Offset(220, 0),
    );
    await tester.pumpAndSettle();
    final period = services.plan!.periods.single;
    expect(period.name, 'Ny period');
    expect(period.startsOn.weekday, DateTime.monday);
    expect(period.endsOn.weekday, DateTime.sunday);
    expect(find.byKey(ValueKey('tdp-panel-${period.id}')), findsOneWidget);
    final blocks = find.byKey(const Key('tdp-lane-blocks'));
    await tester.dragFrom(
      tester.getTopLeft(blocks) + const Offset(30, 20),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    final block = services.plan!.blocks.single;
    expect(block.periodId, period.id);
    expect(block.startsOn.isBefore(period.startsOn), isFalse);
    expect(block.endsOn.isAfter(period.endsOn), isFalse);

    // The block's name in its dialog, and a goal of its own.
    await tester.tap(find.byKey(const Key('tdp-panel-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tdp-block-name')),
      'Speluppbyggnad',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-block-save')));
    await tester.pumpAndSettle();
    expect(services.plan!.blocks.single.name, 'Speluppbyggnad');
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('tdp-panel-${block.id}')),
        matching: find.byTooltip('Lägg till mål'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-goal-horizon')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('tdp-goal-title')),
      'Ur egen zon i sex av tio',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-goal-save')));
    await tester.pumpAndSettle();
    final blockGoal = services.plan!.goals.single;
    expect(
      [blockGoal.horizon, blockGoal.blockId],
      [GoalHorizon.block, block.id],
    );

    // A long-term goal of the season, beside the panel, marked achieved from its row.
    await tester.tap(find.byTooltip('Lägg till mål').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tdp-goal-title')),
      'Alla spelar mycket',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-goal-save')));
    await tester.pumpAndSettle();
    final seasonGoal = services.plan!.goals.last;
    expect(seasonGoal.horizon, GoalHorizon.season);
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('tdp-goal-${seasonGoal.id}')),
        matching: find.byTooltip('Markera som uppnått'),
      ),
    );
    await tester.pumpAndSettle();
    expect(services.plan!.goals.last.state, GoalState.achieved);

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
    expect(checkin.goalId, seasonGoal.id);
    await tester.tapAt(const Offset(700, 40));
    await tester.pumpAndSettle();

    // Spelidé: a principle and a key figure.
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

    // The principle in focus in the block, picked in the block's dialog.
    await tester.tap(find.text('Planera'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('tdp-item-${block.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-panel-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spela framåt när det går'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-block-save')));
    await tester.pumpAndSettle();
    expect(services.plan!.blocks.single.principleIds, [
      services.plan!.principles.single.id,
    ]);

    // The block on the season at a glance in the overview.
    await tester.tap(find.text('Översikt'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Speluppbyggnad'), findsOneWidget);

    // Sharing with the players, per part, with nothing picked.
    await tester.tap(find.text('Planera'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tdp-share-blocks')));
    await tester.tap(find.byKey(const Key('tdp-share-blocks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-share-goals')));
    await tester.pumpAndSettle();
    expect(services.plan!.sharing.blocks, isTrue);
    expect(services.plan!.sharing.goals, isTrue);
    expect(services.plan!.sharing.vision, isFalse);

    // A link on the season goal, shown to the players.
    await tester.tap(find.text('Översikt'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Alla spelar mycket'));
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
    final link = services.plan!.goals.last.links.single;
    expect([link.title, link.visible], ['Film', true]);
    expect(tester.takeException(), isNull);
  });

  /// The module opened on a season with a block and no principles.
  Future<_Plans> openWithoutModel(
    WidgetTester tester, {
    List<PlanMatch> matches = const [],
    List<TeamPrinciple> principles = const [],
    List<TeamKpi> kpis = const [],
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final today = DateUtils.dateOnly(DateTime.now());
    final services = _Plans()
      ..plan = SeasonPlan(
        id: 'plan',
        title: 'Säsong',
        startsOn: today.subtract(const Duration(days: 100)),
        endsOn: today.add(const Duration(days: 100)),
        revision: 1,
        matches: matches,
        principles: principles,
        kpis: kpis,
        vision: principles.isEmpty ? '' : 'Ett modigt lag',
        matchButtons: const [(id: 'ballwin', label: 'Bollvinst')],
        periods: [
          DevelopmentPeriod(
            id: 'p1',
            name: 'Seriespel',
            phase: PeriodPhase.competition,
            startsOn: today.subtract(const Duration(days: 30)),
            endsOn: today.add(const Duration(days: 30)),
          ),
        ],
        blocks: [
          DevelopmentBlock(
            id: 'b1',
            periodId: 'p1',
            name: 'Speluppbyggnad',
            startsOn: today.subtract(const Duration(days: 7)),
            endsOn: today.add(const Duration(days: 7)),
          ),
        ],
      );
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'tdp'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          modules: _Modules(services),
          calendar: _Activities(const []),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('drawer-workspace-team_development')),
    );
    await tester.pumpAndSettle();
    return services;
  }

  testWidgets('the game model starts from a template and the guide', (
    tester,
  ) async {
    final services = await openWithoutModel(tester);
    await tester.tap(find.text('Spelidé'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-model-start')), findsOneWidget);

    // A template, with one of its principles left out.
    await tester.tap(find.byKey(const Key('tdp-model-templates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-template-possession')));
    await tester.pumpAndSettle();
    expect(find.text('Lägg till 10 principer'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tdp-idea-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-model-add')));
    await tester.pumpAndSettle();
    var titles = [for (final p in services.plan!.principles) p.title];
    expect(titles, hasLength(9));
    expect(titles, contains('Kort uppbyggnad från målvakten'));
    expect(titles, isNot(contains('Spela in i straffområdet')));
    expect(find.byKey(const Key('tdp-model-start')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tdp-area-build_up')),
        matching: find.text('Spela runt pressen'),
      ),
      findsOneWidget,
    );

    // The guide: an answer the plan already has and one it lacks.
    await tester.tap(find.byKey(const Key('tdp-model-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-model-menu-guide')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('tdp-guide-next')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('tdp-guide-build_up-0')));
    await tester.ensureVisible(find.byKey(const Key('tdp-guide-regaining-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-guide-regaining-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-guide-next')));
    await tester.pumpAndSettle();
    expect(find.text('Finns redan i spelidén'), findsOneWidget);
    expect(find.text('Lägg till 1 princip'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tdp-model-add')));
    await tester.pumpAndSettle();
    titles = [for (final p in services.plan!.principles) p.title];
    expect(titles, hasLength(10));
    expect(services.plan!.principles.last.area, PrincipleArea.regaining);
    expect(titles.last, 'Falla hem tillsammans');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a block without a game model picks from the base list', (
    tester,
  ) async {
    final services = await openWithoutModel(tester);
    await tester.tap(find.text('Planera'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tdp-item-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-panel-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-block-standard-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-block-standard-6')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-block-save')));
    await tester.pumpAndSettle();
    final principles = services.plan!.principles;
    expect(
      [for (final p in principles) p.title],
      ['Skapa spelbarhet', 'Reagera direkt'],
    );
    expect(services.plan!.blocks.single.principleIds, [
      for (final p in principles) p.id,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a key figure takes its values from the matches', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final services = await openWithoutModel(
      tester,
      matches: [
        PlanMatch(
          eventId: 'm1',
          playedOn: today.subtract(const Duration(days: 14)),
          title: 'P2012 – Vetlanda IF',
          registered: true,
          metrics: const {'goals_for': 3, 'shots': 9},
          buttons: const {'ballwin': 4},
        ),
        PlanMatch(
          eventId: 'm2',
          playedOn: today.subtract(const Duration(days: 7)),
          title: 'Eksjö BK – P2012',
          metrics: const {'goals_for': 1},
        ),
      ],
    );
    await tester.tap(find.text('Spelidé'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-new-kpi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-kpi-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Från matcherna: Avslut').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tdp-kpi-title')))
          .controller!
          .text,
      'Avslut',
    );
    await tester.enterText(find.byKey(const Key('tdp-kpi-target')), '8');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-kpi-save')));
    await tester.pumpAndSettle();
    final kpi = services.plan!.kpis.single;
    expect([kpi.source, kpi.unit], ['shots', 'st']);
    // Only the registered match tells its shots.
    expect([for (final v in services.plan!.valuesOfKpi(kpi)) v.value], [9]);

    // The registered match's value corrected by hand.
    await tester.ensureVisible(find.byKey(ValueKey('tdp-kpi-${kpi.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('tdp-kpi-${kpi.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tdp-kpi-match-m2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tdp-kpi-match-m1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tdp-kpi-match-value')), '11');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-kpi-match-save')));
    await tester.pumpAndSettle();
    var values = services.plan!.valuesOfKpi(kpi);
    expect([values.single.value, values.single.counted], [11, false]);
    expect(find.textContaining('satt för hand'), findsOneWidget);

    // The match's own value again.
    await tester.tap(find.byKey(const ValueKey('tdp-kpi-match-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-kpi-match-reset')));
    await tester.pumpAndSettle();
    values = services.plan!.valuesOfKpi(kpi);
    expect([values.single.value, values.single.counted], [9, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new season starts from this one, and the header tells which', (
    tester,
  ) async {
    final services = await openWithoutModel(
      tester,
      principles: const [
        TeamPrinciple(
          id: 'pr1',
          area: PrincipleArea.buildUp,
          title: 'Skapa spelbarhet',
        ),
      ],
      kpis: const [
        TeamKpi(id: 'k1', title: 'Avslut', unit: 'st', source: 'shots'),
      ],
    );
    final first = services.plan!;
    final switcher = find.byKey(const Key('tdp-season-switcher'));
    expect(
      find.descendant(of: switcher, matching: find.text('Säsong')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: switcher, matching: find.textContaining('Pågår')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tdp-season-banner')), findsNothing);

    // A new season from the switcher, starting from this one.
    await tester.tap(switcher);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-season-new')));
    await tester.pumpAndSettle();
    for (final part in ['vision', 'principles', 'kpis']) {
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(ValueKey('tdp-season-from-$part')),
            )
            .value,
        isTrue,
      );
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tdp-season-vision')))
          .controller!
          .text,
      'Ett modigt lag',
    );
    await tester.tap(find.byKey(const ValueKey('tdp-season-from-kpis')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-season-save')));
    await tester.pumpAndSettle();
    final next = services.plan!;
    expect(next.id, isNot(first.id));
    expect(next.vision, 'Ett modigt lag');
    expect([for (final p in next.principles) p.title], ['Skapa spelbarhet']);
    expect(next.kpis, isEmpty);
    expect(next.startsOn, first.endsOn.add(const Duration(days: 1)));

    // The new season is upcoming: the header and a banner say so.
    expect(
      find.descendant(of: switcher, matching: find.textContaining('Kommande')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tdp-season-banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tdp-season-to-current')));
    await tester.pumpAndSettle();
    expect(services.plan!.id, first.id);
    expect(find.byKey(const Key('tdp-season-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the players\' load and the signals the leaders set', (
    tester,
  ) async {
    final services = await openWithoutModel(tester);
    expect(find.byKey(const Key('tdp-attention')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tdp-attention-ada-load_increase')),
      findsOneWidget,
    );
    expect(find.textContaining('360 min de senaste 7 dagarna'), findsOneWidget);
    expect(find.textContaining('Överväg ett lugnare pass'), findsOneWidget);
    expect(find.byKey(const ValueKey('tdp-player-load-bo')), findsOneWidget);
    expect(
      find.textContaining('ansträngning 6,5 av 10 (2 svar)'),
      findsOneWidget,
    );

    // The leaders turn the increase off and set the match minutes.
    await tester.ensureVisible(find.byKey(const Key('tdp-load-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-load-settings')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tdp-load-increase')), '');
    await tester.enterText(find.byKey(const Key('tdp-load-match')), '5000');
    await tester.tap(find.byKey(const Key('tdp-load-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ett tal från 1 till 1000'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tdp-load-match')), '150');
    await tester.tap(find.byKey(const Key('tdp-load-save')));
    await tester.pumpAndSettle();
    expect(services.savedLoad!.loadIncreasePercent, isNull);
    expect(services.savedLoad!.attendanceMinPercent, 50);
    expect(services.savedLoad!.matchMinutesMax, 150);
    expect(
      find.byKey(const ValueKey('tdp-attention-ada-load_increase')),
      findsNothing,
    );
    expect(find.textContaining('Ingen spelare sticker ut'), findsOneWidget);

    // The leaders turn the effort question after trainings on.
    final effortPush = find.byKey(const Key('tdp-effort-push'));
    await tester.ensureVisible(effortPush);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(effortPush).value, isFalse);
    await tester.tap(effortPush);
    await tester.pumpAndSettle();
    expect(services.teamLoad.settings.effortPush, isTrue);
    expect(tester.widget<SwitchListTile>(effortPush).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a block suggests exercises and takes the leaders\' own', (
    tester,
  ) async {
    final services = await openWithoutModel(
      tester,
      principles: const [
        TeamPrinciple(
          id: 'pr1',
          area: PrincipleArea.buildUp,
          title: 'Skapa spelbarhet',
        ),
      ],
    );
    BlockExercise item(String id, String source, String title, String phase) =>
        BlockExercise(
          pass: {
            'source': source,
            'id': id,
            'kind': 'exercise',
            'title': title,
            'exercises': [
              {'title': title, 'phase': phase, 'minutes': 10},
            ],
          },
        );
    services.library.addAll([
      item('i1', 'teamzone', 'Rondo 4 mot 2', 'build_up'),
      item('i2', 'teamzone', 'Försvar i linje', 'defending'),
      item('i3', 'club', 'Klubbens uppbyggnad', 'build_up'),
    ]);
    await tester.tap(find.text('Planera'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tdp-item-b1')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('tdp-block-exercises'));
    await tester.ensureVisible(panel);
    await tester.pumpAndSettle();
    expect(find.textContaining('Välj principer för blocket'), findsOneWidget);

    // A principle for the block: the exercises that train it.
    await tester.tap(find.byKey(const Key('tdp-panel-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tdp-block-principle-pr1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-block-save')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(panel);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tdp-block-suggested-i1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tdp-block-suggested-i3')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tdp-block-suggested-i2')), findsNothing);

    // One chosen from the suggestions, one from the library, one own.
    await tester.tap(find.byKey(const ValueKey('tdp-block-exercise-pick-i1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('tdp-block-exercise-library')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-block-exercise-library')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('tdp-library-source')),
        matching: find.text('TeamZone'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tdp-library-item-i2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tdp-block-exercise-own')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-block-exercise-own')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tdp-own-exercise-title')),
      'Fyra mot fyra',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-own-exercise-save')));
    await tester.pumpAndSettle();
    expect(
      [for (final c in services.chosen) c.title],
      ['Rondo 4 mot 2', 'Försvar i linje', 'Fyra mot fyra'],
    );
    expect(find.byKey(const ValueKey('tdp-block-suggested-i1')), findsNothing);

    // Taken away again.
    final first = services.chosen.first;
    await tester.ensureVisible(
      find.byKey(ValueKey('tdp-block-exercise-remove-${first.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('tdp-block-exercise-remove-${first.id}')),
    );
    await tester.pumpAndSettle();
    expect(services.chosen, hasLength(2));
    expect(
      find.byKey(const ValueKey('tdp-block-suggested-i1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the leaders register an injury and note the player back', (
    tester,
  ) async {
    final services = await openWithoutModel(tester);
    final ada = find.byKey(const ValueKey('tdp-player-load-ada'));
    await tester.ensureVisible(ada);
    await tester.pumpAndSettle();
    await tester.tap(ada);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-injury-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tdp-injury-what')),
      'Stukad fot',
    );
    await tester.enterText(
      find.byKey(const Key('tdp-injury-note')),
      'Undvik hopp en vecka',
    );
    await tester.tap(find.byKey(const Key('tdp-injury-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-injury-current')), findsOneWidget);
    expect(find.textContaining('Undvik hopp en vecka'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tdp-injury-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tdp-attention-injury-ada')),
      findsOneWidget,
      reason: 'the injured player needs attention',
    );

    // Back in training: no longer in the attention list.
    await tester.ensureVisible(
      find.byKey(const ValueKey('tdp-attention-injury-ada')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tdp-attention-injury-ada')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-injury-back')));
    await tester.pumpAndSettle();
    expect(services.injuryList['ada']!.single.backOn, isNotNull);
    await tester.tap(find.byKey(const Key('tdp-injury-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tdp-attention-injury-ada')),
      findsNothing,
    );

    // Under 15: blocked until the consents; the club's is given here.
    final bo = find.byKey(const ValueKey('tdp-player-load-bo'));
    await tester.ensureVisible(bo);
    await tester.pumpAndSettle();
    await tester.tap(bo);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdp-injury-blocked')), findsOneWidget);
    expect(find.byKey(const Key('tdp-injury-new')), findsNothing);
    await tester.tap(find.byKey(const Key('tdp-injury-club-consent')));
    await tester.pumpAndSettle();
    expect(services.clubConsents, {'bo'});

    // Turned off: the injuries are deleted.
    await tester.tap(find.byKey(const Key('tdp-injury-registration')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-injury-turn-off-confirm')));
    await tester.pumpAndSettle();
    expect(services.turnedOff, {'bo'});
    expect(find.textContaining('avstängd för spelaren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the player sees their injuries and consents under 15', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
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
          calendar: _Activities(const []),
          roster: _Overview(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget').first);
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('player-injury-card'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: card, matching: find.text('Ont i knät')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('tillbaka i träning'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('player-injury-consent-bo')));
    await tester.pumpAndSettle();
    expect(services.boConsents, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a block\'s dates are chosen in its dialog', (tester) async {
    final services = await openWithoutModel(tester);
    final before = services.plan!.blocks.single;
    await tester.tap(find.text('Planera'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tdp-item-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-panel-edit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Inom perioden Seriespel'), findsOneWidget);

    // Two days earlier or later, within the same month.
    final end = before.endsOn;
    final target = end.day > 3
        ? DateTime(end.year, end.month, end.day - 2)
        : DateTime(end.year, end.month, end.day + 2);
    await tester.tap(find.byKey(const Key('tdp-block-ends')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${target.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-block-save')));
    await tester.pumpAndSettle();
    final after = services.plan!.blocks.single;
    expect(after.endsOn, target);
    expect(after.startsOn, before.startsOn);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a block\'s focus is written and shown as Markdown', (
    tester,
  ) async {
    final services = await openWithoutModel(tester);
    await tester.tap(find.text('Planera'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tdp-item-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tdp-panel-edit')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('tdp-block-focus'));
    await tester.enterText(field, 'Bygg upp lugnt');
    await tester.pump();
    // "Bygg" made bold, then the line a list item.
    tester.widget<TextField>(field).controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await tester.tap(find.byKey(const Key('tdp-format-bold')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tdp-format-list')));
    await tester.pump();
    expect(
      tester.widget<TextField>(field).controller!.text,
      '- **Bygg** upp lugnt',
    );
    await tester.tap(find.byKey(const Key('tdp-block-save')));
    await tester.pumpAndSettle();
    expect(services.plan!.blocks.single.focus, '- **Bygg** upp lugnt');

    // The panel shows it formatted, without the marks.
    expect(find.text('Bygg upp lugnt'), findsWidgets);
    expect(find.textContaining('**'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('a key figure counts goals, own buttons and values set by hand', () {
    final day = DateTime(2026, 10, 1);
    final plan = SeasonPlan(
      id: 'plan',
      title: 'Säsong',
      startsOn: DateTime(2026),
      endsOn: DateTime(2026, 12, 31),
      revision: 1,
      matches: [
        PlanMatch(
          eventId: 'm1',
          playedOn: day,
          title: 'A',
          registered: true,
          metrics: const {'goals_for': 2},
          buttons: const {'ballwin': 5},
        ),
        PlanMatch(
          eventId: 'm2',
          playedOn: day.add(const Duration(days: 7)),
          title: 'B',
          metrics: const {'goals_for': 0},
        ),
      ],
      checkins: [
        TeamCheckin(
          id: 'c1',
          kpiId: 'goals',
          eventId: 'm2',
          checkedOn: day.add(const Duration(days: 7)),
          value: 1,
        ),
        TeamCheckin(
          id: 'c2',
          kpiId: 'goals',
          checkedOn: day.add(const Duration(days: 9)),
          value: 4,
        ),
      ],
    );
    const goals = TeamKpi(id: 'goals', title: 'Mål', source: 'goals_for');
    expect(
      [for (final v in plan.valuesOfKpi(goals)) (v.value, v.counted)],
      [(4.0, false), (1.0, false), (2.0, true)],
    );
    const wins = TeamKpi(
      id: 'w',
      title: 'Bollvinster',
      source: 'button:ballwin',
    );
    expect([for (final v in plan.valuesOfKpi(wins)) v.value], [5]);
  });
}

class _Plans implements TeamDevelopmentServices {
  SeasonPlan? plan;
  SeasonPlan? created;
  var _ids = 0;

  SeasonPlan _with({
    List<DevelopmentPeriod>? periods,
    List<DevelopmentBlock>? blocks,
    List<TeamGoal>? goals,
    List<TeamPrinciple>? principles,
    List<TeamKpi>? kpis,
    List<TeamCheckin>? checkins,
    PlanSharing? sharing,
    bool revise = true,
  }) => plan = SeasonPlan(
    matches: plan!.matches,
    matchButtons: plan!.matchButtons,
    id: plan!.id,
    title: plan!.title,
    vision: plan!.vision,
    startsOn: plan!.startsOn,
    endsOn: plan!.endsOn,
    revision: plan!.revision + (revise ? 1 : 0),
    checkinEveryDays: plan!.checkinEveryDays,
    sharing: sharing ?? plan!.sharing,
    periods: periods ?? plan!.periods,
    blocks: blocks ?? plan!.blocks,
    goals: goals ?? plan!.goals,
    principles: principles ?? plan!.principles,
    kpis: kpis ?? plan!.kpis,
    checkins: checkins ?? plan!.checkins,
  );

  @override
  Future<TeamDevelopment> get(String teamId, {String? planId}) async {
    // Another season asked for: the two swap places.
    if (planId != null && planId == previous?.id) {
      final shown = plan;
      plan = previous;
      previous = shown;
    }
    return TeamDevelopment(
      canEdit: true,
      seasons: [
        for (final season in [?plan, ?previous])
          SeasonSummary(
            id: season.id,
            title: season.title,
            startsOn: season.startsOn,
            endsOn: season.endsOn,
          ),
      ],
      plan: plan,
    );
  }

  /// The season before the one [createPlan] made.
  SeasonPlan? previous;

  /// The players' load, and the values the leaders saved last.
  LoadSettings? savedLoad;
  TeamLoad teamLoad = TeamLoad(
    day: DateTime(2026, 11, 2),
    players: const [
      PlayerLoad(
        personId: 'ada',
        name: 'Ada',
        sessions7: 3,
        trainingMinutes7: 270,
        matchMinutes7: 90,
        loadPercent: 180,
        effort7: 6.5,
        efforts7: 2,
        signals: [LoadSignal.loadIncrease],
      ),
      PlayerLoad(personId: 'bo', name: 'Bo', sessions7: 2),
    ],
  );

  /// The library, and the block's exercises as the server keeps them.
  final library = <BlockExercise>[];
  final chosen = <BlockExercise>[];

  BlockExercises get _exercises => BlockExercises(
    chosen: [...chosen],
    matched: [
      for (final item in library)
        if (item.single &&
            !chosen.any((c) => c.itemId == item.itemId) &&
            plan!.blocks.any(
              (b) => b.principleIds.any(
                (p) => plan!.principles.any(
                  (pr) => pr.id == p && pr.area == item.phase,
                ),
              ),
            ))
          item,
    ],
  );

  @override
  Future<BlockExercises> blockExercises(
    SeasonPlan plan,
    String blockId,
  ) async => _exercises;

  @override
  Future<BlockExercises> addBlockExercise(
    SeasonPlan plan,
    String blockId, {
    String? sharedItemId,
    String title = '',
    String description = '',
  }) async {
    final id = 'chosen-${_ids++}';
    chosen.add(
      sharedItemId == null
          ? BlockExercise(
              id: id,
              pass: {
                'source': 'own',
                'id': id,
                'kind': 'exercise',
                'title': title,
                'exercises': [
                  {'title': title, 'organisation': description},
                ],
              },
            )
          : BlockExercise(
              id: id,
              pass: library.firstWhere((i) => i.itemId == sharedItemId).pass,
            ),
    );
    return _exercises;
  }

  @override
  Future<BlockExercises> deleteBlockExercise(
    SeasonPlan plan,
    String exerciseId,
  ) async {
    chosen.removeWhere((c) => c.id == exerciseId);
    return _exercises;
  }

  @override
  Future<TeamLoad> load(SeasonPlan plan, {DateTime? day}) async => teamLoad;

  /// The players' injuries as the server keeps them: Ada 15+, Bo under 15.
  final injuryList = <String, List<PlayerInjury>>{'ada': [], 'bo': []};
  final turnedOff = <String>{};
  final clubConsents = <String>{};
  TeamInjuries get _injuries => TeamInjuries(
    players: [
      for (final (id, name, adult) in [
        ('ada', 'Ada', true),
        ('bo', 'Bo', false),
      ])
        InjuryPlayer(
          personId: id,
          name: name,
          adult: adult,
          turnedOff: turnedOff.contains(id),
          clubConsent: clubConsents.contains(id),
          allowed: !turnedOff.contains(id) && adult,
          injuries: injuryList[id]!,
        ),
    ],
  );

  @override
  Future<TeamInjuries> injuries(SeasonPlan plan) async => _injuries;

  @override
  Future<TeamInjuries> saveInjury(
    SeasonPlan plan, {
    String? injuryId,
    required String personId,
    required DateTime startedOn,
    required String what,
    String note = '',
    DateTime? backOn,
  }) async {
    final list = injuryList[personId]!;
    list.removeWhere((injury) => injury.id == injuryId);
    list.insert(
      0,
      PlayerInjury(
        id: injuryId ?? 'inj${_ids++}',
        startedOn: startedOn,
        what: what,
        note: note,
        backOn: backOn,
      ),
    );
    return _injuries;
  }

  @override
  Future<TeamInjuries> deleteInjury(SeasonPlan plan, String injuryId) async {
    for (final list in injuryList.values) {
      list.removeWhere((injury) => injury.id == injuryId);
    }
    return _injuries;
  }

  @override
  Future<TeamInjuries> setInjuryRegistration(
    SeasonPlan plan,
    String personId, {
    bool? turnOff,
    bool? clubConsent,
  }) async {
    if (turnOff == true) {
      turnedOff.add(personId);
      injuryList[personId]!.clear();
    } else if (turnOff == false) {
      turnedOff.remove(personId);
    }
    if (clubConsent == true) clubConsents.add(personId);
    if (clubConsent == false) clubConsents.remove(personId);
    return _injuries;
  }

  /// The player's own view: Bo, under 15, with an injury from before.
  bool boConsents = false;
  TeamInjuries get _mine => TeamInjuries(
    players: [
      InjuryPlayer(
        personId: 'bo',
        name: 'Bo',
        self: true,
        playerConsent: boConsents,
        injuries: [
          PlayerInjury(
            id: 'old',
            startedOn: DateTime(2026, 9, 1),
            what: 'Ont i knät',
            backOn: DateTime(2026, 9, 14),
          ),
        ],
      ),
    ],
  );

  @override
  Future<TeamInjuries> myInjuries(String teamId) async => _mine;

  @override
  Future<TeamInjuries> setInjuryConsent(
    String teamId,
    String personId,
    bool give,
  ) async {
    boConsents = give;
    return _mine;
  }

  @override
  Future<TeamLoad> setEffortPush(SeasonPlan plan, bool on) async =>
      teamLoad = TeamLoad(
        day: teamLoad.day,
        settings: LoadSettings(effortPush: on),
        players: teamLoad.players,
      );

  @override
  Future<TeamLoad> saveLoadSettings(
    SeasonPlan plan,
    LoadSettings settings,
  ) async {
    savedLoad = settings;
    return teamLoad = TeamLoad(
      day: teamLoad.day,
      settings: settings,
      players: [
        for (final p in teamLoad.players)
          PlayerLoad(
            personId: p.personId,
            name: p.name,
            sessions7: p.sessions7,
            trainingMinutes7: p.trainingMinutes7,
            matchMinutes7: p.matchMinutes7,
            loadPercent: p.loadPercent,
            signals: [
              for (final s in p.signals)
                if (s != LoadSignal.loadIncrease ||
                    settings.loadIncreasePercent != null)
                  s,
            ],
          ),
      ],
    );
  }

  @override
  Future<List<BlockExercise>> listLibrary(
    String source, {
    String search = '',
  }) async => [
    for (final item in library)
      if (item.source == source) item,
  ];

  @override
  Future<SeasonPlan> copySeason(
    SeasonPlan plan, {
    required String fromPlanId,
    required bool principles,
    required bool kpis,
  }) async => _with(
    principles: [...plan.principles, if (principles) ...previous!.principles],
    kpis: [...plan.kpis, if (kpis) ...previous!.kpis],
  );

  @override
  Future<SeasonPlan> createPlan({
    required String teamId,
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
  }) async => created = plan = SeasonPlan(
    id: (previous = plan) == null ? 'plan' : 'plan-${_ids++}',
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
  Future<SeasonPlan> saveBlock(
    SeasonPlan plan, {
    String? blockId,
    required String periodId,
    required String name,
    required DateTime startsOn,
    required DateTime endsOn,
    required String focus,
    required List<String> principleIds,
  }) async => _with(
    blocks: [
      ...plan.blocks.where((b) => b.id != blockId),
      DevelopmentBlock(
        id: blockId ?? 'block-${_ids++}',
        periodId: periodId,
        name: name,
        startsOn: startsOn,
        endsOn: endsOn,
        focus: focus,
        principleIds: principleIds,
      ),
    ],
  );

  @override
  Future<SeasonPlan> deleteBlock(SeasonPlan plan, String blockId) async =>
      _with(blocks: [...plan.blocks.where((b) => b.id != blockId)]);

  @override
  Future<SeasonPlan> saveGoal(
    SeasonPlan plan, {
    String? goalId,
    required GoalHorizon horizon,
    String? periodId,
    String? blockId,
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
        blockId: blockId,
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
    String? source,
  }) async => _with(
    kpis: [
      ...plan.kpis.where((k) => k.id != kpiId),
      TeamKpi(
        id: kpiId ?? 'kpi-${_ids++}',
        title: title,
        unit: unit,
        target: target,
        higherIsBetter: higherIsBetter,
        source: source == null || source.isEmpty ? null : source,
      ),
    ],
  );

  @override
  Future<SeasonPlan> setKpiMatchValue(
    SeasonPlan plan, {
    required String kpiId,
    required String eventId,
    double? value,
    String note = '',
  }) async => _with(
    revise: false,
    checkins: [
      if (value != null)
        TeamCheckin(
          id: 'checkin-${_ids++}',
          kpiId: kpiId,
          eventId: eventId,
          checkedOn: plan.matches
              .firstWhere((m) => m.eventId == eventId)
              .playedOn,
          value: value,
          note: note,
        ),
      for (final checkin in plan.checkins)
        if (checkin.kpiId != kpiId || checkin.eventId != eventId) checkin,
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

int _isoWeek(DateTime day) {
  final date = DateTime.utc(day.year, day.month, day.day);
  final thursday = date.add(Duration(days: 4 - date.weekday));
  return thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
}

CalendarEventSummary _activity(
  String id,
  String title,
  String type,
  DateTime startsAt,
) => CalendarEventSummary(
  id: id,
  clubId: 'club',
  owningTeamId: 'team',
  teamName: 'P2012',
  title: title,
  type: type,
  state: 'published',
  startsAt: startsAt,
  endsAt: startsAt.add(const Duration(minutes: 90)),
  allDay: false,
  timezone: 'Europe/Stockholm',
  revision: 1,
);

/// The team's calendar, for the activities beside the plan.
class _Activities extends UnconfiguredCalendarServices {
  _Activities(this.events);
  final List<CalendarEventSummary> events;
  DateTime? from;

  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async {
    this.from = from;
    return [
      for (final event in events)
        if (!event.startsAt.isBefore(from) && event.startsAt.isBefore(to))
          event,
    ];
  }
}

/// The team overview under Laget, for the player's injury card.
class _Overview extends UnconfiguredRosterServices {
  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) async =>
      const TeamOverview(
        teamId: 'team',
        clubId: 'club',
        teamName: 'P2012',
        clubName: 'Testklubben',
        leaders: [],
        memberCount: 0,
        canManage: false,
        activeInvitationCount: 0,
        pendingApplicationCount: 0,
      );
}
