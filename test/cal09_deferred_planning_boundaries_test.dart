import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  EventDetails event({
    String type = 'training',
    Set<String> actions = const {},
  }) => EventDetails(
    id: 'event/with spaces',
    title: 'Event',
    description: null,
    type: type,
    state: 'scheduled',
    startsAt: DateTime.utc(2026, 8, 27, 17),
    endsAt: DateTime.utc(2026, 8, 27, 18),
    allDay: false,
    timezone: 'Europe/Stockholm',
    revision: 1,
    callerActions: actions,
    teams: const [],
    audiences: const [],
  );

  test('EventDetails exposes only implemented preparation actions', () {
    expect(event().preparationActions, isEmpty);
    expect(event(type: 'match').preparationActions, {
      EventPreparationAction.matchSpace,
    });
    expect(event(actions: {'manage_roster', 'revise'}).preparationActions, {
      EventPreparationAction.participants,
      EventPreparationAction.editEvent,
    });
  });

  test('calendar event route preserves opaque event identity', () {
    final location = ProductRouteContract.calendarEvent('event/with spaces');
    final uri = Uri.parse(location);
    expect(uri.path, ProductRouteContract.calendar);
    expect(uri.queryParameters['event'], 'event/with spaces');
    expect(ProductRouteContract.canonicalInitialLocation(location), location);
  });

  test('core calendar surface has no deferred planning affordances', () {
    final source = File(
      'lib/src/features/calendar/calendar_surface.dart',
    ).readAsStringSync();
    for (final deferredLabel in [
      'Importera event',
      'Lägg till anteckning',
      'Lägg till bilaga',
      'Öppna träningsworkspace',
    ]) {
      expect(source, isNot(contains(deferredLabel)));
    }
    expect(source, contains('event.preparationActions'));
  });
}
