import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('teamzone/share');

/// Whether this device has a share sheet the app can open.
bool get canShareText => defaultTargetPlatform == TargetPlatform.android;

/// Opens Android's share sheet with [text]; MainActivity answers the call.
Future<bool> shareText(String text, {String? subject}) async {
  if (!canShareText) return false;
  try {
    return await _channel.invokeMethod<bool>('shareText', {
          'text': text,
          'subject': ?subject,
        }) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
