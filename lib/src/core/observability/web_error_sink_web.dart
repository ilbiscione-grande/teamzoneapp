import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Fire-and-forget: a beacon survives page unload and, sent as text/plain,
/// needs no CORS preflight.
bool sendWebErrorRecord(String url, String body) =>
    web.window.navigator.sendBeacon(url, body.toJS);
