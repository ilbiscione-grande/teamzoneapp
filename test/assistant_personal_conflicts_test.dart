import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_tasks.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';
import 'assistant_context_tasks_test.dart' as fixtures;

class PersonalOverview extends fixtures.Overview
    implements PersonalCalendarConflictServices {
  bool fail = false;
  @override
  Future<Map<String, dynamic>> loadPersonalCalendarConflicts() async {
    if (fail) throw StateError('offline');
    return {
      'generated_at': '2026-10-02T12:00:00Z',
      'tasks': [
        {
          'kind': 'personal_calendar_conflict',
          'title': 'Möjlig personlig krock',
          'count': 1,
          'priority': 0,
          'route': '/calendar?event=one&overlap=two',
          'first_event': {
            'context_id': 'a',
            'event_id': 'one',
            'response': 'accepted',
          },
          'second_event': {
            'context_id': 'b',
            'event_id': 'two',
            'response': 'pending',
          },
        },
      ],
    };
  }
}

void main() {
  final contexts = [
    fixtures.team('a', role: 'player'),
    fixtures.team('b', role: 'player'),
  ];
  test(
    'players receive private pairs without leader capabilities and reject moved events',
    () async {
      final overview = PersonalOverview();
      final result = await loadAssistantTasks(
        contexts: contexts,
        overview: overview,
        loadEvent: fixtures.event,
      );
      expect(result.tasks, hasLength(1));
      expect(result.tasks.single.overlappingContext!.clubId, 'club-b');
      expect(result.tasks.single.contextForEvent('two').id, 'b');
      expect(overview.calls, isEmpty);
      final moved = await loadAssistantTasks(
        contexts: contexts,
        overview: overview,
        loadEvent: (id) => fixtures.event(id, hour: id == 'two' ? 19 : 18),
      );
      expect(moved.tasks, isEmpty);
      final inaccessible = await loadAssistantTasks(
        contexts: contexts,
        overview: overview,
        loadEvent: (id) {
          if (id == 'two') throw StateError('revoked');
          return fixtures.event(id);
        },
      );
      expect(inaccessible.tasks, isEmpty);
      expect(inaccessible.personalFailed, isTrue);
    },
  );

  testWidgets(
    'personal card labels both clubs, responses and second-team context',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssistantTaskSections(
                contexts: contexts,
                activeContext: contexts.last,
                page: const AssistantPageContext('/calendar/event/two'),
                overview: PersonalOverview(),
                loadEvent: fixtures.event,
                onOpen: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Här och nu'), findsOneWidget);
      expect(find.text('Klubb a · Lag a\n↔ Klubb b · Lag b'), findsOneWidget);
      await tester.tap(find.text('Träning one'));
      await tester.pumpAndSettle();
      expect(find.text('Ditt svar: Kommer'), findsOneWidget);
      expect(find.text('Ditt svar: Obesvarat'), findsOneWidget);
      expect(find.text('Hantera'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
