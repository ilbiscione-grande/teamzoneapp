import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EventDetails uses the four approved full tab names', () {
    final source = File(
      'lib/src/features/calendar/calendar_surface.dart',
    ).readAsStringSync();

    expect(source, contains("Tab(text: strings.feature('Info'))"));
    expect(source, contains("Tab(text: strings.feature('Deltagare'))"));
    expect(source, contains("Tab(text: strings.feature('Förberedelser'))"));
    expect(source, contains("Tab(text: strings.feature('Uppföljning'))"));
    expect(source, contains('isScrollable: true'));
    expect(source, contains('MediaQuery.sizeOf(context).width >= 720'));
    expect(source, contains('_eventDateTimeLabel(context, event)'));
    expect(source, contains('localizations.formatFullDate(start)'));
    expect(source, contains('TimeOfDay.fromDateTime(start).format(context)'));
    expect(source, contains('strings.eventOwner(name)'));
    expect(source, contains('strings.callupSummary'));
    expect(source, contains('strings.preparationTitle(event.type)'));
    expect(source, isNot(contains("'\${widget.event.startsAt.toLocal()} –")));
  });

  test('participant and role-specific actions stay capability driven', () {
    final source = File(
      'lib/src/features/calendar/calendar_surface.dart',
    ).readAsStringSync();

    expect(source, contains("event.can('manage_roster')"));
    expect(source, contains("event.can('manage_sharing')"));
    expect(source, contains("event.can('revise')"));
    expect(source, contains("feature('Urval')"));
    expect(source, contains("'Kallelser och svar'"));
    expect(source, contains("feature('Närvaro')"));
    expect(source, contains("event.type == 'match'"));
  });
}
