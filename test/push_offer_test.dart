import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/push/push_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';

void main() {
  testWidgets('notifications are offered once there is something unread', (
    tester,
  ) async {
    final push = _Push();
    final messaging = _Messaging(unread: 1);
    await _open(tester, push, messaging);
    expect(find.byKey(const ValueKey('push-offer')), findsOneWidget);
    expect(
      find.textContaining('aldrig namn eller meddelandetext'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tillåt notiser'));
    await tester.pumpAndSettle();
    expect(push.requested, isTrue);
    expect(push.offered, isTrue);
    // Message pushes follow the inbox setting, so that is turned on too.
    expect(messaging.pushEnabled, isTrue);
  });

  testWidgets('"Inte nu" is remembered and nothing is asked of the OS', (
    tester,
  ) async {
    final push = _Push();
    final messaging = _Messaging(unread: 1);
    await _open(tester, push, messaging);
    await tester.tap(find.text('Inte nu'));
    await tester.pumpAndSettle();
    expect(push.requested, isFalse);
    expect(push.offered, isTrue);
    expect(messaging.pushEnabled, isFalse);
  });

  testWidgets(
    'no offer without anything unread, once offered or once decided',
    (tester) async {
      for (final push in [
        _Push(),
        _Push()..offered = true,
        _Push()..state = PushPermission.denied,
      ]) {
        final unread =
            push.offered || push.state != PushPermission.notDetermined ? 3 : 0;
        await _open(tester, push, _Messaging(unread: unread));
        expect(find.byKey(const ValueKey('push-offer')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('offered when the app returns with something unread', (
    tester,
  ) async {
    final push = _Push();
    final messaging = _Messaging(unread: 0);
    await _open(tester, push, messaging);
    expect(find.byKey(const ValueKey('push-offer')), findsNothing);
    messaging.unread = 1;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('push-offer')), findsOneWidget);
  });

  testWidgets('allowed devices stay registered and taps open the target', (
    tester,
  ) async {
    final push = _Push()..state = PushPermission.granted;
    await _open(tester, push, _Messaging(unread: 0));
    expect(push.registered, 1);
    push.taps.add('https://evil.example/phish');
    await tester.pumpAndSettle();
    // Unsafe routes are ignored without navigating or failing.
    expect(tester.takeException(), isNull);
  });

  test('only the app\'s own event and thread routes are followed', () {
    const event = '/calendar/event/30000000-0000-4000-8000-000000000001';
    const thread = '/inbox?thread=40000000-0000-4000-8000-000000000001';
    expect(PushRoutes.safe(event), event);
    expect(PushRoutes.safe(thread), thread);
    expect(PushRoutes.safe('/inbox'), '/inbox');
    expect(PushRoutes.safe('https://evil.example'), isNull);
    expect(PushRoutes.safe('/calendar/event/../../settings'), isNull);
    expect(PushRoutes.safe(42), isNull);
    // "Kan inte…" opens the participants with the decline for that callup.
    const callupId = '60000000-0000-4000-8000-000000000001';
    final decline = PushRoutes.decline(event, callupId);
    expect(decline, '$event?tab=participants&decline=$callupId');
    expect(PushRoutes.safe(decline), decline);
    expect(PushRoutes.safe('$event?tab=participants&decline=x'), isNull);
    expect(PushRoutes.safe('$event?decline=$callupId'), isNull);
  });

  test('a message push with a reply token needs every field well-formed', () {
    const threadId = '40000000-0000-4000-8000-000000000001';
    final data = <String, dynamic>{
      'kind': 'message',
      'title': 'Nytt meddelande',
      'body': 'P2012',
      'route': '/inbox?thread=$threadId',
      'thread_id': threadId,
      'reply_token': 'b' * 64,
      'language': 'sv',
    };
    final push = MessagePush.parse(data)!;
    expect(push.texts.reply, 'Svara');
    expect(push.route, '/inbox?thread=$threadId');
    expect(
      MessagePush.parse({...data, 'language': 'en'})!.texts.reply,
      'Reply',
    );
    for (final broken in [
      {...data, 'kind': 'callup'},
      {...data, 'reply_token': 'b' * 63},
      {...data, 'thread_id': 'x'},
      // The route must be this thread's.
      {...data, 'route': '/inbox?thread=40000000-0000-4000-8000-000000000002'},
      {...data, 'route': '/calendar/event/$threadId'},
      {...data, 'body': null},
    ]) {
      expect(MessagePush.parse(broken), isNull, reason: '$broken');
    }
  });

  test('an answerable callup push needs every field well-formed', () {
    final data = <String, dynamic>{
      'kind': 'callup',
      'title': 'Ny kallelse',
      'body': 'Träning · P2012 · lör 17 okt 18:00',
      'route': '/calendar/event/30000000-0000-4000-8000-000000000001',
      'callup_id': '60000000-0000-4000-8000-000000000001',
      'response_token': 'a' * 64,
      'language': 'sv',
    };
    final push = CallupPush.parse(data)!;
    expect(push.texts.accept, 'Kommer');
    expect(push.texts.decline, 'Kan inte…');
    expect(
      push.notificationId,
      CallupPush.parse({...data, 'title': 'Påminnelse'})!.notificationId,
      reason: 'a reminder replaces the earlier notification',
    );
    expect(
      CallupPush.parse({...data, 'language': 'en'})!.texts.accept,
      'Coming',
    );
    for (final broken in [
      {...data, 'kind': 'message'},
      {...data, 'response_token': 'A' * 64},
      {...data, 'response_token': 'a' * 63},
      {...data, 'callup_id': 'x'},
      {...data, 'route': 'https://evil.example'},
      {...data, 'route': '/inbox'},
      {...data, 'title': null},
    ]) {
      expect(CallupPush.parse(broken), isNull, reason: '$broken');
    }
  });
}

Future<void> _open(
  WidgetTester tester,
  _Push push,
  _Messaging messaging,
) async {
  await tester.pumpWidget(
    TeamZoneApp(
      environment: const AppEnvironment(name: 'push'),
      locale: const Locale('sv'),
      services: AppServices(
        identity: const _Identity(),
        messaging: messaging,
        push: push,
        isConfigured: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Push implements PushServices {
  PushPermission state = PushPermission.notDetermined;
  bool offered = false;
  bool requested = false;
  int registered = 0;
  final taps = StreamController<String>.broadcast();

  @override
  bool get supported => true;
  @override
  Future<PushPermission> permission() async => state;
  @override
  Future<bool> requestAndRegister() async {
    requested = true;
    state = PushPermission.granted;
    registered++;
    return true;
  }

  @override
  Future<void> registerIfAllowed() async {
    if (state == PushPermission.granted) registered++;
  }

  @override
  Future<void> unregister() async {}
  @override
  Stream<String> get openedRoutes => taps.stream;
  @override
  Future<String?> initialRoute() async => null;
  @override
  Future<bool> wasOffered() async => offered;
  @override
  Future<void> markOffered() async => offered = true;
}

class _Messaging extends UnconfiguredMessagingServices {
  _Messaging({required this.unread});
  int unread;
  bool pushEnabled = false;

  @override
  Future<NotificationCenter> listNotifications() async =>
      NotificationCenter(items: const [], unreadCount: unread);

  @override
  Future<void> setPushEnabled(bool enabled, String idempotencyKey) async =>
      pushEnabled = enabled;
}

class _Identity implements IdentityServices {
  const _Identity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context-a',
      clubId: 'alby',
      clubName: 'Alby IF',
      teamId: 'team-a',
      teamName: 'F2012',
      rolePackage: 'player',
      capabilities: {'team.read'},
    ),
  ];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}
