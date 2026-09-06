import 'dart:async';

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
    for (final label in ['Agenda', 'Månad', 'Vecka', 'Dag']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Kvällsträning'), findsOneWidget);
    // Team/type filters live behind a compact filter button now, not two
    // full-width dropdowns.
    expect(find.byIcon(Icons.filter_list), findsOneWidget);
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    expect(find.text('Alla lag'), findsOneWidget);
    expect(find.text('Alla eventtyper'), findsOneWidget);
    await tester.tap(find.text('Klar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Månad'));
    await tester.pumpAndSettle();
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
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Vecka'));
    await tester.pumpAndSettle();
    // The week grid shows the 7 selected-week days plus one extra "peek"
    // box for next week's first day (8 day cells total, each a Card), and
    // reuses the same fixed-grid/scrolling-day-panel layout as month view.
    expect(find.byType(Card), findsNWidgets(8));
    expect(find.byKey(const Key('calendarSelectedDayPanel')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Dag'));
    await tester.pumpAndSettle();
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
          state: 'scheduled',
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
