import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/team_development/team_development_services.dart';
import 'package:teamzone_app/src/features/training/training_services.dart';
import 'package:teamzone_app/src/features/workspaces/module_services.dart';

void main() {
  test('a session reads its blocks and sends them back', () {
    final session = TrainingSession.fromJson(const {
      'event_id': 't',
      'can_edit': true,
      'title': 'Träning',
      'starts_at': '2026-10-25T16:00:00Z',
      'ends_at': '2026-10-25T17:30:00Z',
      'revision': 2,
      'published': true,
      'theme': 'Press',
      'blocks': [
        {'part': 'warmup', 'title': 'Rondo', 'minutes': 12},
        {
          'part': 'main',
          'title': 'Press 4v4',
          'minutes': 25,
          'phase': 'regaining',
          'source_kind': 'own',
        },
      ],
    });
    expect([session.minutes, session.eventMinutes], [37, 90]);
    expect(session.blocks.last.phase, PrincipleArea.regaining);
    expect(session.blocks.last.toJson()['phase'], 'regaining');
    expect(session.blocks.first.toJson()['part'], 'warmup');
    final withPlayers = session.blocks.first.copyWith(
      players: const [
        TrainingBlockPlayer(),
        TrainingBlockPlayer(
          personId: 'person-1',
          name: 'Alex',
          team: TrainingPlayerTeam.red,
        ),
      ],
    );
    final decoded = TrainingBlock.fromJson(withPlayers.toJson());
    expect(decoded.players.map((p) => p.team), [
      TrainingPlayerTeam.blue,
      TrainingPlayerTeam.red,
    ]);
    expect(decoded.copyWith(title: 'Ändrat').players.last.personId, 'person-1');
    expect(session.blocks.last.players, isEmpty);
  });

  testWidgets('a leader plans a training session in the module', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessions = _Sessions();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'training'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          modules: const _Modules(),
          calendar: _Calendar(sessions),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom-nav-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbetsytor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-module-module.training')));
    await tester.pumpAndSettle();

    // The next training, with nothing planned yet.
    expect(find.byKey(const Key('module-next-training')), findsOneWidget);
    expect(find.textContaining('Inget pass planerat än'), findsOneWidget);
    await tester.tap(find.byKey(const Key('module-next-training-open')));
    await tester.pumpAndSettle();

    // One plan, no separate Förberedelser beside it: the session stands
    // alone when the event's preparation cannot be fetched.
    expect(find.byType(Tab), findsNothing);
    expect(find.textContaining('kunde inte hämtas'), findsOneWidget);

    // It starts from the event's theme, and its plan can become a block.
    expect(find.text('Press'), findsOneWidget);
    expect(
      find.byKey(const Key('training-session-event-plan')),
      findsOneWidget,
    );

    // A warm-up exercise.
    await tester.tap(find.byKey(const ValueKey('training-add-warmup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('training-block-title')),
      'Rondo 5 mot 2',
    );
    await tester.enterText(
      find.byKey(const Key('training-block-minutes')),
      '12',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('training-block-save')));
    await tester.pumpAndSettle();
    expect(find.text('Rondo 5 mot 2'), findsOneWidget);
    expect(find.text('12 av 90 min planerade'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('training-player-add-anonymous')),
    );
    await tester.tap(find.byKey(const Key('training-player-add-anonymous')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('training-player-team-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rött lag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-player-add-roster')));
    await tester.pumpAndSettle();
    expect(find.text('Kallade – accepterat'), findsOneWidget);
    final rosterScroll = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    for (final heading in [
      'Kallade – obesvarat',
      'Kallade – nekat',
      'Okallade spelare',
    ]) {
      await tester.scrollUntilVisible(
        find.text(heading),
        140,
        scrollable: rosterScroll,
      );
      expect(find.text(heading), findsOneWidget);
    }
    tester.state<ScrollableState>(rosterScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex Spelare'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('training-roster-team-player-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grönt lag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-player-roster-confirm')));
    await tester.pumpAndSettle();

    // Published and saved.
    await tester.ensureVisible(
      find.byKey(const Key('training-session-published')),
    );
    await tester.tap(find.byKey(const Key('training-session-published')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('training-session-save')));
    await tester.pumpAndSettle();
    final saved = sessions.saved!;
    expect(saved.published, isTrue);
    expect(saved.revision, 1);
    expect(saved.blocks.single.players.map((p) => p.team), [
      TrainingPlayerTeam.red,
      TrainingPlayerTeam.green,
    ]);
    expect(saved.blocks.single.players.last.personId, 'player-1');
    expect(saved.blocks.map((b) => [b.part, b.title, b.minutes]).toList(), [
      [TrainingPart.warmup, 'Rondo 5 mot 2', 12],
    ]);
    expect(find.textContaining('visas för spelarna'), findsOneWidget);

    // Cancelling the guide leaves the saved plan untouched.
    await tester.tap(find.byKey(const Key('training-guide-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avbryt'));
    await tester.pumpAndSettle();
    expect(find.text('Rondo 5 mot 2'), findsOneWidget);

    // The guide replaces the local draft only after review, then uses
    // the same save contract and preserves the publication setting.
    await tester.tap(find.byKey(const Key('training-guide-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('training-guide-focus')),
      'Spelvändning',
    );
    await tester.tap(find.byKey(const Key('training-guide-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-guide-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ersätter övningarna'), findsOneWidget);
    await tester.tap(find.byKey(const Key('training-guide-next')));
    await tester.pumpAndSettle();
    expect(sessions.saved!.blocks.single.title, 'Rondo 5 mot 2');
    await tester.tap(find.byKey(const Key('training-session-save')));
    await tester.pumpAndSettle();
    expect(sessions.saved!.theme, 'Spelvändning');
    expect(sessions.saved!.blocks.map((b) => b.minutes), [18, 63, 9]);
    expect(sessions.saved!.published, isTrue);

    // A wide window uses the planning surface; the same draft survives
    // resizing back to the mobile card sequence.
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    expect(find.text('Tidslinje'), findsOneWidget);
    expect(find.text('Passets delar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Finder workspaceField(String name) => find.byWidgetPredicate(
      (widget) =>
          widget is TextFormField &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'workspace-$name-',
          ),
    );
    await tester.enterText(workspaceField('title'), 'Rondo i bredd');
    await tester.enterText(
      workspaceField('organisation'),
      'Två ytor, fem spelare per yta.',
    );
    await tester.ensureVisible(workspaceField('coaching'));
    await tester.enterText(
      workspaceField('coaching'),
      'Öppna kroppen före mottagning.',
    );
    await tester.enterText(workspaceField('minutes'), '999');
    await tester.tap(find.byKey(const Key('training-session-save')));
    await tester.pumpAndSettle();
    expect(find.text('Ange 0–240 minuter.'), findsOneWidget);
    expect(sessions.saved!.blocks.first.title, 'Uppvärmning');
    await tester.enterText(workspaceField('minutes'), '22');
    await tester.tap(find.byKey(const Key('training-session-save')));
    await tester.pumpAndSettle();
    expect(sessions.saved!.blocks.first.title, 'Rondo i bredd');
    expect(sessions.saved!.blocks.first.minutes, 22);
    expect(
      sessions.saved!.blocks.first.organisation,
      'Två ytor, fem spelare per yta.',
    );
    expect(
      sessions.saved!.blocks.first.coachingPoints,
      'Öppna kroppen före mottagning.',
    );
    expect(sessions.saved!.blocks[1].minutes, 63);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Lägg till övning').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('training-block-title')),
      'Andra uppvärmningen',
    );
    await tester.enterText(
      find.byKey(const Key('training-block-minutes')),
      '7',
    );
    await tester.tap(find.byKey(const Key('training-block-save')));
    await tester.pumpAndSettle();
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-session-save')));
    await tester.pumpAndSettle();
    expect(sessions.saved!.blocks.map((b) => b.title), [
      'Andra uppvärmningen',
      'Rondo i bredd',
      'Huvuddel',
      'Avslutning',
    ]);
    expect(
      sessions.saved!.blocks[1].organisation,
      'Två ytor, fem spelare per yta.',
    );
    expect(sessions.saved!.blocks.map((b) => b.minutes), [7, 22, 63, 9]);
    // Moving across phase boundaries is rejected; phase changes use the property field.
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 3);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('training-session-save')))
          .onPressed,
      isNull,
    );
    tester.view.physicalSize = const Size(390, 1400);
    await tester.pumpAndSettle();
    expect(find.text('Spelvändning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a leader evaluates a session after the training', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessions = _Sessions(started: true);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'training'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          modules: const _Modules(),
          calendar: _Calendar(sessions),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bottom-nav-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbetsytor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-module-module.training')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('module-next-training-open')));
    await tester.pumpAndSettle();

    // The evaluation shows on the session once it has started.
    await tester.ensureVisible(find.byKey(const Key('training-evaluation')));
    expect(find.text('7 närvarade · 10 kallade, 8 tackade ja'), findsOneWidget);
    await tester.tap(find.byKey(const Key('training-evaluation-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('training-evaluation-star-4')));
    await tester.tap(find.text('Ja'));
    await tester.tap(find.text('Bra'));
    await tester.enterText(
      find.byKey(const Key('training-evaluation-next')),
      'Följ upp pressen',
    );
    await tester.tap(find.byKey(const Key('training-evaluation-save')));
    await tester.pumpAndSettle();
    final saved = sessions.evaluation!;
    expect(
      [saved.rating, saved.goalReached, saved.nextTime],
      [4, GoalReached.yes, 'Följ upp pressen'],
    );
    expect(saved.blocks.single.title, 'Rondo');
    expect(saved.blocks.single.rating, BlockRating.good);
    expect(
      find.textContaining('Till nästa pass: Följ upp pressen'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'English training planning and evaluation preserve user content',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sessions = _Sessions(started: true);
      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'training'),
          locale: const Locale('en'),
          services: AppServices(
            identity: _Identity(),
            modules: const _Modules(),
            calendar: _Calendar(sessions),
            isConfigured: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bottom-nav-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workspaces'));
      await tester.pumpAndSettle();
      expect(find.text('Training'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('workspace-module-module.training')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Previous'), findsOneWidget);
      expect(find.textContaining('No session planned yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('module-next-training-open')));
      await tester.pumpAndSettle();
      expect(find.text('Training session'), findsOneWidget);
      expect(find.text('Warm-up'), findsOneWidget);
      expect(find.text('Press'), findsOneWidget);
      expect(find.text('12 of 90 min planned'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('training-add-main')));
      await tester.tap(find.byKey(const Key('training-add-main')));
      await tester.pumpAndSettle();
      expect(find.text('New exercise'), findsOneWidget);
      expect(find.text('Minutes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('training-block-phase')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Regaining possession (without the ball)').last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('training-block-title')),
        'Återerövring',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('training-block-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('training-session-save')));
      await tester.pumpAndSettle();
      expect(sessions.saved!.blocks.last.title, 'Återerövring');
      expect(sessions.saved!.blocks.last.phase, PrincipleArea.regaining);

      await tester.ensureVisible(find.byKey(const Key('training-evaluation')));
      expect(
        find.text('7 attended · 10 called up, 8 accepted'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('training-evaluation-open')));
      await tester.pumpAndSettle();
      expect(find.text('Did you reach the training goals?'), findsOneWidget);
      await tester.tap(find.byTooltip('4 out of 5'));
      await tester.tap(find.text('Yes'));
      await tester.tap(find.text('Good').first);
      await tester.enterText(
        find.byKey(const Key('training-evaluation-next')),
        'Följ upp pressen',
      );
      await tester.tap(find.byKey(const Key('training-evaluation-save')));
      await tester.pumpAndSettle();
      expect(sessions.evaluation!.nextTime, 'Följ upp pressen');
      expect(sessions.evaluation!.goalReached, GoalReached.yes);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Sessions implements TrainingServices {
  _Sessions({this.started = false});
  final bool started;
  TrainingSession? saved;
  TrainingEvaluation? evaluation;
  late final DateTime _start = started
      ? DateTime.now().subtract(const Duration(hours: 1))
      : DateTime.now().add(const Duration(days: 1));

  TrainingSession get _empty => TrainingSession(
    eventId: 'training-1',
    canEdit: true,
    title: 'Träning',
    startsAt: _start,
    endsAt: _start.add(const Duration(minutes: 90)),
    theme: 'Press',
    eventPlan: 'Rondo, press 4v4, match',
    blocks: started
        ? const [
            TrainingBlock(
              part: TrainingPart.warmup,
              title: 'Rondo',
              minutes: 12,
            ),
          ]
        : const [],
    revision: started ? 1 : 0,
  );

  @override
  Future<TrainingSession?> getSession(String eventId) async => saved ?? _empty;

  @override
  Future<TrainingSession> saveSession({
    required String eventId,
    required int expectedRevision,
    required String theme,
    required String goal,
    required bool published,
    required List<TrainingBlock> blocks,
  }) async => saved = TrainingSession(
    eventId: eventId,
    canEdit: true,
    title: 'Träning',
    startsAt: _start,
    endsAt: _start.add(const Duration(minutes: 90)),
    revision: expectedRevision + 1,
    published: published,
    theme: theme,
    goal: goal,
    blocks: blocks,
  );

  @override
  Future<List<ModuleTraining>> listTrainings({
    required String teamId,
    required DateTime from,
    required DateTime to,
  }) async => [
    ModuleTraining(
      eventId: 'training-1',
      title: 'Träning',
      startsAt: _start,
      endsAt: _start.add(const Duration(minutes: 90)),
      state: 'scheduled',
      session: saved == null ? 'none' : 'published',
      theme: 'Press',
    ),
  ];

  @override
  Future<TrainingEvaluation> getEvaluation(String eventId) async =>
      evaluation ??
      TrainingEvaluation(
        eventId: eventId,
        canEdit: true,
        started: started,
        revision: 0,
        called: 10,
        accepted: 8,
        attended: 7,
        recorded: 9,
      );

  @override
  Future<TrainingEvaluation> saveEvaluation({
    required String eventId,
    required int expectedRevision,
    int? rating,
    GoalReached? goalReached,
    required String wentWell,
    required String doDifferently,
    required String nextTime,
    required List<EvaluatedBlock> blocks,
  }) async => evaluation = TrainingEvaluation(
    eventId: eventId,
    canEdit: true,
    started: true,
    revision: expectedRevision + 1,
    rating: rating,
    goalReached: goalReached,
    wentWell: wentWell,
    doDifferently: doDifferently,
    nextTime: nextTime,
    blocks: blocks,
    called: 10,
    accepted: 8,
    attended: 7,
    recorded: 9,
  );
}

class _Calendar extends UnconfiguredCalendarServices {
  @override
  Future<SquadDetails> getEventSquad(String eventId) async => SquadDetails(
    eventId: eventId,
    state: 'empty',
    members: const [],
    callups: const [],
    attendance: const [],
    roster: const [
      EventRosterPerson(
        personId: 'player-1',
        name: 'Alex Spelare',
        teamId: 'team',
        teamName: 'P2012',
        rolePackage: 'player',
        inDraft: false,
        callupId: 'callup-1',
        callupState: 'accepted',
      ),
      EventRosterPerson(
        personId: 'player-2',
        name: 'Bertil Obesvarad',
        teamId: 'team',
        teamName: 'P2012',
        rolePackage: 'player',
        inDraft: false,
        callupId: 'callup-2',
        callupState: 'pending',
      ),
      EventRosterPerson(
        personId: 'player-3',
        name: 'Cecilia Nekad',
        teamId: 'team',
        teamName: 'P2012',
        rolePackage: 'player',
        inDraft: false,
        callupId: 'callup-3',
        callupState: 'declined',
      ),
      EventRosterPerson(
        personId: 'player-4',
        name: 'Dani Okallad',
        teamId: 'team',
        teamName: 'P2012',
        rolePackage: 'player',
        inDraft: false,
      ),
    ],
    callerActions: const {},
    selectionSource: 'manual',
    selectionContext: const {},
    dispatchKind: 'none',
  );
  _Calendar(this.trainingSessions);
  @override
  final TrainingServices trainingSessions;
}

class _Modules implements ModuleServices {
  const _Modules();
  @override
  TeamDevelopmentServices get teamDevelopment =>
      const UnconfiguredTeamDevelopmentServices();
  @override
  Future<TeamModules> getTeamModules({required String teamId}) async =>
      TeamModules.fromJson(const {
        'modules': [
          {
            'key': 'module.training',
            'title': 'Träning',
            'description': 'Träningspass med övningar',
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
      capabilities: {'training.plan', 'event.manage'},
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
