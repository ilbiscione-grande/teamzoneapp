import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_task_preferences.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_tasks.dart';
import 'assistant_context_tasks_test.dart' as fixtures;
import 'assistant_personal_conflicts_test.dart' as personal;
import 'package:teamzone_app/src/features/overview/overview_services.dart';

class Preferences extends fixtures.Overview
    implements AssistantTaskPreferencesServices {
  AssistantTaskPreferences value = const AssistantTaskPreferences();
  bool failRead = false, failSave = false;
  @override
  Future<AssistantTaskPreferences> loadAssistantTaskPreferences() async {
    if (failRead) throw StateError('offline');
    return value;
  }

  @override
  Future<AssistantTaskPreferences> saveAssistantTaskPreferences(
    Set<String> hiddenKinds,
    int expectedRevision, {
    bool currentTeamOnly = false,
    bool welcomeMessageVisible = true,
  }) async {
    if (failSave) throw StateError('offline');
    expect(expectedRevision, value.revision);
    return value = AssistantTaskPreferences(
      hiddenKinds: hiddenKinds,
      currentTeamOnly: currentTeamOnly,
      welcomeMessageVisible: welcomeMessageVisible,
      revision: expectedRevision + 1,
    );
  }
}

class ScopedPersonal extends Preferences
    implements PersonalCalendarConflictServices {
  @override
  Future<Map<String, dynamic>> loadPersonalCalendarConflicts() =>
      personal.PersonalOverview().loadPersonalCalendarConflicts();
}

void main() {
  test(
    'current team scope filters teams before reads and follows either side of personal conflicts',
    () async {
      final service = ScopedPersonal()
        ..value = const AssistantTaskPreferences(currentTeamOnly: true)
        ..homes['a'] = fixtures.home([fixtures.task('one')])
        ..homes['b'] = fixtures.home([fixtures.task('two')]);
      final contexts = [
        fixtures.team('a'),
        fixtures.team('b'),
        fixtures.team('c'),
      ];
      for (final active in contexts) {
        service.calls.clear();
        final result = await loadAssistantTasks(
          contexts: contexts,
          activeContext: active,
          overview: service,
          loadEvent: fixtures.event,
        );
        expect(service.calls, [active.id]);
        expect(result.currentTeamOnly, true);
        expect(
          result.tasks.where((t) => t.isPersonalConflict).length,
          active.id == 'c' ? 0 : 1,
        );
        expect(
          result.tasks
              .where((t) => !t.isPersonalConflict)
              .every((t) => t.context.id == active.id),
          true,
        );
      }
      final noTeam = await loadAssistantTasks(
        contexts: contexts,
        overview: service,
        loadEvent: fixtures.event,
      );
      expect(noTeam.tasks, isEmpty);
    },
  );

  testWidgets(
    'categories filter one list and remain usable in a narrow panel',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = Preferences()
        ..homes['a'] = fixtures.home([
          fixtures.task('one'),
          fixtures.task('two', kind: 'unfinished_preparation'),
        ]);
      final team = fixtures.team(
        'a',
        caps: {'event.squad.manage', 'event.logistics'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssistantTaskSections(
                contexts: [team],
                activeContext: team,
                page: const AssistantPageContext('/home'),
                overview: service,
                loadEvent: fixtures.event,
                onOpen: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alla (2)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assistant-category-matches')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('assistant-category-preparation')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Träning one'), findsNothing);
      expect(find.text('Träning two'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assistant-category-all')));
      await tester.pumpAndSettle();
      expect(find.text('Träning one'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'hidden task types are excluded before metadata and failed settings stay explicit',
    () async {
      final service = Preferences()
        ..homes['a'] = fixtures.home([fixtures.task('one')]);
      service.value = const AssistantTaskPreferences(
        hiddenKinds: {'pending_callups'},
      );
      var reads = 0;
      final snapshot = await loadAssistantTasks(
        contexts: [fixtures.team('a')],
        overview: service,
        loadEvent: (id) {
          reads++;
          return fixtures.event(id);
        },
      );
      expect(snapshot.tasks, isEmpty);
      expect(snapshot.filtersActive, isTrue);
      expect(reads, 0);
      service.failRead = true;
      final failed = await loadAssistantTasks(
        contexts: [fixtures.team('a')],
        overview: service,
        loadEvent: fixtures.event,
      );
      expect(failed.settingsFailed, isTrue);
    },
  );

  testWidgets(
    'failed save retains selection for retry and persists only on success',
    (tester) async {
      final service = Preferences()..failSave = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssistantTaskVisibilitySettings(services: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aktuellt lag'));
      await tester.ensureVisible(
        find.byKey(
          const ValueKey('assistant-visible-personal_calendar_conflict'),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey('assistant-visible-personal_calendar_conflict'),
        ),
      );
      await tester.ensureVisible(find.text('Spara visningsinställningar'));
      await tester.tap(find.text('Spara visningsinställningar'));
      await tester.pumpAndSettle();
      expect(service.value.hiddenKinds, isEmpty);
      expect(find.textContaining('Kunde inte spara.'), findsOneWidget);
      service.failSave = false;
      await tester.tap(find.text('Spara visningsinställningar'));
      await tester.pumpAndSettle();
      expect(service.value.hiddenKinds, {'personal_calendar_conflict'});
      expect(service.value.currentTeamOnly, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'welcome message dismissal persists and settings can restore it',
    (tester) async {
      final service = Preferences()..homes['a'] = fixtures.home([]);
      final context = fixtures.team('a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssistantTaskSections(
                contexts: [context],
                activeContext: context,
                page: const AssistantPageContext('/home'),
                overview: service,
                loadEvent: fixtures.event,
                onOpen: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('assistant-welcome-message')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('assistant-dismiss-welcome')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant-welcome-message')), findsNothing);
      expect(service.value.welcomeMessageVisible, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssistantTaskVisibilitySettings(services: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final setting = find.byKey(
        const Key('assistant-welcome-message-setting'),
      );
      expect(tester.widget<SwitchListTile>(setting).value, isFalse);
      await tester.tap(setting);
      await tester.ensureVisible(find.text('Spara visningsinställningar'));
      await tester.tap(find.text('Spara visningsinställningar'));
      await tester.pumpAndSettle();
      expect(service.value.welcomeMessageVisible, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssistantTaskSections(
                contexts: [context],
                activeContext: context,
                page: const AssistantPageContext('/home'),
                overview: service,
                loadEvent: fixtures.event,
                onOpen: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('assistant-welcome-message')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
