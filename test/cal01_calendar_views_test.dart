import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

void main() {
  testWidgets('calendar requests only the active team context by default', (
    tester,
  ) async {
    final calendar = _RecordingCalendar();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'cal01-context'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _TwoTeamIdentity(),
          calendar: calendar,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();

    expect(calendar.requestedContextIds, ['context-a']);

    // Several teams can be shown together from the filter button.
    await tester.tap(find.byTooltip('Vy och filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'F2011'));
    await tester.pumpAndSettle();
    // Both teams picked means every team.
    expect(calendar.requestedContextIds, ['context-a', 'context-b']);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Alla lag'))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(FilterChip, 'F2011'));
    await tester.pumpAndSettle();
    expect(calendar.requestedContextIds, ['context-b']);
  });

  testWidgets('calendar exposes agenda, month, week and day on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Vy och filter'), findsOneWidget);
    Future<void> selectView(String label) async {
      await tester.tap(find.byTooltip('Vy och filter'));
      await tester.pumpAndSettle();
      for (final option in ['Agenda', 'Månad', 'Vecka', 'Dag']) {
        expect(find.text(option), findsWidgets);
      }
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    expect(find.text('Kvällsträning'), findsOneWidget);
    // Team/type filters live behind a compact filter button now, not two
    // full-width dropdowns.
    expect(find.byIcon(Icons.filter_list), findsOneWidget);
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'F2012'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Alla lag'));
    await tester.pumpAndSettle();
    expect(find.text('Alla eventtyper'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendarFilterClose')));
    await tester.pumpAndSettle();
    await selectView('Månad');
    // Today's cell shows an event-count badge instead of cropped titles...
    expect(find.text('4'), findsWidgets);
    // ...while the full list for the selected day scrolls independently
    // below the fixed month grid, so every event is reachable.
    expect(find.text('Kvällsträning'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Extraevent 3'),
      find.byKey(const Key('calendarSelectedDayPanel')),
      const Offset(0, -100),
    );
    expect(find.text('Extraevent 1'), findsOneWidget);
    expect(find.text('Extraevent 2'), findsOneWidget);
    expect(find.text('Extraevent 3'), findsOneWidget);
    // Planned events carry no status text; only the draft gets an icon.
    expect(find.text('Planerad'), findsNothing);
    expect(find.byKey(const Key('calendarDraftMarker')), findsOneWidget);
    // The Dag/Månad switch sits in the title row of the list under the grid.
    await tester.drag(
      find.byKey(const Key('calendarSelectedDayPanel')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('calendarMonthScopeToggle'));
    expect(
      find.descendant(
        of: find.byKey(const Key('calendarSelectedDayPanel')),
        matching: toggle,
      ),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: toggle, matching: find.text('Månad')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendarMonthEventsPanel')), findsOneWidget);
    await tester.tap(find.descendant(of: toggle, matching: find.text('Dag')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await selectView('Vecka');
    // The week grid shows the 7 selected-week days plus one extra "peek"
    // box for next week's first day (8 day cells total, each a Card), and
    // reuses the same fixed-grid/scrolling-day-panel layout as month view.
    expect(find.byType(Card), findsNWidgets(8));
    expect(find.byKey(const Key('calendarSelectedDayPanel')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await selectView('Dag');
    // Dag mode is a 24h timeline: hour gridlines with labels...
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
    // ...and events render as cards positioned on it.
    expect(find.text('Kvällsträning'), findsOneWidget);
    expect(find.text('Extraevent 1'), findsOneWidget);
    // Kvällsträning (18:00–19:30) and Extraevent 1 (19:00–20:00) overlap
    // for 30 minutes, so the column layout must place them side by side
    // instead of stacked on top of each other.
    final kvallstraningLeft = tester.getTopLeft(find.text('Kvällsträning')).dx;
    final extraevent1Left = tester.getTopLeft(find.text('Extraevent 1')).dx;
    expect(kvallstraningLeft, isNot(equals(extraevent1Left)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('archive filter swaps active events for retained history', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();

    expect(find.text('Kvällsträning'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visa arkiverade event'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendarFilterClose')));
    await tester.pumpAndSettle();

    expect(find.text('Arkiverade event'), findsOneWidget);
    expect(find.text('Arkiverad match'), findsOneWidget);
    expect(find.textContaining('Säsongen avslutad'), findsOneWidget);
    expect(find.text('Kvällsträning'), findsNothing);
  });

  test('all modes share team/type filters and local overlap logic', () {
    final date = DateTime(2026, 8, 27);
    final wanted = _event(
      id: 'wanted',
      teamId: 'team-a',
      type: 'training',
      startsAt: DateTime(2026, 8, 27, 18),
      endsAt: DateTime(2026, 8, 27, 19, 30),
    );
    final wrongTeam = _event(
      id: 'wrong-team',
      teamId: 'team-b',
      type: 'training',
      startsAt: DateTime(2026, 8, 27, 18),
      endsAt: DateTime(2026, 8, 27, 19),
    );
    final wrongType = _event(
      id: 'wrong-type',
      teamId: 'team-a',
      type: 'match',
      startsAt: DateTime(2026, 8, 27, 20),
      endsAt: DateTime(2026, 8, 27, 21),
    );
    for (final mode in CalendarViewMode.values) {
      final projection = CalendarProjection(
        events: [wrongTeam, wrongType, wanted],
        mode: mode,
        selectedDate: date,
        teamId: 'team-a',
        eventType: 'training',
      );
      expect(projection.visibleEvents.map((event) => event.id), ['wanted']);
    }
  });

  test('overnight, all-day and DST instants retain correct boundaries', () {
    final overnight = _event(
      id: 'overnight',
      startsAt: DateTime(2026, 10, 24, 23, 30),
      endsAt: DateTime(2026, 10, 25, 0, 30),
    );
    final allDay = _event(
      id: 'all-day',
      startsAt: DateTime(2026, 3, 29),
      endsAt: DateTime(2026, 3, 30),
      allDay: true,
    );
    final projection = CalendarProjection(
      events: [overnight, allDay],
      mode: CalendarViewMode.month,
      selectedDate: DateTime(2026, 10, 1),
    );
    expect(projection.eventsOn(DateTime(2026, 10, 24)), contains(overnight));
    expect(projection.eventsOn(DateTime(2026, 10, 25)), contains(overnight));
    final spring = CalendarProjection(
      events: [allDay],
      mode: CalendarViewMode.day,
      selectedDate: DateTime(2026, 3, 29),
    );
    expect(spring.visibleEvents, [allDay]);

    final dstStart = DateTime.parse('2026-03-29T01:30:00+01:00');
    final dstEnd = DateTime.parse('2026-03-29T03:30:00+02:00');
    expect(dstStart.isUtc, isTrue);
    expect(dstEnd.difference(dstStart), const Duration(hours: 1));
  });

  test('long calendar ranges are split within the backend limit', () {
    final from = DateTime.utc(2025, 1, 1);
    final to = DateTime.utc(2028, 1, 1);
    final windows = buildCalendarQueryWindows(
      from: from,
      to: to,
      maximumWindow: const Duration(days: 399),
    );

    expect(windows.length, 3);
    expect(windows.first.from, from);
    expect(windows.last.to, to);
    for (var index = 0; index < windows.length; index++) {
      expect(
        windows[index].to.difference(windows[index].from),
        lessThanOrEqualTo(const Duration(days: 399)),
      );
      if (index > 0) {
        expect(windows[index].from, windows[index - 1].to);
      }
    }
  });

  test('a month grid day from the neighbouring month keeps its events', () {
    final projection = CalendarProjection(
      events: [
        _event(
          id: 'next-month',
          startsAt: DateTime(2026, 11, 2, 18),
          endsAt: DateTime(2026, 11, 2, 19),
        ),
        _event(
          id: 'other-type',
          type: 'match',
          startsAt: DateTime(2026, 11, 2, 10),
          endsAt: DateTime(2026, 11, 2, 11),
        ),
      ],
      mode: CalendarViewMode.month,
      selectedDate: DateTime(2026, 10, 5),
      eventType: 'training',
    );
    // Outside October, so not in the month's own list...
    expect(projection.visibleEvents, isEmpty);
    // ...but still shown on the grid's trailing 2 November cell, filtered.
    expect(projection.eventsOn(DateTime(2026, 11, 2)).map((e) => e.id), [
      'next-month',
    ]);
  });

  testWidgets('swiping sideways changes period and reloads further away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calendar = _RecordingCalendar();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'cal01-swipe'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _Identity(),
          calendar: calendar,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Vy och filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Månad').last);
    await tester.pumpAndSettle();

    String title() => tester
        .widget<Text>(
          find.descendant(
            of: find.byTooltip('Välj datum'),
            matching: find.byType(Text),
          ),
        )
        .data!;
    final area = find.byKey(const Key('calendarSwipeArea'));
    final current = title();
    await tester.fling(area, const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    final next = title();
    expect(next, isNot(current));
    await tester.fling(area, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(title(), current);

    // The loaded window follows the selected month: two months back is
    // outside the initial window (from last month) and reloads around it.
    final now = DateTime.now();
    expect(calendar.requestedFrom.single, DateTime(now.year, now.month - 1));
    await tester.fling(area, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    await tester.fling(area, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(calendar.requestedFrom.last, DateTime(now.year, now.month - 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolling under the fixed calendar header keeps the app bar colour',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kalender'));
      await tester.pumpAndSettle();
      // Colour and elevation together: the scrolled-under state changes
      // either, depending on the theme.
      (Color?, double) appBarColor() {
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppBar).first,
                matching: find.byType(Material),
              )
              .first,
        );
        return (material.color, material.elevation);
      }

      // Unscrolled, before the day timeline opens at 15:00.
      final before = appBarColor();
      await tester.tap(find.byTooltip('Vy och filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dag').last);
      await tester.pumpAndSettle();
      expect(appBarColor(), before);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('calendarDayTimelineScroll'))),
      );
      await gesture.moveBy(const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(appBarColor(), before);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('day view opens at 15:00', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Vy och filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dag').last);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('calendarDayTimelineScroll')),
        matching: find.byType(Scrollable),
      ),
    );
    // 15:00 at the top, or as close as the end of the day allows on a
    // screen taller than 15:00–24:00.
    final position = scrollable.position;
    expect(position.pixels, min(15 * 64.0, position.maxScrollExtent));
    expect(position.pixels, greaterThan(14 * 64));
    expect(tester.takeException(), isNull);
  });
}

Widget _app() => TeamZoneApp(
  environment: const AppEnvironment(name: 'cal01'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: const _Identity(),
    calendar: _Calendar(),
    isConfigured: true,
  ),
);

CalendarEventSummary _event({
  required String id,
  String teamId = 'team-a',
  String type = 'training',
  required DateTime startsAt,
  required DateTime endsAt,
  bool allDay = false,
}) => CalendarEventSummary(
  id: id,
  clubId: 'club',
  owningTeamId: teamId,
  teamName: teamId == 'team-a' ? 'F2012' : 'F2011',
  title: id,
  type: type,
  state: 'scheduled',
  startsAt: startsAt,
  endsAt: endsAt,
  allDay: allDay,
  timezone: 'Europe/Stockholm',
  revision: 1,
);

class _Calendar extends UnconfiguredCalendarServices {
  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async {
    final now = DateTime.now();
    return [
      CalendarEventSummary(
        id: 'event',
        clubId: 'club',
        owningTeamId: 'team-a',
        teamName: 'F2012',
        title: 'Kvällsträning',
        type: 'training',
        state: 'scheduled',
        startsAt: DateTime(now.year, now.month, now.day, 18),
        endsAt: DateTime(now.year, now.month, now.day, 19, 30),
        allDay: false,
        timezone: 'Europe/Stockholm',
        revision: 1,
      ),
      for (var index = 1; index <= 3; index++)
        CalendarEventSummary(
          id: 'event-$index',
          clubId: 'club',
          owningTeamId: 'team-a',
          teamName: 'F2012',
          title: 'Extraevent $index',
          type: 'training',
          state: index == 3 ? 'draft' : 'scheduled',
          // Extraevent 1 (19:00–20:00) deliberately overlaps Kvällsträning
          // (18:00–19:30) for 30 minutes, to exercise the day timeline's
          // side-by-side overlap layout.
          startsAt: DateTime(now.year, now.month, now.day, 18 + index),
          endsAt: DateTime(now.year, now.month, now.day, 19 + index),
          allDay: false,
          timezone: 'Europe/Stockholm',
          revision: 1,
        ),
    ];
  }

  @override
  Future<List<CalendarEventSummary>> listArchivedEvents({
    required List<String> contextIds,
  }) async {
    final now = DateTime.now();
    return [
      CalendarEventSummary(
        id: 'archived-event',
        clubId: 'club',
        owningTeamId: 'team-a',
        teamName: 'F2012',
        title: 'Arkiverad match',
        type: 'match',
        state: 'completed',
        startsAt: DateTime(now.year, now.month - 1, 1, 18),
        endsAt: DateTime(now.year, now.month - 1, 1, 20),
        allDay: false,
        timezone: 'Europe/Stockholm',
        revision: 3,
        archivedAt: DateTime(now.year, now.month, 1),
        archiveReason: 'Säsongen avslutad',
      ),
    ];
  }
}

class _RecordingCalendar extends UnconfiguredCalendarServices {
  List<String> requestedContextIds = const [];
  final List<DateTime> requestedFrom = [];

  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async {
    requestedContextIds = List.of(contextIds);
    requestedFrom.add(from);
    return const [];
  }
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
      teamId: 'team-a',
      teamName: 'F2012',
      rolePackage: 'player',
      capabilities: {'team.read'},
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

class _TwoTeamIdentity extends _Identity {
  const _TwoTeamIdentity();

  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context-a',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team-a',
      teamName: 'F2012',
      rolePackage: 'player',
      capabilities: {'team.read'},
    ),
    TeamZoneContext(
      id: 'context-b',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team-b',
      teamName: 'F2011',
      rolePackage: 'player',
      capabilities: {'team.read'},
    ),
  ];
}
