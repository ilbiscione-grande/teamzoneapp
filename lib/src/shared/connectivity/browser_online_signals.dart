import 'dart:async';

import 'browser_online_signals_stub.dart'
    if (dart.library.html) 'browser_online_signals_web.dart'
    as platform;

Stream<void> browserOnlineSignals() => platform.browserOnlineSignals();

bool browserIsOnline() => platform.browserIsOnline();

Stream<bool> browserConnectionChanges() => platform.browserConnectionChanges();
