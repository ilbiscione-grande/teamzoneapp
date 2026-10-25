import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_task_badge.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_tasks.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'assistant_context_tasks_test.dart' as fixtures;

AssistantTask task(String status, {bool stale = false}) => AssistantTask(
  context: fixtures.team('a'),
  eventId: status,
  generatedAt: DateTime.now(),
  stale: stale,
  task: LeaderHomeTask(
    kind: 'pending_callups',
    title: 'Kallelser',
    count: 15,
    route: '/calendar?event=$status',
    priority: 1,
    assistantStatus: status,
  ),
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    Future<AssistantTaskSnapshot> Function() load, {
    int token = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        supportedLocales: const [Locale('sv')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: AssistantTaskBadge(
            load: load,
            refreshToken: token,
            child: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.assistant),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('important tasks add a yellow exclamation badge', (tester) async {
    final today = AssistantTask(
      context: fixtures.team('a'),
      eventId: 'today',
      stale: false,
      generatedAt: DateTime.now(),
      startsAt: DateTime.now().add(const Duration(hours: 3)),
      task: const LeaderHomeTask(
        kind: 'pending_callups',
        title: 'Kallelser',
        count: 16,
        route: '/calendar?event=today',
        priority: 1,
        assistantStatus: 'active',
      ),
    );
    await mount(
      tester,
      () async => AssistantTaskSnapshot([today, task('active')], []),
    );
    final important = find.byKey(const Key('assistant-task-important'));
    expect(tester.widget<Badge>(important).isLabelVisible, isTrue);
    expect(find.text('!'), findsOneWidget);
    await mount(
      tester,
      () async => AssistantTaskSnapshot([task('active')], []),
      token: 1,
    );
    expect(tester.widget<Badge>(important).isLabelVisible, isFalse);
  });

  testWidgets('counts only active cards and hides zero', (tester) async {
    await mount(
      tester,
      () async => AssistantTaskSnapshot([
        task('active'),
        task('active'),
        task('snoozed'),
        task('archived'),
      ], []),
    );
    expect(find.text('2'), findsOneWidget);
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('assistant-task-count')))
          .isLabelVisible,
      isTrue,
    );
    await mount(
      tester,
      () async => const AssistantTaskSnapshot([], []),
      token: 1,
    );
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('assistant-task-count')))
          .isLabelVisible,
      isFalse,
    );
  });

  testWidgets('does not display an incomplete or stale count', (tester) async {
    await mount(
      tester,
      () async => AssistantTaskSnapshot([task('active')], [fixtures.team('b')]),
    );
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('assistant-task-count')))
          .isLabelVisible,
      isFalse,
    );
    await mount(
      tester,
      () async => AssistantTaskSnapshot([task('active', stale: true)], []),
      token: 1,
    );
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('assistant-task-count')))
          .isLabelVisible,
      isFalse,
    );
  });

  testWidgets('late response cannot replace the new context count', (
    tester,
  ) async {
    final old = Completer<AssistantTaskSnapshot>();
    await mount(tester, () => old.future);
    await mount(
      tester,
      () async => AssistantTaskSnapshot([task('active')], []),
      token: 1,
    );
    old.complete(AssistantTaskSnapshot([task('active'), task('active')], []));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides the button only when nothing is confirmed current', (
    tester,
  ) async {
    final gate = Completer<AssistantTaskSnapshot>();
    Future<AssistantTaskSnapshot> Function() answer = () => gate.future;
    var token = 0;
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        supportedLocales: const [Locale('sv')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: AssistantTaskBadge(
            load: () => answer(),
            refreshToken: token,
            hideWhenEmpty: true,
            child: const Icon(Icons.assistant, key: Key('fab')),
          ),
        ),
      ),
    );
    await show();
    expect(find.byKey(const Key('fab')), findsOneWidget, reason: 'loading');
    gate.complete(AssistantTaskSnapshot([task('snoozed')], []));
    await tester.pump();
    expect(find.byKey(const Key('fab')), findsNothing, reason: 'zero');
    // A refresh that is still loading keeps it hidden: no flash.
    final next = Completer<AssistantTaskSnapshot>();
    answer = () => next.future;
    token++;
    await show();
    expect(find.byKey(const Key('fab')), findsNothing);
    next.complete(AssistantTaskSnapshot([task('active')], []));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('fab')), findsOneWidget, reason: 'one current');
    // A read error is not a zero: the button shows.
    answer = () => Future.error(StateError('offline'));
    token++;
    await show();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('fab')), findsOneWidget);
  });
}
