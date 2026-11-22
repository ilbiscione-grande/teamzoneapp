/// The device's own share sheet: Android's chooser in the app, the
/// browser's share (Web Share) on the web. [shareText] returns false when
/// there is no share sheet, so the caller can copy the text instead.
library;

export 'system_share_stub.dart'
    if (dart.library.js_interop) 'system_share_web.dart';
