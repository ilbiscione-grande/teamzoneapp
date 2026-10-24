import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
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
    expect(saved.blocks.map((b) => [b.part, b.title, b.minutes]).toList(), [
      [TrainingPart.warmup, 'Rondo 5 mot 2', 12],
    ]);
    expect(find.textContaining('visas för spelarna'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Sessions implements TrainingServices {
  TrainingSession? saved;
  static final _start = DateTime.now().add(const Duration(days: 1));

  TrainingSession get _empty => TrainingSession(
    eventId: 'training-1',
    canEdit: true,
    title: 'Träning',
    startsAt: _start,
    endsAt: _start.add(const Duration(minutes: 90)),
    revision: 0,
    theme: 'Press',
    eventPlan: 'Rondo, press 4v4, match',
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
}

class _Calendar extends UnconfiguredCalendarServices {
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
