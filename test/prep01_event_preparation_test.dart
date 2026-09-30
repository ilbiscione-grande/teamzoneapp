import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/calendar/preparation_models.dart';
import 'package:teamzone_app/src/features/match/match_models.dart';
import 'package:teamzone_app/src/features/match/match_services.dart';

void main() {
  group('Träning', () {
    testWidgets('focus from earlier use, custom focus and removal', (
      tester,
    ) async {
      final prep = _Prep()..suggestions = ['Speluppbyggnad', 'Presspel'];
      await _openPreparation(tester, _Calendar('training', prep));
      expect(find.text('TRÄNINGSFOKUS'), findsOneWidget);
      expect(find.text('ANTECKNINGAR'), findsOneWidget);
      expect(find.text('MATERIAL'), findsOneWidget);
      expect(find.text('UPPGIFTER'), findsOneWidget);
      expect(find.text('FILER'), findsOneWidget);
      // No overall progress anywhere.
      expect(find.textContaining('klara'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.text('Lägg till').first);
      await tester.pumpAndSettle();
      expect(find.text('Tidigare använda'), findsOneWidget);
      await tester.tap(find.text('Speluppbyggnad'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Tredje man');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Klar'));
      await tester.pumpAndSettle();
      expect(prep.labels('focus'), ['Speluppbyggnad', 'Tredje man']);
      expect(find.widgetWithText(InputChip, 'Tredje man'), findsOneWidget);

      await tester.tap(find.byTooltip('Ta bort Speluppbyggnad'));
      await tester.pumpAndSettle();
      expect(prep.labels('focus'), ['Tredje man']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('note, material checklist and task with owner', (tester) async {
      final prep = _Prep()..suggestions = ['Bollar', 'Koner'];
      await _openPreparation(tester, _Calendar('training', prep));

      await tester.tap(
        find.descendant(
          of: _sectionFor('ANTECKNINGAR'),
          matching: find.text('Lägg till'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Fokus på speluppbyggnad.\nAvsluta med 8v8.',
      );
      await tester.tap(find.text('Spara'));
      await tester.pumpAndSettle();
      expect(prep.note.body, 'Fokus på speluppbyggnad.\nAvsluta med 8v8.');
      expect(find.textContaining('Avsluta med 8v8.'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: _sectionFor('MATERIAL'),
          matching: find.text('Lägg till'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bollar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Klar'));
      await tester.pumpAndSettle();
      expect(prep.labels('material'), ['Bollar']);
      await tester.tap(find.text('Bollar'));
      await tester.pumpAndSettle();
      expect(prep.items.single.done, isTrue);

      await tester.ensureVisible(find.text('Lägg till').last);
      await tester.tap(
        find.descendant(
          of: _sectionFor('UPPGIFTER'),
          matching: find.text('Lägg till'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Ta fram material');
      await tester.tap(find.text('Johan Lind'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spara'));
      await tester.pumpAndSettle();
      final task = prep.items.firstWhere((item) => item.kind == 'task');
      expect(task.assigneePersonId, 'johan');
      expect(find.text('Johan Lind'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(Checkbox),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Ta fram material, Johan Lind',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(prep.items.firstWhere((item) => item.kind == 'task').done, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('file visibility can be changed per file', (tester) async {
      final prep = _Prep()
        ..files = [
          EventFile(
            id: 'file-1',
            name: 'Träningsplan.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 1200000,
            visibility: FileVisibility.participants,
            revision: 1,
            createdAt: DateTime(2026, 9, 27),
          ),
          EventFile(
            id: 'file-2',
            name: 'Rehab.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 200000,
            visibility: FileVisibility.selected,
            revision: 1,
            createdAt: DateTime(2026, 9, 27),
            viewerCount: 2,
            viewerIds: const ['erik', 'johan'],
          ),
        ];
      await _openPreparation(tester, _Calendar('training', prep));
      await tester.ensureVisible(find.text('Träningsplan.pdf'));
      expect(find.text('Alla'), findsOneWidget);
      expect(find.text('2 pers.'), findsOneWidget);
      await tester.tap(find.byTooltip('Fler val').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ändra synlighet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Endast ledare'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spara'));
      await tester.pumpAndSettle();
      expect(prep.visibilityCalls.single.$1, 'file-1');
      expect(prep.visibilityCalls.single.$2, 'leaders');
      expect(prep.visibilityCalls.single.$3, isEmpty);
      expect(find.text('Ledare'), findsOneWidget);

      await tester.tap(find.byTooltip('Fler val').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ändra synlighet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erik Andersson'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spara'));
      await tester.pumpAndSettle();
      expect(prep.visibilityCalls.last.$1, 'file-2');
      expect(prep.visibilityCalls.last.$2, 'selected');
      expect(prep.visibilityCalls.last.$3, ['johan']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('read-only user sees content without edit controls', (
      tester,
    ) async {
      final prep = _Prep(canEdit: false)
        ..items = [
          const PreparationItem(id: 'f', kind: 'focus', label: 'Presspel'),
          const PreparationItem(
            id: 'm',
            kind: 'material',
            label: 'Västar',
            done: true,
          ),
        ];
      await _openPreparation(tester, _Calendar('training', prep));
      expect(find.text('Presspel'), findsOneWidget);
      expect(find.text('Västar'), findsOneWidget);
      expect(find.text('Lägg till'), findsNothing);
      expect(find.text('UPPGIFTER'), findsNothing, reason: 'empty is hidden');
      expect(find.byTooltip('Ta bort Presspel'), findsNothing);
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);
      expect(checkbox.onChanged, isNull);
    });

    testWidgets('conflict reloads instead of overwriting', (tester) async {
      final prep = _Prep()..conflictOnSave = true;
      await _openPreparation(tester, _Calendar('training', prep));
      await tester.tap(
        find.descendant(
          of: _sectionFor('ANTECKNINGAR'),
          matching: find.text('Lägg till'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Min text');
      await tester.tap(find.text('Spara'));
      await tester.pumpAndSettle();
      expect(
        find.text('Din text finns kvar. Den sparade versionen har ändrats.'),
        findsOneWidget,
      );
      expect(find.text('Min text'), findsOneWidget);
    });
  });

  testWidgets('Möte: agenda, reorder, tick, tasks, notes and files', (
    tester,
  ) async {
    final prep = _Prep()
      ..items = [
        const PreparationItem(
          id: 'a1',
          kind: 'agenda',
          label: 'Föregående möte',
          position: 0,
        ),
        const PreparationItem(
          id: 'a2',
          kind: 'agenda',
          label: 'Spelartrupp 2027',
          position: 1,
        ),
      ];
    await _openPreparation(tester, _Calendar('meeting', prep));
    final headers = ['AGENDA', 'UPPGIFTER', 'ANTECKNINGAR', 'FILER'];
    for (var i = 0; i < headers.length - 1; i++) {
      expect(
        tester.getTopLeft(find.text(headers[i])).dy,
        lessThan(tester.getTopLeft(find.text(headers[i + 1])).dy),
      );
    }
    expect(find.text('TRÄNINGSFOKUS'), findsNothing);
    expect(find.text('MATERIAL'), findsNothing);

    await tester.tap(find.text('Lägg till punkt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Övriga frågor');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Klar'));
    await tester.pumpAndSettle();
    expect(prep.labels('agenda'), [
      'Föregående möte',
      'Spelartrupp 2027',
      'Övriga frågor',
    ]);

    await tester.timedDrag(
      find.byIcon(Icons.drag_indicator).last,
      const Offset(0, -44),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    final added = prep.items.firstWhere((i) => i.label == 'Övriga frågor').id;
    expect(prep.reorders.single, ['a1', added, 'a2']);
    expect(prep.labels('agenda'), [
      'Föregående möte',
      'Övriga frågor',
      'Spelartrupp 2027',
    ]);

    await tester.tap(find.text('Föregående möte'));
    await tester.pumpAndSettle();
    final first = find.ancestor(
      of: find.text('Föregående möte'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: first.first, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(prep.items.firstWhere((item) => item.id == 'a1').done, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each area follows its own permission', (tester) async {
    // A team manager: logistics, but neither training plan nor tactics.
    final prep =
        _Prep(permissions: const PreparationPermissions(logistics: true))
          ..items = [
            const PreparationItem(id: 'f', kind: 'focus', label: 'Presspel'),
          ];
    await _openPreparation(tester, _Calendar('training', prep));
    expect(find.text('Presspel'), findsOneWidget, reason: 'still readable');
    expect(find.byTooltip('Ta bort Presspel'), findsNothing);
    expect(find.text('ANTECKNINGAR'), findsNothing, reason: 'empty and locked');
    expect(
      find.descendant(
        of: _sectionFor('MATERIAL'),
        matching: find.text('Lägg till'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _sectionFor('UPPGIFTER'),
        matching: find.text('Lägg till'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tactics permission edits only the match preparation note', (
    tester,
  ) async {
    final prep = _Prep(permissions: const PreparationPermissions(match: true));
    await _openPreparation(tester, _Calendar('match', prep));
    expect(
      find.descendant(
        of: _sectionFor('MATCHFÖRBEREDELSE'),
        matching: find.text('Lägg till'),
      ),
      findsOneWidget,
    );
    expect(find.text('MATERIAL'), findsNothing);
    expect(find.text('UPPGIFTER'), findsNothing);
  });

  group('Match', () {
    testWidgets('preparation sections and open match mode', (tester) async {
      final match = _Match();
      await _openPreparation(tester, _Calendar('match', _Prep()), match: match);
      expect(find.text('Öppna matchläge'), findsOneWidget);
      expect(find.text('MATCHFÖRBEREDELSE'), findsOneWidget);
      expect(find.text('MATERIAL'), findsOneWidget);
      expect(find.text('TRÄNINGSFOKUS'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Öppna matchläge')).dy,
        lessThan(tester.getTopLeft(find.text('MATCHFÖRBEREDELSE')).dy),
      );
      await _openMatchMode(tester);
      expect(find.text('Matchläge'), findsOneWidget);
      expect(find.text('F2012'), findsWidgets);
      expect(find.text('Vetlanda'), findsWidgets);
      expect(find.text('Starta match'), findsOneWidget);
      await _closeMatchMode(tester);
    });

    testWidgets('start, pause, goals with scorer/assist and opponent goal', (
      tester,
    ) async {
      final match = _Match();
      await _openPreparation(tester, _Calendar('match', _Prep()), match: match);
      await _openMatchMode(tester);
      await tester.tap(find.text('Starta match'));
      await _pumpFrames(tester);
      expect(match.commands.map((c) => c.$1), ['freeze', 'start']);
      expect(find.text('Pausa'), findsOneWidget);

      await tester.tap(find.byTooltip('Mål för F2012'));
      await _pumpFrames(tester);
      expect(find.text('Vem gjorde målet?'), findsOneWidget);
      // Leaders are in the squad but cannot score.
      expect(find.text('Thomas Emilson'), findsNothing);
      await tester.tap(find.text('Erik Andersson'));
      await _pumpFrames(tester);
      expect(find.text('Assist?'), findsOneWidget);
      await tester.tap(find.text('Johan Lind'));
      await _pumpFrames(tester);
      final goal = match.facts.single;
      expect(goal['club_person_id'], 'erik');
      expect(goal['secondary_club_person_id'], 'johan');
      expect(goal['minute'], 1);
      expect(find.text('Assist: Johan Lind'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      await tester.tap(find.byTooltip('Mål för F2012'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Okänd målskytt'));
      await _pumpFrames(tester);
      expect(match.facts.last['club_person_id'], isNull);
      expect(find.text('Okänd målskytt'), findsOneWidget);

      await tester.tap(find.byTooltip('Mål för Vetlanda'));
      await _pumpFrames(tester);
      expect(match.facts.last['side'], 'opponent');
      expect(find.text('Ångra'), findsOneWidget);
      expect(match.scoreUs, 2);
      expect(match.scoreOpponent, 1);

      await tester.tap(find.text('Pausa'));
      await _pumpFrames(tester);
      expect(find.text('Fortsätt'), findsOneWidget);
      await _closeMatchMode(tester);
    });

    testWidgets('minus removes the latest goal, edit corrects minute', (
      tester,
    ) async {
      final match = _Match()..goLive(minutesAgo: 30);
      match.addGoal('us', 12, scorer: 'erik');
      match.addGoal('us', 25, scorer: 'johan');
      await _openPreparation(tester, _Calendar('match', _Prep()), match: match);
      await _openMatchMode(tester);
      await tester.tap(find.byTooltip('Ta bort mål för F2012'));
      await _pumpFrames(tester);
      expect(find.text('Målet 25′ Johan Lind tas bort.'), findsOneWidget);
      await tester.tap(find.text('Ta bort'));
      await _pumpFrames(tester);
      expect(match.scoreUs, 1);
      expect(match.commands.last.$1, 'void');

      await tester.tap(find.byTooltip('Redigera händelse').first);
      await _pumpFrames(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Minut'), '14');
      await tester.pump();
      await tester.tap(find.text('Spara'));
      await _pumpFrames(tester);
      expect(match.facts.first['minute'], 14);
      expect(match.facts.first['club_person_id'], 'erik');
      expect(find.text('14′'), findsOneWidget);
      await _closeMatchMode(tester);
    });

    testWidgets('failed goal is not shown and retry reuses the command', (
      tester,
    ) async {
      final match = _Match()
        ..goLive(minutesAgo: 10)
        ..failNext = true;
      await _openPreparation(tester, _Calendar('match', _Prep()), match: match);
      await _openMatchMode(tester);
      await tester.tap(find.byTooltip('Mål för Vetlanda'));
      await _pumpFrames(tester);
      expect(match.facts, isEmpty);
      expect(
        find.text('Ändringen kunde inte bekräftas. Kontrollera anslutningen.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Försök igen'));
      await _pumpFrames(tester);
      expect(match.facts, hasLength(1));
      expect(match.commands[0].$2, match.commands[1].$2, reason: 'same id');
      expect(find.text('Försök igen'), findsNothing);
      expect(match.facts, hasLength(1), reason: 'no duplicate goal');
      await _closeMatchMode(tester);
    });

    testWidgets('clock survives leaving; periods and time correction', (
      tester,
    ) async {
      final match = _Match()..goLive(minutesAgo: 5, extraSeconds: 3);
      await _openPreparation(tester, _Calendar('match', _Prep()), match: match);
      await _openMatchMode(tester);
      expect(find.textContaining('05:0'), findsOneWidget);
      expect(find.text('1:a halvlek'), findsOneWidget);

      await tester.tap(find.text('1:a halvlek'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Avsluta 1:a halvlek'));
      await _pumpFrames(tester);
      // Clock caption and the timeline marker.
      expect(find.text('Halvtid'), findsNWidgets(2));
      expect(find.text('Starta 2:a halvlek'), findsOneWidget);
      await tester.tap(find.text('Starta 2:a halvlek'));
      await _pumpFrames(tester);
      expect(match.currentPeriod, 2);
      expect(find.text('2:a halvlek'), findsOneWidget);

      await tester.tap(find.text('2:a halvlek'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Korrigera tid'));
      await _pumpFrames(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Minuter'), '63');
      await tester.enterText(find.widgetWithText(TextField, 'Sekunder'), '24');
      await tester.pump();
      await tester.tap(find.text('Spara'));
      await _pumpFrames(tester);
      expect(match.commands.last, ('clock', match.commands.last.$2, 3804));
      expect(find.textContaining('63:2'), findsOneWidget);
      await _closeMatchMode(tester);
    });

    testWidgets('match format supports three periods', (tester) async {
      final match = _Match();
      await _openPreparation(tester, _Calendar('match', _Prep()), match: match);
      await _openMatchMode(tester);
      await tester.tap(find.byTooltip('Matchinställningar'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Matchformat'));
      await _pumpFrames(tester);
      await tester.tap(find.text('3 × 30'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Spara'));
      await _pumpFrames(tester);
      expect(match.periods, [30, 30, 30]);
      await _closeMatchMode(tester);
    });

    testWidgets('view-only context sees score without controls', (
      tester,
    ) async {
      final match = _Match()..goLive(minutesAgo: 20);
      match.addGoal('us', 12, scorer: 'erik');
      await _openPreparation(
        tester,
        _Calendar('match', _Prep(canEdit: false)),
        match: match,
        identity: const _SharedTeamIdentity(),
      );
      await _openMatchMode(tester);
      expect(find.text('Erik Andersson'), findsOneWidget);
      expect(find.text('Pausa'), findsNothing);
      expect(find.byTooltip('Mål för F2012'), findsNothing);
      expect(find.byTooltip('Redigera händelse'), findsNothing);
      await _closeMatchMode(tester);
    });
  });
}

Finder _sectionFor(String header) => find
    .ancestor(of: find.text(header), matching: find.byType(DecoratedBox))
    .first;

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openPreparation(
  WidgetTester tester,
  _Calendar calendar, {
  MatchServices match = const UnconfiguredMatchServices(),
  IdentityServices identity = const _Identity(),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TeamZoneApp(
      environment: const AppEnvironment(name: 'prep01', matchSpaceV2: true),
      locale: const Locale('sv'),
      services: AppServices(
        identity: identity,
        calendar: calendar,
        match: match,
        isConfigured: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kalender'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Vy och filter'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agenda').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(calendar.title));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Förberedelser'));
  await tester.pumpAndSettle();
}

Future<void> _openMatchMode(WidgetTester tester) async {
  await tester.tap(find.text('Öppna matchläge'));
  await _pumpFrames(tester);
}

/// The page ticks once a second while the clock runs; unmount it so no
/// periodic timer outlives the test.
Future<void> _closeMatchMode(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
}

class _Prep implements EventPreparationServices {
  _Prep({this.canEdit = true, this.permissions});
  final bool canEdit;
  final PreparationPermissions? permissions;
  List<PreparationItem> items = [];
  PreparationNote note = const PreparationNote();
  List<EventFile> files = [];
  List<String> suggestions = [];
  bool conflictOnSave = false;
  final visibilityCalls = <(String, String, List<String>)>[];
  final reorders = <List<String>>[];

  List<String> labels(String kind) =>
      (items.where((i) => i.kind == kind).toList()
            ..sort((a, b) => a.position.compareTo(b.position)))
          .map((i) => i.label)
          .toList();

  @override
  Future<EventPreparation> getPreparation(String eventId) async =>
      EventPreparation(
        eventId: eventId,
        canEdit: canEdit,
        permissions: permissions,
        items: [...items],
        note: note,
        files: [...files],
      );

  @override
  Future<PreparationItem> saveItem({
    required String eventId,
    required String itemId,
    required String kind,
    required String label,
    String? assigneePersonId,
    required int expectedRevision,
  }) async {
    final existing = items.where((i) => i.id == itemId).firstOrNull;
    final item = PreparationItem(
      id: itemId,
      kind: kind,
      label: label,
      assigneePersonId: assigneePersonId,
      assigneeName: const {
        'erik': 'Erik Andersson',
        'johan': 'Johan Lind',
        'thomas': 'Thomas Emilson',
      }[assigneePersonId],
      position:
          existing?.position ??
          items
                  .where((i) => i.kind == kind)
                  .fold<int>(-1, (m, i) => i.position > m ? i.position : m) +
              1,
      revision: (existing?.revision ?? 0) + 1,
      done: existing?.done ?? false,
    );
    items = [...items.where((i) => i.id != itemId), item];
    return item;
  }

  @override
  Future<PreparationItem> setItemDone(String itemId, bool done) async {
    final item = items.firstWhere((i) => i.id == itemId).copyWith(done: done);
    items = [...items.where((i) => i.id != itemId), item];
    return item;
  }

  @override
  Future<void> deleteItem(String eventId, String itemId) async {
    items = items.where((i) => i.id != itemId).toList();
  }

  @override
  Future<void> reorderItems(
    String eventId,
    String kind,
    List<String> itemIds,
  ) async {
    reorders.add(itemIds);
    items = [
      ...items.where((i) => i.kind != kind),
      for (var n = 0; n < itemIds.length; n++)
        () {
          final i = items.firstWhere((item) => item.id == itemIds[n]);
          return PreparationItem(
            id: i.id,
            kind: i.kind,
            label: i.label,
            done: i.done,
            position: n,
            revision: i.revision + 1,
          );
        }(),
    ];
  }

  @override
  Future<PreparationNote> saveNote(
    String eventId,
    String body,
    int expectedRevision,
  ) async {
    if (conflictOnSave) {
      conflictOnSave = false;
      note = const PreparationNote(body: 'Någon annans text', revision: 1);
      throw const PreparationConflict();
    }
    note = PreparationNote(body: body, revision: expectedRevision + 1);
    return note;
  }

  @override
  Future<List<String>> listSuggestions(String eventId, String kind) async =>
      suggestions;

  @override
  Future<void> uploadFile({
    required String eventId,
    required String fileId,
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required String visibility,
    List<String> personIds = const [],
  }) async {}

  @override
  Future<void> setFileVisibility({
    required String fileId,
    required String visibility,
    List<String> personIds = const [],
    required int expectedRevision,
  }) async {
    visibilityCalls.add((fileId, visibility, personIds));
    files = [
      for (final f in files)
        f.id == fileId
            ? EventFile(
                id: f.id,
                name: f.name,
                mimeType: f.mimeType,
                sizeBytes: f.sizeBytes,
                visibility: visibility,
                revision: f.revision + 1,
                createdAt: f.createdAt,
                viewerCount: personIds.length,
                viewerIds: personIds,
              )
            : f,
    ];
  }

  @override
  Future<void> deleteFile(String fileId) async {
    files = files.where((f) => f.id != fileId).toList();
  }

  @override
  Future<String> signedFileUrl(String fileId) async => 'https://example.test';

  @override
  Stream<void> watchEventLive(String eventId) => const Stream.empty();
}

/// An in-memory stand-in for the Match Space v2 commands: idempotent by
/// command id, score derived from active goals.
class _Match extends UnconfiguredMatchServices {
  String state = 'planning';
  bool workspace = false, failNext = false;
  int rosterRevision = 0, currentPeriod = 1, pausedSeconds = 0;
  List<int> periods = [45, 45];
  DateTime? startedAt, pausedAt;
  final facts = <Map<String, dynamic>>[];
  final commands = <(String, String, Object?)>[];
  final _seen = <String>{};
  int _factIds = 0;

  static const _roster = [
    ('erik', 'Erik Andersson'),
    ('johan', 'Johan Lind'),
    ('thomas', 'Thomas Emilson'),
  ];

  List<Map<String, dynamic>> get _active =>
      facts.where((f) => f['state'] == 'active').toList();
  int get scoreUs => _active
      .where((f) => f['fact_type'] == 'goal' && f['side'] == 'us')
      .length;
  int get scoreOpponent => _active
      .where((f) => f['fact_type'] == 'goal' && f['side'] == 'opponent')
      .length;

  void goLive({required int minutesAgo, int extraSeconds = 0}) {
    workspace = true;
    rosterRevision = 1;
    state = 'live';
    startedAt = DateTime.now().toUtc().subtract(
      Duration(minutes: minutesAgo, seconds: extraSeconds),
    );
  }

  void addGoal(String side, int minute, {String? scorer, String? assist}) =>
      facts.add({
        'id': 'fact-${_factIds++}',
        'fact_type': 'goal',
        'side': side,
        'minute': minute,
        'club_person_id': scorer,
        'secondary_club_person_id': assist,
        'state': 'active',
        'detail': <String, dynamic>{},
        'source_command_id': 'seed-$_factIds',
      });

  Future<void> _apply(
    String name,
    String key,
    Object? args,
    void Function() change,
  ) async {
    commands.add((name, key, args));
    if (failNext) {
      failNext = false;
      throw StateError('offline');
    }
    if (_seen.add(key)) change();
  }

  @override
  Future<MatchSnapshot?> getSnapshot(String eventId) async {
    if (!workspace) return null;
    return MatchSnapshot(
      eventId: eventId,
      state: state,
      revision: commands.length,
      rosterRevision: rosterRevision,
      scoreUs: scoreUs,
      scoreOpponent: scoreOpponent,
      cursor: '',
      clock: {
        'started_at': startedAt?.toIso8601String(),
        'paused_at': pausedAt?.toIso8601String(),
        'paused_seconds': pausedSeconds,
        'period_minutes': periods,
        'current_period': currentPeriod,
      },
      facts: [...facts],
      roster: [
        if (rosterRevision > 0)
          for (final (id, name) in _roster)
            MatchRosterMember(
              personId: id,
              name: name,
              sourceState: 'accepted',
            ),
      ],
      people: {for (final (id, name) in _roster) id: name},
      canManage: true,
    );
  }

  @override
  Future<void> freezeRoster(String id, String eventId, String reason) =>
      _apply('freeze', id, reason, () {
        workspace = true;
        rosterRevision++;
      });

  @override
  Future<void> transition(String id, String eventId, String action) =>
      _apply(action, id, null, () {
        switch (action) {
          case 'start':
            state = 'live';
            startedAt = DateTime.now().toUtc();
          case 'pause':
            pausedAt = DateTime.now().toUtc();
          case 'resume':
            pausedSeconds += DateTime.now()
                .toUtc()
                .difference(pausedAt!)
                .inSeconds;
            pausedAt = null;
        }
      });

  @override
  Future<void> transitionPeriod(String id, String eventId, String action) =>
      _apply('period_$action', id, null, () {
        if (action == 'end') {
          pausedAt = DateTime.now().toUtc();
          facts.add({
            'id': 'fact-${_factIds++}',
            'fact_type': 'period_end',
            'minute': periods.first,
            'state': 'active',
            'detail': {'period': currentPeriod},
          });
        } else {
          pausedAt = null;
          currentPeriod++;
        }
      });

  @override
  Future<void> recordGoal(
    String id,
    String eventId,
    String side,
    int minute, {
    String? scorerId,
    String? assistId,
  }) => _apply('goal', id, side, () {
    addGoal(side, minute, scorer: scorerId, assist: assistId);
    facts.last['source_command_id'] = id;
  });

  @override
  Future<void> voidEvent(String id, String factId) => _apply(
    'void',
    id,
    factId,
    () => facts.firstWhere((f) => f['id'] == factId)['state'] = 'voided',
  );

  @override
  Future<void> correctEvent(
    String id,
    String factId, {
    required int minute,
    String? scorerId,
    String? assistId,
    String? text,
  }) => _apply('correct', id, factId, () {
    final fact = facts.firstWhere((f) => f['id'] == factId);
    fact['minute'] = minute;
    fact['club_person_id'] = scorerId;
    fact['secondary_club_person_id'] = assistId;
  });

  @override
  Future<void> adjustClock(String id, String eventId, int elapsedSeconds) =>
      _apply('clock', id, elapsedSeconds, () {
        startedAt = DateTime.now().toUtc().subtract(
          Duration(seconds: elapsedSeconds + pausedSeconds),
        );
      });

  @override
  Future<void> configurePeriods(String id, String eventId, List<int> value) =>
      _apply('format', id, value, () {
        workspace = true;
        periods = value;
      });
}

class _Calendar extends UnconfiguredCalendarServices {
  _Calendar(this.type, this.prep);
  final String type;
  final _Prep prep;

  String get title => switch (type) {
    'match' => 'Match A',
    'meeting' => 'Möte A',
    _ => 'Träning A',
  };

  @override
  EventPreparationServices get preparation => prep;

  late final _event = EventDetails(
    id: 'event-1',
    title: title,
    description: null,
    type: type,
    state: 'scheduled',
    startsAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
    endsAt: DateTime.now().toUtc().add(const Duration(hours: 26)),
    allDay: false,
    timezone: 'Europe/Stockholm',
    revision: 1,
    callerActions: const {'revise', 'complete', 'manage_roster', 'match_live'},
    opponentName: 'Vetlanda',
    homeAway: 'home',
    teams: const [
      {'team_id': 'team', 'name': 'F2012', 'relation': 'primary'},
      {
        'team_id': 'shared-team',
        'name': 'F2011',
        'relation': 'shared',
        'capabilities': ['view'],
      },
    ],
    audiences: const [],
  );

  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async => [
    CalendarEventSummary(
      id: 'event-1',
      clubId: 'club',
      owningTeamId: 'team',
      teamName: 'F2012',
      title: title,
      type: type,
      state: 'scheduled',
      startsAt: _event.startsAt,
      endsAt: _event.endsAt,
      allDay: false,
      timezone: 'Europe/Stockholm',
      revision: 1,
    ),
  ];

  @override
  Future<EventDetails> getEventDetails(String eventId) async => _event;

  @override
  Future<SquadDetails> getEventSquad(String eventId) async => SquadDetails(
    eventId: eventId,
    state: 'sent',
    squadRevisionId: 'squad-1',
    revision: 1,
    members: const [],
    callups: const [],
    attendance: const [],
    roster: const [
      EventRosterPerson(
        personId: 'erik',
        name: 'Erik Andersson',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'player',
        inDraft: true,
        callupId: 'c1',
        callupState: 'accepted',
      ),
      EventRosterPerson(
        personId: 'johan',
        name: 'Johan Lind',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'player',
        inDraft: true,
        callupId: 'c2',
        callupState: 'accepted',
      ),
      EventRosterPerson(
        personId: 'thomas',
        name: 'Thomas Emilson',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'leader',
        inDraft: true,
        callupId: 'c3',
        callupState: 'accepted',
      ),
    ],
    callerActions: const {'save_squad', 'record_attendance'},
    selectionSource: 'manual',
    selectionContext: const {},
    dispatchKind: 'initial',
  );
}

class _Identity implements IdentityServices {
  const _Identity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'leader',
      capabilities: {'team.read', 'event.manage', 'club.memberships.manage'},
    ),
  ];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _SharedTeamIdentity extends _Identity {
  const _SharedTeamIdentity();
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'shared-context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'shared-team',
      teamName: 'F2011',
      rolePackage: 'leader',
      capabilities: {'event.manage'},
    ),
  ];
}
