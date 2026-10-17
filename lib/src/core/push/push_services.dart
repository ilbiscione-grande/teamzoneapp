import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_notifications/teamzone_notifications.dart';

enum PushPermission { granted, denied, notDetermined }

/// Push notifications through Firebase Cloud Messaging (decided 2026-10-13).
/// The lock screen shows type + activity only (built by the server); the
/// app asks for permission when there is first something to be notified
/// about, and a tap opens the event or thread.
abstract interface class PushServices {
  /// Android, and iOS once its Firebase options exist; never web.
  bool get supported;
  Future<PushPermission> permission();

  /// Asks the operating system and registers the device when allowed.
  Future<bool> requestAndRegister();

  /// Keeps the registration fresh when permission was given earlier.
  Future<void> registerIfAllowed();

  /// Before signing out: this device stops receiving the account's pushes.
  Future<void> unregister();

  /// In-app routes of tapped notifications, while the app runs.
  Stream<String> get openedRoutes;

  /// The route of the notification that started the app, once.
  Future<String?> initialRoute();

  /// Whether the permission explanation has been shown on this device.
  Future<bool> wasOffered();
  Future<void> markOffered();
}

/// Only the app's own event and thread routes are followed. "Kan inte…" on
/// a callup notification opens the event's participants with the decline
/// for that callup.
abstract final class PushRoutes {
  static final _safe = RegExp(
    r'^/(calendar/event/[0-9a-fA-F-]{36}(\?tab=participants&decline=[0-9a-fA-F-]{36})?|inbox(\?(thread|pool|poolad)=[0-9a-fA-F-]{36})?)$',
  );

  static String? safe(Object? route) =>
      route is String && _safe.hasMatch(route) ? route : null;

  static String decline(String eventRoute, String callupId) =>
      '$eventRoute?tab=participants&decline=$callupId';
}

/// An answerable callup push (a data message, see notification-worker):
/// the app draws it with "Kommer" and "Kan inte…". Null for anything else.
class CallupPush {
  const CallupPush._({
    required this.title,
    required this.body,
    required this.route,
    required this.callupId,
    required this.token,
    required this.english,
  });

  static final _callupId = RegExp(r'^[0-9a-fA-F-]{36}$');
  static final _token = RegExp(r'^[0-9a-f]{64}$');

  static CallupPush? parse(Map<String, dynamic> data) {
    final route = PushRoutes.safe(data['route']);
    final callupId = data['callup_id'], token = data['response_token'];
    final title = data['title'], body = data['body'];
    if (data['kind'] != 'callup' ||
        route == null ||
        !route.startsWith('/calendar/event/') ||
        callupId is! String ||
        !_callupId.hasMatch(callupId) ||
        token is! String ||
        !_token.hasMatch(token) ||
        title is! String ||
        body is! String) {
      return null;
    }
    return CallupPush._(
      title: title,
      body: body,
      route: route,
      callupId: callupId,
      token: token,
      english: data['language'] == 'en',
    );
  }

  final String title, body, route, callupId, token;
  final bool english;

  /// Stable per callup, so a reminder replaces the earlier notification.
  int get notificationId => _stableId(callupId);

  CallupNotificationTexts get texts => english
      ? const CallupNotificationTexts(
          accept: 'Coming',
          decline: "Can't…",
          sent: 'Answer sent: coming',
          gone: 'This callup can no longer be answered here',
          failed: "The answer wasn't sent – open the callup",
          locked: 'Unlock the phone to answer',
        )
      : const CallupNotificationTexts(
          accept: 'Kommer',
          decline: 'Kan inte…',
          sent: 'Svar skickat: kommer',
          gone: 'Kallelsen kan inte besvaras här längre',
          failed: 'Svaret skickades inte – öppna kallelsen',
          locked: 'Lås upp telefonen för att svara',
        );
}

/// A message push one can reply to (a data message, see notification-worker):
/// the app draws it with "Svara". Null for anything else.
class MessagePush {
  const MessagePush._({
    required this.title,
    required this.body,
    required this.route,
    required this.threadId,
    required this.token,
    required this.english,
  });

  static final _threadId = RegExp(r'^[0-9a-fA-F-]{36}$');
  static final _token = RegExp(r'^[0-9a-f]{64}$');

  static MessagePush? parse(Map<String, dynamic> data) {
    final route = PushRoutes.safe(data['route']);
    final threadId = data['thread_id'], token = data['reply_token'];
    final title = data['title'], body = data['body'];
    if (data['kind'] != 'message' ||
        threadId is! String ||
        !_threadId.hasMatch(threadId) ||
        route != '/inbox?thread=$threadId' ||
        token is! String ||
        !_token.hasMatch(token) ||
        title is! String ||
        body is! String) {
      return null;
    }
    return MessagePush._(
      title: title,
      body: body,
      route: route!,
      threadId: threadId,
      token: token,
      english: data['language'] == 'en',
    );
  }

  final String title, body, route, threadId, token;
  final bool english;

  /// Stable per thread, so a newer message replaces the earlier one.
  int get notificationId => _stableId(threadId);

  MessageNotificationTexts get texts => english
      ? const MessageNotificationTexts(
          reply: 'Reply',
          hint: 'Write a reply',
          sent: 'Reply sent',
          gone: "You can't reply here any more – open the conversation",
          failed: "The reply wasn't sent – open the conversation",
          locked: 'Unlock the phone to reply',
        )
      : const MessageNotificationTexts(
          reply: 'Svara',
          hint: 'Skriv ett svar',
          sent: 'Svar skickat',
          gone: 'Det går inte att svara här längre – öppna samtalet',
          failed: 'Svaret skickades inte – öppna samtalet',
          locked: 'Lås upp telefonen för att svara',
        );
}

int _stableId(String value) {
  // FNV-1a: String.hashCode is not guaranteed to be stable across isolates.
  // 29 bits, so the plugin's request codes (id * 4 + n) never overflow and
  // two notifications never share an action intent.
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x1fffffff;
  }
  return hash;
}

String _randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The channel the app's notifications use (idempotent; also needed in the
/// background isolate, which may run before the app ever opened).
Future<void> _ensureChannel() {
  final english = PlatformDispatcher.instance.locale.languageCode == 'en';
  return TeamzoneNotifications.createChannel(
    name: english ? 'Callups and messages' : 'Kallelser och meddelanden',
    description: english
        ? 'Callups, reminders and new messages'
        : 'Kallelser, påminnelser och nya meddelanden',
  );
}

/// Shows a push on Android: an answerable callup or a message one can reply
/// to with its buttons; while the app is open (FCM shows nothing then) also a
/// plain notification. In the background FCM shows plain notifications
/// itself. If the buttons cannot be drawn, the push still appears plain.
Future<void> showPush(RemoteMessage message, {required bool foreground}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _showPush(message, foreground: foreground);
  } catch (error) {
    AppErrors.caught('push_services.showPush', error);
    final title = message.data['title'] ?? message.notification?.title;
    final body = message.data['body'] ?? message.notification?.body;
    if (title is String && body is String) {
      await TeamzoneNotifications.showPlain(
        id: _stableId(message.messageId ?? title),
        title: title,
        body: body,
        route: PushRoutes.safe(message.data['route']) ?? '/inbox',
      );
    }
  }
}

Future<void> _showPush(
  RemoteMessage message, {
  required bool foreground,
}) async {
  const environment = AppEnvironment.fromDefines();
  final callup = CallupPush.parse(message.data);
  if (callup != null && environment.supabaseUrl.isNotEmpty) {
    await TeamzoneNotifications.showCallup(
      id: callup.notificationId,
      title: callup.title,
      body: callup.body,
      route: callup.route,
      declineRoute: PushRoutes.decline(callup.route, callup.callupId),
      token: callup.token,
      idempotencyKey: _randomUuid(),
      endpoint: '${environment.supabaseUrl}/functions/v1/push-callup-response',
      apiKey: environment.supabasePublishableKey,
      texts: callup.texts,
    );
    return;
  }
  final reply = MessagePush.parse(message.data);
  if (reply != null && environment.supabaseUrl.isNotEmpty) {
    await TeamzoneNotifications.showMessage(
      id: reply.notificationId,
      title: reply.title,
      body: reply.body,
      route: reply.route,
      token: reply.token,
      idempotencyKey: _randomUuid(),
      endpoint: '${environment.supabaseUrl}/functions/v1/push-message-reply',
      apiKey: environment.supabasePublishableKey,
      texts: reply.texts,
    );
    return;
  }
  final notification = message.notification;
  final title = notification?.title ?? message.data['title'];
  final body = notification?.body ?? message.data['body'];
  if ((foreground || notification == null) &&
      title is String &&
      body is String) {
    await TeamzoneNotifications.showPlain(
      id: _stableId(message.messageId ?? title),
      title: title,
      body: body,
      route: PushRoutes.safe(message.data['route']) ?? '/inbox',
    );
  }
}

/// FCM's background handler (registered in main): runs in its own isolate
/// when a data message arrives while the app is closed or in the background.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    await _ensureChannel();
    await showPush(message, foreground: false);
  } catch (error) {
    AppErrors.caught('push_services.background', error);
  }
}

class UnconfiguredPushServices implements PushServices {
  const UnconfiguredPushServices();
  @override
  bool get supported => false;
  @override
  Future<PushPermission> permission() async => PushPermission.denied;
  @override
  Future<bool> requestAndRegister() async => false;
  @override
  Future<void> registerIfAllowed() async {}
  @override
  Future<void> unregister() async {}
  @override
  Stream<String> get openedRoutes => const Stream.empty();
  @override
  Future<String?> initialRoute() async => null;
  @override
  Future<bool> wasOffered() async => true;
  @override
  Future<void> markOffered() async {}
}

class FirebasePushServices implements PushServices {
  FirebasePushServices(this._client);

  /// Push needs Firebase, which main() initializes on Android (and iOS once
  /// configured).
  static PushServices create(SupabaseClient client) =>
      !kIsWeb && Firebase.apps.isNotEmpty
      ? FirebasePushServices(client)
      : const UnconfiguredPushServices();

  final SupabaseClient _client;
  String? _registeredToken;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  bool _initialConsumed = false;

  static const _offeredKey = 'push.offered.v1';

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  bool get supported => true;

  @override
  Future<PushPermission> permission() async {
    final settings = await _messaging.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => PushPermission.granted,
      AuthorizationStatus.notDetermined => PushPermission.notDetermined,
      // Android only reports enabled or not: before the first question
      // (Android 13+) notifications are off, which is not a refusal.
      AuthorizationStatus.denied =>
        defaultTargetPlatform == TargetPlatform.android && !await wasOffered()
            ? PushPermission.notDetermined
            : PushPermission.denied,
    };
  }

  @override
  Future<bool> requestAndRegister() async {
    final settings = await _messaging.requestPermission();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (granted) await _register();
    return granted;
  }

  @override
  Future<void> registerIfAllowed() async {
    if (await permission() == PushPermission.granted) await _register();
  }

  Future<void> _register() async {
    await _listenInForeground();
    final token = await _messaging.getToken();
    if (token == null) return;
    await _send(token);
    _tokenRefresh ??= _messaging.onTokenRefresh.listen(
      (fresh) => unawaited(
        _send(fresh).catchError(
          (Object error) => AppErrors.caught('push_services.refresh', error),
        ),
      ),
    );
  }

  Future<void> _send(String token) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'register_push_endpoint',
          params: {'platform': _platform, 'token': token},
        );
    _registeredToken = token;
  }

  /// The channel the notifications use, and pushes while the app is open.
  Future<void> _listenInForeground() async {
    if (_foreground != null ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    await _ensureChannel();
    _foreground = FirebaseMessaging.onMessage.listen(
      (message) => unawaited(
        showPush(message, foreground: true).catchError(
          (Object error) => AppErrors.caught('push_services.foreground', error),
        ),
      ),
    );
  }

  @override
  Future<void> unregister() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    await _foreground?.cancel();
    _foreground = null;
    final token = _registeredToken ?? await _messaging.getToken();
    if (token != null) {
      await _client
          .schema('api')
          .rpc<Object?>('unregister_push_endpoint', params: {'token': token});
    }
    _registeredToken = null;
    await _messaging.deleteToken();
  }

  /// Taps on FCM's own notifications and on the app's (callups, and pushes
  /// shown while the app was open).
  @override
  Stream<String> get openedRoutes => Stream<Object?>.multi((controller) {
    final fcm = FirebaseMessaging.onMessageOpenedApp
        .map((message) => message.data['route'])
        .listen(controller.add);
    final own = defaultTargetPlatform == TargetPlatform.android
        ? TeamzoneNotifications.openedRoutes.listen(controller.add)
        : null;
    controller.onCancel = () async {
      await fcm.cancel();
      await own?.cancel();
    };
  }).map(PushRoutes.safe).where((route) => route != null).cast<String>();

  @override
  Future<String?> initialRoute() async {
    if (_initialConsumed) return null;
    _initialConsumed = true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final own = PushRoutes.safe(
        await TeamzoneNotifications.takeLaunchRoute(),
      );
      if (own != null) return own;
    }
    final message = await _messaging.getInitialMessage();
    return PushRoutes.safe(message?.data['route']);
  }

  @override
  Future<bool> wasOffered() async =>
      (await SharedPreferences.getInstance()).getBool(_offeredKey) ?? false;

  @override
  Future<void> markOffered() async =>
      (await SharedPreferences.getInstance()).setBool(_offeredKey, true);
}
