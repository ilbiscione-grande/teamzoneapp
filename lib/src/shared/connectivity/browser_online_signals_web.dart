import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool browserIsOnline() => web.window.navigator.onLine;

Stream<bool> browserConnectionChanges() {
  late final StreamController<bool> controller;
  final web.EventListener onOnline = ((web.Event _) {
    if (!controller.isClosed) controller.add(true);
  }).toJS;
  final web.EventListener onOffline = ((web.Event _) {
    if (!controller.isClosed) controller.add(false);
  }).toJS;
  controller = StreamController<bool>(
    onListen: () {
      web.window.addEventListener('online', onOnline);
      web.window.addEventListener('offline', onOffline);
    },
    onCancel: () {
      web.window.removeEventListener('online', onOnline);
      web.window.removeEventListener('offline', onOffline);
    },
  );
  return controller.stream;
}

Stream<void> browserOnlineSignals() =>
    browserConnectionChanges().where((isOnline) => isOnline).map((_) {});
