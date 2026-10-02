import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_preparation_checklist.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_tasks.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/calendar/preparation_models.dart';
import 'package:teamzone_app/src/features/calendar/preparation_services.dart';
import 'assistant_context_tasks_test.dart' as fixtures;

class Preparation extends UnconfiguredEventPreparationServices {
  int reads = 0;
  bool permitted = true;
  bool fail = false;
  final writes = <String>[];
  List<PreparationItem> items = const [
    PreparationItem(id: 'ball', kind: 'material', label: 'Bollar'),
    PreparationItem(
      id: 'ride',
      kind: 'task',
      label: 'Boka skjuts',
      assigneeName: 'Ledare',
    ),
    PreparationItem(id: 'done', kind: 'task', label: 'Redan klar', done: true),
    PreparationItem(id: 'focus', kind: 'focus', label: 'Passningsspel'),
  ];
  @override
  Future<EventPreparation> getPreparation(String eventId) async {
    reads++;
    return EventPreparation(eventId: eventId, canEdit: permitted, items: items);
  }

  @override
  Future<PreparationItem> setItemDone(String itemId, bool done) async {
    writes.add(itemId);
    if (fail) throw StateError('offline');
    final updated = items
        .firstWhere((i) => i.id == itemId)
        .copyWith(done: done);
    items = [
      for (final i in items)
        if (i.id == itemId) updated else i,
    ];
    return updated;
  }
}

class PreparationOverview extends fixtures.Overview {
  PreparationOverview(this.preparation);
  final Preparation preparation;
  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async =>
      fixtures.home([
        if (preparation.items.any((i) => i.kind == 'task' && !i.done))
          fixtures.task('event', kind: 'unfinished_preparation'),
      ]);
}

void main() {
  testWidgets('loads on action only and removes finished task from assistant', (
    tester,
  ) async {
    final service = Preparation()
      ..items = const [
        PreparationItem(id: 'ride', kind: 'task', label: 'Boka skjuts'),
      ];
    final team = fixtures.team('a', caps: {'event.logistics'});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssistantTaskSections(
              contexts: [team],
              activeContext: team,
              page: const AssistantPageContext('/home'),
              overview: PreparationOverview(service),
              loadEvent: fixtures.event,
              preparation: service,
              onOpen: (_) async => fail('Should expand inline'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.reads, 0);
    await tester.tap(find.text('Åtgärda'));
    await tester.pumpAndSettle();
    expect(find.text('Boka skjuts'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-preparation-ride')));
    await tester.pumpAndSettle();
    expect(find.text('Åtgärda'), findsNothing);
    expect(find.text('Inga aktuella uppgifter att visa.'), findsOneWidget);
  });
  Future<void> mount(
    WidgetTester tester,
    Preparation service,
    VoidCallback changed, {
    bool allowEdit = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 248,
              child: AssistantPreparationChecklist(
                eventId: 'event',
                services: service,
                loadEvent: fixtures.event,
                allowEdit: allowEdit,
                onChanged: changed,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows remaining actionable items and refreshes after saving', (
    tester,
  ) async {
    final service = Preparation();
    var changes = 0;
    await mount(tester, service, () => changes++);
    expect(find.text('Bollar'), findsOneWidget);
    expect(find.text('Boka skjuts'), findsOneWidget);
    expect(find.text('Redan klar'), findsNothing);
    expect(find.text('Passningsspel'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('assistant-preparation-ball')));
    await tester.pumpAndSettle();
    expect(service.writes, ['ball']);
    expect(changes, 1);
    expect(find.text('Bollar'), findsNothing);
    expect(find.text('Boka skjuts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save retains item and permits retry', (tester) async {
    final service = Preparation()..fail = true;
    var changes = 0;
    await mount(tester, service, () => changes++);
    await tester.tap(find.byKey(const ValueKey('assistant-preparation-ball')));
    await tester.pumpAndSettle();
    expect(find.text('Bollar'), findsOneWidget);
    expect(find.textContaining('kunde inte sparas'), findsOneWidget);
    expect(changes, 0);
    service.fail = false;
    await tester.tap(find.byKey(const ValueKey('assistant-preparation-ball')));
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(find.text('Bollar'), findsNothing);
  });

  testWidgets('server and context permissions both prevent edits', (
    tester,
  ) async {
    final service = Preparation()..permitted = false;
    await mount(tester, service, () {});
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .onChanged,
      isNull,
    );
    service.permitted = true;
    await mount(tester, service, () {}, allowEdit: false);
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .onChanged,
      isNull,
    );
    expect(service.writes, isEmpty);
  });
}
