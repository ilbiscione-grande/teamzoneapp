import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('priority surfaces share the async data contract', () {
    for (final path in [
      'lib/src/features/roster/roster_surface.dart',
      'lib/src/features/calendar/calendar_surface.dart',
      'lib/src/features/messaging/inbox_surface.dart',
      'lib/src/features/overview/overview_surface.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('AsyncDataController<'), reason: path);
      expect(source, contains('replaceScope('), reason: path);
      expect(source, contains('AsyncDataPhase.failed'), reason: path);
    }
  });

  test('calendar reports Realtime status and resyncs after reconnect', () {
    final service = File(
      'lib/src/features/calendar/calendar_services.dart',
    ).readAsStringSync();
    final surface = File(
      'lib/src/features/calendar/calendar_surface.dart',
    ).readAsStringSync();

    for (final status in [
      'RealtimeSubscribeStatus.subscribed',
      'RealtimeSubscribeStatus.channelError',
      'RealtimeSubscribeStatus.closed',
      'RealtimeSubscribeStatus.timedOut',
    ]) {
      expect(service, contains(status));
    }
    expect(surface, contains('resyncOnReconnect: true'));
    expect(surface, contains('AppConnectionStatus.reconnecting'));
    expect(surface, contains('AppConnectionStatus.offline'));
  });

  test('shared state never stores or exposes a backend error object', () {
    final source = File(
      'lib/src/shared/async/async_data_controller.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Object? error')));
    expect(source, isNot(contains('String error')));
    expect(source, contains('catch (_)'));
  });
}
