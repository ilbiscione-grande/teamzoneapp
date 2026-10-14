import 'package:flutter/services.dart';

/// Texts for an answerable callup notification, in the recipient's language.
class CallupNotificationTexts {
  const CallupNotificationTexts({
    required this.accept,
    required this.decline,
    required this.sent,
    required this.gone,
    required this.failed,
    required this.locked,
  });

  final String accept, decline, sent, gone, failed, locked;
}

/// TeamZone's Android notifications (the plugin in android/): plain ones and
/// callups with "Kommer" (answered in the notification after unlock) and
/// "Kan inte…" (opens the event). Works from the FCM background handler.
abstract final class TeamzoneNotifications {
  static const _methods = MethodChannel('teamzone/notifications');
  static const _opened = EventChannel('teamzone/notifications/opened');

  static Future<void> createChannel({
    required String name,
    required String description,
  }) => _methods.invokeMethod<void>('createChannel', {
    'name': name,
    'description': description,
  });

  static Future<void> showPlain({
    required int id,
    required String title,
    required String body,
    required String route,
  }) => _methods.invokeMethod<void>('showPlain', {
    'id': id,
    'title': title,
    'body': body,
    'route': route,
  });

  /// [endpoint] is push-callup-response; [token] the single-use response
  /// token and [idempotencyKey] the key reused if the answer is retried.
  static Future<void> showCallup({
    required int id,
    required String title,
    required String body,
    required String route,
    required String declineRoute,
    required String token,
    required String idempotencyKey,
    required String endpoint,
    required String apiKey,
    required CallupNotificationTexts texts,
  }) => _methods.invokeMethod<void>('showCallup', {
    'id': id,
    'title': title,
    'body': body,
    'route': route,
    'declineRoute': declineRoute,
    'token': token,
    'idempotencyKey': idempotencyKey,
    'endpoint': endpoint,
    'apiKey': apiKey,
    'acceptLabel': texts.accept,
    'declineLabel': texts.decline,
    'sentTitle': texts.sent,
    'goneTitle': texts.gone,
    'failedTitle': texts.failed,
    'lockedTitle': texts.locked,
  });

  /// The route of the notification that started the app, once.
  static Future<String?> takeLaunchRoute() =>
      _methods.invokeMethod<String>('takeLaunchRoute');

  /// Routes of notifications tapped while the app runs.
  static Stream<String> get openedRoutes =>
      _opened.receiveBroadcastStream().where((value) => value is String).cast();
}
