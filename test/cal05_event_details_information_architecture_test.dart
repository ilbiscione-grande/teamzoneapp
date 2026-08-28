import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EventDetails uses the four approved full tab names', () {
    final source = File(
      'lib/src/features/calendar/calendar_surface.dart',
    ).readAsStringSync();

    expect(source, contains("Tab(text: 'Info')"));
    expect(source, contains("Tab(text: 'Deltagare')"));
    expect(source, contains("Tab(text: 'Förberedelser')"));
    expect(source, contains("Tab(text: 'Uppföljning')"));
    expect(source, contains('isScrollable: true'));
    expect(source, contains('MediaQuery.sizeOf(context).width >= 720'));
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
