import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_tasks.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';

TeamZoneContext team(String id, {String role = 'leader', Set<String>? caps}) =>
    TeamZoneContext(
      id: id,
      clubId: 'club-$id',
      clubName: 'Klubb $id',
      teamId: 'team-$id',
      teamName: 'Lag $id',
      rolePackage: role,
      capabilities: caps ?? {'event.squad.manage', 'event.attendance.manage'},
    );

LeaderHomeTask task(
  String event, {
  String kind = 'pending_callups',
  String? route,
}) => LeaderHomeTask(
  kind: kind,
  title: kind == 'pending_callups' ? 'Obesvarade kallelser' : 'Närvaro saknas',
  count: 2,
  route: route ?? '/calendar?event=$event',
  priority: 1,
);

LeaderHomeProjection home(List<LeaderHomeTask> tasks, {bool stale = false}) =>
    LeaderHomeProjection(
      generatedAt: DateTime(2026, 10, 2, 12),
      todayEvents: const [],
      tasks: tasks,
      planningActions: const [],
      isStale: stale,
    );

Future<EventDetails> event(
  String id, {
  bool callupsRequired = true,
  int hour = 18,
}) async => EventDetails(
  id: id,
  callupsRequired: callupsRequired,
  title: 'Träning $id',
  description: null,
  type: 'training',
  state: 'scheduled',
  startsAt: DateTime(2026, 10, 3, hour),
  endsAt: DateTime(2026, 10, 3, hour + 1),
  allDay: false,
  timezone: 'Europe/Stockholm',
  revision: 1,
  callerActions: {'manage_roster'},
  teams: const [],
  audiences: const [],
);

class Overview extends UnconfiguredOverviewServices {
  final Map<String, LeaderHomeProjection> homes = {};
  final List<String> calls = [];
  final Set<String> failures = {};
  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async {
    calls.add(contextId);
    if (failures.contains(contextId)) throw StateError('denied');
    return homes[contextId] ?? home([]);
  }
}

class FreshOverview extends Overview implements FreshLeaderOverviewServices {
  @override
  Future<LeaderHomeProjection> loadFreshLeaderHome(String contextId) async =>
      throw StateError('revoked');
}

class OrganizedOverview extends Overview implements AssistantTaskStateServices {
  bool fail = false;
  final changes = <String>[];
  @override
  Future<void> setAssistantTaskState({
    required String contextId,
    required String kind,
    required String route,
    required String status,
    int? snoozeMinutes,
  }) async {
    if (fail) throw StateError('network');
    changes.add(status);
    homes[contextId] = home([
      for (final item in homes[contextId]!.tasks)
        LeaderHomeTask(
          kind: item.kind,
          title: item.title,
          count: item.count,
          route: item.route,
          priority: item.priority,
          assistantStatus: status,
          snoozedUntil: status == 'snoozed'
              ? DateTime.now().add(Duration(minutes: snoozeMinutes!))
              : null,
        ),
    ]);
  }
}

void main() {
  test(
    'planning tasks require capabilities and recheck moved conflicts',
    () async {
      final overview = Overview()
        ..homes['a'] = home([
          task(
            'one',
            kind: 'calendar_conflict',
            route: '/calendar?event=one&overlap=two',
          ),
          task(
            'one',
            kind: 'calendar_conflict',
            route: '/calendar?event=one&overlap=three',
          ),
          task('one', kind: 'unfinished_preparation'),
        ]);
      final denied = await loadAssistantTasks(
        contexts: [team('a')],
        overview: overview,
        loadEvent: event,
      );
      expect(denied.tasks, isEmpty);
      final allowed = team('a', caps: {'event.manage', 'event.logistics'});
      final result = await loadAssistantTasks(
        contexts: [allowed],
        overview: overview,
        loadEvent: (id) => event(id, hour: id == 'three' ? 19 : 18),
      );
      expect(result.tasks.length, 2);
      expect(result.tasks.first.overlappingEvent?.id, 'two');
      expect(
        result.tasks.first.overlappingTask.route,
        contains('/two?context=a&tab=info'),
      );
      expect(result.tasks.last.route, contains('tab=preparation'));
      final failed = await loadAssistantTasks(
        contexts: [allowed],
        overview: overview,
        loadEvent: (id) {
          if (id == 'two') throw StateError('revoked');
          return event(id);
        },
      );
      expect(failed.tasks, isEmpty);
      expect(failed.failedContexts, hasLength(1));
    },
  );
  testWidgets('conflict compares both events and offers time editing', (
    tester,
  ) async {
    final context = team('a', caps: {'event.manage'});
    final overview = Overview()
      ..homes['a'] = home([
        task(
          'one',
          kind: 'calendar_conflict',
          route: '/calendar?event=one&overlap=two',
        ),
      ]);
    AssistantTask? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssistantTaskSections(
              contexts: [context],
              activeContext: context,
              page: const AssistantPageContext('/calendar/event/two'),
              overview: overview,
              loadEvent: event,
              onOpen: (task) async {
                opened = task;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Plats saknas'), findsNothing);
    await tester.tap(find.text('Träning one'));
    await tester.pumpAndSettle();
    expect(find.text('Plats saknas'), findsNWidgets(2));
    expect(find.text('Träning two'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Träning one').first).dy,
      lessThan(tester.getTopLeft(find.text('Mina uppgifter')).dy),
    );
    await tester.ensureVisible(find.text('Ändra tid'));
    await tester.tap(find.text('Ändra tid'));
    await tester.pumpAndSettle();
    expect(opened?.eventId, 'one');
    expect(opened?.overlappingEvent?.id, 'two');
    expect(opened?.route, contains('context=a&tab=info'));
    expect(tester.takeException(), isNull);
  });
  test('match follow-up requires match capability and opens Info', () async {
    final overview = Overview()
      ..homes['a'] = home([
        task('result', kind: 'missing_match_result'),
        task('report', kind: 'missing_match_report'),
      ]);
    final denied = await loadAssistantTasks(
      contexts: [team('a')],
      overview: overview,
      loadEvent: event,
    );
    expect(denied.tasks, isEmpty);
    final result = await loadAssistantTasks(
      contexts: [
        team('a', caps: {'match.live'}),
      ],
      overview: overview,
      loadEvent: event,
    );
    expect(result.tasks.length, 2);
    expect(
      result.tasks.map((t) => t.actionLabel),
      containsAll(['Registrera resultat', 'Skriv matchrapport']),
    );
    expect(result.tasks.every((t) => t.route.contains('tab=info')), isTrue);
    expect(
      result.tasks.every((t) => t.explanation.contains('sju dagarna')),
      isTrue,
    );
  });
  test(
    'missing callups uses the server task, respects opt-out and capability',
    () async {
      final overview = Overview()
        ..homes['a'] = home([
          task('required', kind: 'missing_callups'),
          task('optional', kind: 'missing_callups'),
        ]);
      final result = await loadAssistantTasks(
        contexts: [team('a')],
        overview: overview,
        loadEvent: (id) => event(id, callupsRequired: id != 'optional'),
      );
      expect(result.tasks.map((t) => t.eventId), ['required']);
      expect(result.tasks.single.actionLabel, 'Förbered kallelser');
      expect(result.tasks.single.explanation, contains('48 timmar'));
      expect(result.tasks.single.route, contains('tab=participants'));
      final denied = await loadAssistantTasks(
        contexts: [team('a', caps: {})],
        overview: overview,
        loadEvent: event,
      );
      expect(denied.tasks, isEmpty);
    },
  );
  test('page context understands old and new event routes', () {
    expect(const AssistantPageContext('/calendar?event=one').eventId, 'one');
    expect(
      const AssistantPageContext(
        '/calendar/event/two?tab=participants',
      ).eventId,
      'two',
    );
    expect(const AssistantPageContext('/calendar').eventId, isNull);
    expect(const AssistantPageContext('/home').isHome, isTrue);
    expect(
      ProductRouteContract.canonicalInitialLocation(
        '/calendar/event/two?context=b&tab=participants',
      ),
      '/calendar/event/two?context=b&tab=participants',
    );
  });

  test(
    'loads only leader contexts and capabilities, rejects foreign URLs and duplicates',
    () async {
      final overview = Overview()
        ..homes['a'] = home([
          task('one'),
          task('one'),
          task('two', kind: 'missing_attendance'),
          task('bad', route: 'https://evil.example/calendar?event=bad'),
          task('bad2', kind: 'medical'),
        ]);
      final result = await loadAssistantTasks(
        contexts: [
          team('a', caps: {'event.squad.manage'}),
          team('p', role: 'player'),
          team('g', role: 'guardian'),
        ],
        overview: overview,
        loadEvent: event,
      );
      expect(overview.calls, ['a']);
      expect(result.tasks.map((t) => t.eventId), ['one']);
      expect(
        result.tasks.single.route,
        '/calendar/event/one?context=a&tab=participants',
      );
    },
  );

  test('revoked fresh read never falls back to cached tasks', () async {
    final overview = FreshOverview()..homes['a'] = home([task('cached')]);
    final result = await loadAssistantTasks(
      contexts: [team('a')],
      overview: overview,
      loadEvent: event,
    );
    expect(result.tasks, isEmpty);
    expect(result.failedContexts.single.id, 'a');
    expect(overview.calls, isEmpty);
  });

  test('failure drops partial team data and preserves other teams', () async {
    final overview = Overview()
      ..homes['a'] = home([task('one'), task('denied')])
      ..homes['b'] = home([task('three', kind: 'missing_attendance')]);
    final result = await loadAssistantTasks(
      contexts: [team('a'), team('b')],
      overview: overview,
      loadEvent: (id) =>
          id == 'denied' ? Future.error(StateError('denied')) : event(id),
    );
    expect(result.tasks.map((t) => t.eventId), ['three']);
    expect(result.failedContexts.single.id, 'a');
  });

  Widget app(
    Overview overview, {
    String location = '/calendar/event/one',
    Future<void> Function(AssistantTask)? onOpen,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AssistantTaskSections(
          contexts: [team('a'), team('b')],
          activeContext: team('a'),
          page: AssistantPageContext(location),
          overview: overview,
          loadEvent: event,
          onOpen: onOpen ?? (_) async {},
        ),
      ),
    ),
  );

  testWidgets('compact cards expand one at a time and fit a narrow panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(248, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final overview = OrganizedOverview()
      ..homes['a'] = home([task('one'), task('two')]);
    await tester.pumpWidget(app(overview, location: '/home'));
    await tester.pumpAndSettle();
    final filterPositions = ['active', 'snoozed', 'archived']
        .map(
          (id) => tester
              .getTopLeft(find.byKey(ValueKey('assistant-filter-$id')))
              .dy,
        )
        .toSet();
    expect(filterPositions, hasLength(1));
    final actionCenters = [
      'Åtgärda',
      'Skjut upp',
      'Arkivera',
    ].map((label) => tester.getCenter(find.text(label).first).dy).toList();
    expect(actionCenters[1], closeTo(actionCenters[0], 1));
    expect(actionCenters[2], closeTo(actionCenters[0], 1));
    expect(find.text('Aktuellt (2)'), findsNothing);
    expect(find.text('Varför visas detta?'), findsNothing);
    await tester.tap(find.text('Träning one'));
    await tester.pumpAndSettle();
    expect(find.text('Varför visas detta?'), findsOneWidget);
    await tester.ensureVisible(find.text('Träning two'));
    await tester.tap(find.text('Träning two'));
    await tester.pumpAndSettle();
    expect(find.text('Varför visas detta?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('archive restore snooze and failed save preserve domain tasks', (
    tester,
  ) async {
    final overview = OrganizedOverview()..homes['a'] = home([task('one')]);
    await tester.pumpWidget(app(overview, location: '/home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Arkivera'));
    await tester.pumpAndSettle();
    expect(find.text('Träning one'), findsNothing);
    await tester.tap(find.byTooltip('Arkiverat (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Träning one'), findsOneWidget);
    await tester.tap(find.text('Återställ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aktuellt (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Skjut upp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Om en timme'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Uppskjutet (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Uppskjutet till'), findsOneWidget);
    overview.fail = true;
    await tester.tap(find.text('Återställ'));
    await tester.pumpAndSettle();
    expect(find.text('Träning one'), findsOneWidget);
    expect(find.textContaining('Valet kunde inte sparas'), findsOneWidget);
    expect(overview.changes, ['archived', 'active', 'snoozed']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('event context shows matching task once and other tasks below', (
    tester,
  ) async {
    final overview = Overview()
      ..homes['a'] = home([task('one'), task('two')])
      ..homes['b'] = home([task('three')]);
    await tester.pumpWidget(app(overview));
    await tester.pumpAndSettle();
    expect(find.text('Här och nu'), findsOneWidget);
    expect(find.text('Mina uppgifter'), findsOneWidget);
    expect(find.text('Träning one'), findsOneWidget);
    expect(find.text('Träning two'), findsOneWidget);
    expect(find.text('Träning three'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Träning one')).dy,
      lessThan(tester.getTopLeft(find.text('Mina uppgifter')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Träning two')).dy,
      greaterThan(tester.getTopLeft(find.text('Mina uppgifter')).dy),
    );
  });

  testWidgets('home collects tasks; page change recalculates context', (
    tester,
  ) async {
    final overview = Overview()..homes['a'] = home([task('one'), task('two')]);
    await tester.pumpWidget(app(overview, location: '/home'));
    await tester.pumpAndSettle();
    expect(find.text('Här och nu'), findsNothing);
    await tester.pumpWidget(app(overview, location: '/calendar/event/two'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Träning two')).dy,
      lessThan(tester.getTopLeft(find.text('Mina uppgifter')).dy),
    );
  });

  testWidgets('completed task disappears after returning from action', (
    tester,
  ) async {
    final overview = Overview()..homes['a'] = home([task('one')]);
    AssistantTask? opened;
    await tester.pumpWidget(
      app(
        overview,
        onOpen: (item) async {
          opened = item;
          overview.homes['a'] = home([]);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Granska och påminn'));
    await tester.pumpAndSettle();
    expect(opened?.context.id, 'a');
    expect(find.text('Träning one'), findsNothing);
    expect(find.text('Här och nu'), findsNothing);
    expect(find.text('Den här aktiviteten · Lag a'), findsNothing);
    expect(find.text('Inga aktuella uppgifter att visa här.'), findsNothing);
  });

  testWidgets('stale counts are labelled and actions disabled', (tester) async {
    final overview = Overview()..homes['a'] = home([task('one')], stale: true);
    await tester.pumpWidget(app(overview));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sparade uppgifter'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Åtgärda'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('failed team is visibly incomplete and retry recovers', (
    tester,
  ) async {
    final overview = Overview()..failures.add('a');
    await tester.pumpWidget(app(overview));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-task-error')), findsOneWidget);
    expect(find.text('Övriga uppgifter är klara.'), findsNothing);
    overview.failures.clear();
    overview.homes['a'] = home([task('one')]);
    await tester.tap(find.byTooltip('Uppdatera uppgifter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-task-error')), findsNothing);
    expect(find.text('Träning one'), findsOneWidget);
  });
}
