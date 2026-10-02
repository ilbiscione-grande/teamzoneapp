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
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    await mount(
      tester,
      () async => const AssistantTaskSnapshot([], []),
      token: 1,
    );
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });

  testWidgets('does not display an incomplete or stale count', (tester) async {
    await mount(
      tester,
      () async => AssistantTaskSnapshot([task('active')], [fixtures.team('b')]),
    );
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    await mount(
      tester,
      () async => AssistantTaskSnapshot([task('active', stale: true)], []),
      token: 1,
    );
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
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
}
