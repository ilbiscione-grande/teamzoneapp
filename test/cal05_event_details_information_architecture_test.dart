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
    expect(source, contains('strings.eventOwner(name)'));
    expect(source, contains('strings.preparationTitle(event.type)'));
    expect(source, isNot(contains("'\${widget.event.startsAt.toLocal()} –")));
  });

  test('participant and role-specific actions stay capability driven', () {
    final source = File(
      'lib/src/features/calendar/event_details_page.dart',
    ).readAsStringSync();

    expect(source, contains("event.can('manage_roster')"));
    expect(source, contains("event.can('manage_sharing')"));
    expect(source, contains("event.can('revise')"));
    // The old "Urval"/"Kallelser och svar"/"Närvaro" summary + a single
    // "Hantera urval" button was replaced by an inline, always-visible
    // status header and roster list (per request) — the fixed four-bucket
    // sort order (called players/leaders, then uncalled) is the current
    // structural contract to protect instead.
    expect(source, contains("strings.feature('Kallade spelare')"));
    expect(source, contains("strings.feature('Kallade ledare')"));
    expect(source, contains("strings.feature('Okallade spelare')"));
    expect(source, contains("strings.feature('Okallade ledare')"));
    expect(source, contains("widget.squad.can('save_squad')"));
    expect(source, contains("widget.squad.can('record_attendance')"));
  });
}
