import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_task_feedback.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_task_preferences.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_tasks.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';

// Min assistent, decided 2026-10-15: "Inte till hjälp" with fixed reasons,
// the support switch view, and "Påminn…" with review over the card.

TeamZoneContext _team() => const TeamZoneContext(
  id: 'a',
  clubId: 'club-a',
  clubName: 'Klubb a',
  teamId: 'team-a',
  teamName: 'Lag a',
  rolePackage: 'leader',
  capabilities: {'event.squad.manage', 'event.attendance.manage'},
);

LeaderHomeProjection _home(List<LeaderHomeTask> tasks) => LeaderHomeProjection(
  generatedAt: DateTime(2026, 10, 2, 12),
  todayEvents: const [],
  tasks: tasks,
  planningActions: const [],
  isStale: false,
);

LeaderHomeTask _task(String kind, {String status = 'active'}) => LeaderHomeTask(
  kind: kind,
  title: kind == 'pending_callups' ? 'Obesvarade kallelser' : 'Närvaro saknas',
  count: 2,
  route: '/calendar?event=one',
  priority: 1,
  assistantStatus: status,
);

Future<EventDetails> _event(String id) async => EventDetails(
  id: id,
  callupsRequired: true,
  title: 'Träning $id',
  description: null,
  type: 'training',
  state: 'scheduled',
  startsAt: DateTime(2026, 10, 3, 18),
  endsAt: DateTime(2026, 10, 3, 19),
  allDay: false,
  timezone: 'Europe/Stockholm',
  revision: 1,
  callerActions: const {'manage_roster'},
  teams: const [],
  audiences: const [],
);

class _Overview extends UnconfiguredOverviewServices
    implements
        AssistantTaskStateServices,
        AssistantTaskFeedbackServices,
        AssistantTaskPreferencesServices {
  _Overview(this.kind);
  final String kind;
  String status = 'active';
  final feedback = <String>[];
  bool offerHide = false;
  Set<String> hidden = {};

  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async =>
      _home([if (!hidden.contains(kind)) _task(kind, status: status)]);

  @override
  Future<void> setAssistantTaskState({
    required String contextId,
    required String kind,
    required String route,
    required String status,
    int? snoozeMinutes,
  }) async => this.status = status;

  @override
  Future<bool> giveAssistantTaskFeedback({
    required String contextId,
    required String kind,
    required String route,
    required String reason,
  }) async {
    feedback.add(reason);
    status = 'archived';
    return offerHide;
  }

  @override
  Future<AssistantTaskPreferences> loadAssistantTaskPreferences() async =>
      AssistantTaskPreferences(hiddenKinds: hidden, revision: 3);

  @override
  Future<AssistantTaskPreferences> saveAssistantTaskPreferences(
    Set<String> hiddenKinds,
    int expectedRevision, {
    bool currentTeamOnly = false,
    bool welcomeMessageVisible = true,
  }) async {
    hidden = hiddenKinds;
    return AssistantTaskPreferences(hiddenKinds: hidden, revision: 4);
  }
}

class _Calendar extends UnconfiguredCalendarServices {
  final reminded = <String>[];
  DateTime? lastReminded;

  @override
  Future<SquadDetails> getEventSquad(String eventId) async => SquadDetails(
    eventId: eventId,
    state: 'locked',
    members: const [],
    roster: const [],
    attendance: const [],
    callerActions: const {'remind_callup'},
    selectionSource: 'manual',
    selectionContext: const {},
    dispatchKind: 'initial',
    callups: [
      CallupView(
        id: 'c1',
        personId: 'p1',
        name: 'Ada Andersson',
        state: 'pending',
        deliveryState: 'sent',
        revision: 2,
        canRespond: false,
        reminderCount: 0,
      ),
      CallupView(
        id: 'c2',
        personId: 'p2',
        name: 'Bo Berg',
        state: 'pending',
        deliveryState: 'sent',
        revision: 1,
        canRespond: false,
        reminderCount: 1,
        lastRemindedAt: lastReminded,
      ),
      const CallupView(
        id: 'c3',
        personId: 'p3',
        name: 'Cia Carlsson',
        state: 'accepted',
        deliveryState: 'sent',
        revision: 3,
        canRespond: false,
        reminderCount: 0,
      ),
    ],
  );

  @override
  Future<void> manageCallup({
    required String callupId,
    required String action,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => reminded.add('$callupId:$action:$expectedRevision');
}

Widget _app(
  _Overview overview, {
  CalendarServices? calendar,
  List<AssistantTask>? opened,
}) => MaterialApp(
  locale: const Locale('sv'),
  supportedLocales: const [Locale('sv')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: SingleChildScrollView(
      child: AssistantTaskSections(
        contexts: [_team()],
        activeContext: _team(),
        page: const AssistantPageContext('/home'),
        overview: overview,
        loadEvent: _event,
        calendar: calendar,
        onOpen: (task) async => opened?.add(task),
      ),
    ),
  ),
);

void main() {
  testWidgets('"Inte till hjälp" archives the card with a fixed reason', (
    tester,
  ) async {
    final overview = _Overview('missing_attendance');
    await tester.pumpWidget(_app(overview));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inte till hjälp'));
    await tester.pumpAndSettle();
    // Exactly the four reasons, no free text.
    for (final label in assistantFeedbackReasons.values) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Redan hanterat'));
    await tester.pumpAndSettle();
    expect(overview.feedback, ['already_handled']);
    expect(find.text('Träning one'), findsNothing);
    expect(find.textContaining('Kortet är arkiverat'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Visas för ofta" can lead to hiding the type', (tester) async {
    final overview = _Overview('missing_attendance')..offerHide = true;
    await tester.pumpWidget(_app(overview));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Träning one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inte till hjälp'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Visas för ofta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visas för ofta'));
    await tester.pumpAndSettle();
    expect(find.text('Dölja den här typen?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assistant-hide-kind')));
    await tester.pumpAndSettle();
    expect(overview.hidden, {'missing_attendance'});
    expect(find.textContaining('Typen är dold'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Påminn…" reviews recipients over the card before sending', (
    tester,
  ) async {
    final overview = _Overview('pending_callups');
    final calendar = _Calendar()
      ..lastReminded = DateTime.now().subtract(const Duration(hours: 2));
    final opened = <AssistantTask>[];
    await tester.pumpWidget(_app(overview, calendar: calendar, opened: opened));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Påminn…'));
    await tester.pumpAndSettle();
    // Only pending callups past the six-hour wait; nothing sent yet.
    expect(find.text('Granska påminnelser'), findsOneWidget);
    expect(find.text('Ada Andersson'), findsOneWidget);
    expect(find.text('Bo Berg'), findsNothing);
    expect(find.text('Cia Carlsson'), findsNothing);
    expect(calendar.reminded, isEmpty);
    await tester.tap(find.text('Skicka 1 påminnelser'));
    await tester.pumpAndSettle();
    expect(calendar.reminded, ['c1:remind:2']);
    expect(find.text('Påminnelsen är skickad.'), findsOneWidget);
    expect(opened, isEmpty, reason: 'the card does not navigate away');
    // The event itself is still one tap away.
    await tester.tap(find.text('Träning one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Öppna aktiviteten'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling the review sends nothing', (tester) async {
    final overview = _Overview('pending_callups');
    final calendar = _Calendar();
    await tester.pumpWidget(_app(overview, calendar: calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Påminn…'));
    await tester.pumpAndSettle();
    expect(find.text('Skicka 2 påminnelser'), findsOneWidget);
    await tester.tap(find.text('Avbryt'));
    await tester.pumpAndSettle();
    expect(calendar.reminded, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without the calendar the card still navigates', (tester) async {
    final overview = _Overview('pending_callups');
    final opened = <AssistantTask>[];
    await tester.pumpWidget(_app(overview, opened: opened));
    await tester.pumpAndSettle();
    expect(find.text('Påminn…'), findsNothing);
    await tester.tap(find.text('Åtgärda'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('support switches a type off with a reason', (tester) async {
    final support = _Support();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        supportedLocales: const [Locale('sv')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: AssistantTaskKindSwitches(services: support)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Stämmer inte 3'), findsOneWidget);
    expect(find.textContaining('(2 personer)'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('assistant-switch-missing_attendance')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stäng av för alla användare?'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Stäng av');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('assistant-switch-reason')),
      'Regeln visar fel',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(support.changes, ['missing_attendance:true:Regeln visar fel']);
    expect(find.textContaining('Avstängd: Regeln visar fel'), findsOneWidget);
  });
}

class _Support implements AssistantTaskSupportServices {
  final changes = <String>[];
  bool off = false;

  @override
  Future<List<AssistantTaskKindStatus>> listAssistantTaskKinds() async => [
    AssistantTaskKindStatus(
      kind: 'missing_attendance',
      disabled: off,
      reason: off ? 'Regeln visar fel' : null,
      feedback: const {'incorrect': 3, 'too_often': 1},
      feedbackPeople: 2,
    ),
    const AssistantTaskKindStatus(kind: 'pending_callups', disabled: false),
  ];

  @override
  Future<void> setAssistantTaskKindSwitch({
    required String kind,
    required bool disabled,
    required String reason,
  }) async {
    changes.add('$kind:$disabled:$reason');
    off = disabled;
  }
}
