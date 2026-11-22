import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web Share is there on phones and most tablets, seldom on a desktop.
bool get canShareText {
  try {
    return web.window.navigator.canShare(web.ShareData(text: 'x'));
  } catch (_) {
    return false;
  }
}

/// The browser's share sheet. False when there is none or it failed; true
/// also when the person closed the sheet without choosing.
Future<bool> shareText(String text, {String? subject}) async {
  if (!canShareText) return false;
  try {
    await web.window.navigator
        .share(web.ShareData(text: text, title: subject ?? ''))
        .toDart;
    return true;
  } catch (error) {
    // AbortError: the person closed the sheet.
    return error.toString().contains('AbortError');
  }
}
