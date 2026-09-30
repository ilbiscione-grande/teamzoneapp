import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EventDetails uses the four approved full tab names', () {
    // EventDetails moved from a dialog/bottom-sheet panel inside
    // calendar_surface.dart to its own page (CAL-11) — the tab structure
    // this test protects now lives in event_details_page.dart.
    final source = File(
      'lib/src/features/calendar/event_details_page.dart',
    ).readAsStringSync();

    expect(source, contains("Tab(text: strings.feature('Info'))"));
    expect(source, contains("Tab(text: strings.feature('Deltagare'))"));
    expect(source, contains("Tab(text: strings.feature('Förberedelser'))"));
    expect(source, contains("Tab(text: strings.feature('Uppföljning'))"));
    expect(source, contains('isScrollable: true'));
    expect(source, contains('_eventDateTimeLabel(context, event)'));
    expect(source, contains('localizations.formatFullDate(start)'));
    expect(source, contains('localizations.formatTimeOfDay('));
    expect(source, contains("strings.feature('Ägande lag')"));
    // Förberedelser v1 replaced the old placeholder text with a real
    // per-event workspace (event_preparation.dart).
    expect(source, contains('_PreparationTab('));
    expect(source, isNot(contains("'\${widget.event.startsAt.toLocal()} –")));
  });

  test('participant and role-specific actions stay capability driven', () {
    final source = File(
      'lib/src/features/calendar/event_details_page.dart',
    ).readAsStringSync();

    expect(source, contains("event.can('manage_roster')"));
    expect(source, contains("event.can('manage_sharing')"));
    expect(source, contains("event.can('revise')"));
    expect(source, contains('_ParticipantsTab('));

    // The Deltagare tab lives in its own file. Its compact list splits
    // players from leaders (callup state is shown per row), and selecting
    // and recording attendance stay gated by the squad's capabilities.
    final participants = File(
      'lib/src/features/calendar/event_participants.dart',
    ).readAsStringSync();
    expect(participants, contains("_s.feature('Spelare').toUpperCase()"));
    expect(participants, contains("_s.feature('Ledare').toUpperCase()"));
    expect(participants, contains("p.rolePackage == 'player'"));
    expect(participants, contains("widget.squad.can('save_squad')"));
    expect(participants, contains("widget.squad.can('record_attendance')"));
    expect(participants, contains("widget.squad.can('send_callups')"));
  });

  test('web allows mouse dragging of the horizontally scrollable tab row', () {
    final appSource = File('lib/src/app/teamzone_app.dart').readAsStringSync();

    expect(
      appSource,
      contains('scrollBehavior: const _TeamZoneScrollBehavior()'),
    );
    expect(appSource, contains('PointerDeviceKind.mouse'));
    expect(appSource, contains('PointerDeviceKind.touch'));
    expect(appSource, contains('PointerDeviceKind.trackpad'));
  });
}
