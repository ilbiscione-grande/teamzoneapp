import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';

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

/// Only the app's own event and thread routes are followed.
abstract final class PushRoutes {
  static final _safe = RegExp(
    r'^/(calendar/event/[0-9a-fA-F-]{36}|inbox(\?thread=[0-9a-fA-F-]{36})?)$',
  );

  static String? safe(Object? route) =>
      route is String && _safe.hasMatch(route) ? route : null;
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

  @override
  Future<void> unregister() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    final token = _registeredToken ?? await _messaging.getToken();
    if (token != null) {
      await _client
          .schema('api')
          .rpc<Object?>('unregister_push_endpoint', params: {'token': token});
    }
    _registeredToken = null;
    await _messaging.deleteToken();
  }

  @override
  Stream<String> get openedRoutes => FirebaseMessaging.onMessageOpenedApp
      .map((message) => PushRoutes.safe(message.data['route']))
      .where((route) => route != null)
      .cast<String>();

  @override
  Future<String?> initialRoute() async {
    if (_initialConsumed) return null;
    _initialConsumed = true;
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
