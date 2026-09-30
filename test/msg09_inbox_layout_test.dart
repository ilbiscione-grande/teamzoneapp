import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';

void main() {
  testWidgets('clubs collapse to their name; the active club starts open', (
    tester,
  ) async {
    await _openInbox(tester, _Messaging());
    expect(find.byKey(const ValueKey('inbox-club-Alby IF')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-club-Bergby FF')), findsOneWidget);
    // Active club open, the other closed to its name.
    expect(find.text('Träningstider'), findsOneWidget);
    expect(find.text('Cupresa'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('inbox-club-Bergby FF')));
    await tester.pumpAndSettle();
    expect(find.text('Cupresa'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inbox-club-Alby IF')));
    await tester.pumpAndSettle();
    expect(find.text('Träningstider'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recipient count decides direct or group conversation', (
    tester,
  ) async {
    final messaging = _Messaging();
    await _openInbox(tester, messaging);
    await tester.tap(find.byTooltip('Nytt meddelande'));
    await tester.pumpAndSettle();
    expect(find.text('Välj en eller flera mottagare'), findsOneWidget);
    // No Direkt/Grupp choice any more.
    expect(find.text('Direkt'), findsNothing);
    await tester.tap(find.text('Ada Andersson'));
    await tester.pumpAndSettle();
    expect(find.text('Direktmeddelande'), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-group-name')), findsNothing);
    await tester.tap(find.text('Bo Berg'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppkonversation'), findsOneWidget);
    // A group needs a name.
    await tester.tap(find.text('Skapa grupp'));
    await tester.pumpAndSettle();
    expect(find.text('Ange ett gruppnamn.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('compose-group-name')),
      'Målvakter',
    );
    await tester.tap(find.text('Skapa grupp'));
    await tester.pumpAndSettle();
    expect(messaging.created.single, ('group', 'Målvakter', 2));
  });

  testWidgets('removing a recipient turns a group back into direct', (
    tester,
  ) async {
    final messaging = _Messaging();
    await _openInbox(tester, messaging);
    await tester.tap(find.byTooltip('Nytt meddelande'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ada Andersson'));
    await tester.tap(find.text('Bo Berg'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ta bort Bo Berg'));
    await tester.pumpAndSettle();
    expect(find.text('Direktmeddelande'), findsOneWidget);
    await tester.tap(find.text('Starta konversation'));
    await tester.pumpAndSettle();
    expect(messaging.created.single, ('direct', '', 1));
  });

  testWidgets('notifications are read or removed without opening', (
    tester,
  ) async {
    final messaging = _Messaging();
    await _openInbox(tester, messaging);
    await tester.tap(find.byTooltip('Fler inkorgsåtgärder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notiser').last);
    await tester.pumpAndSettle();
    expect(find.text('Kallelse till match'), findsOneWidget);
    // Mark as read: the item stays, the read button goes.
    await tester.tap(find.byKey(const ValueKey('notification-read-n1')));
    await tester.pumpAndSettle();
    expect(messaging.states, [('n1', 'read')]);
    expect(find.byKey(const ValueKey('notification-read-n1')), findsNothing);
    expect(find.text('Kallelse till match'), findsOneWidget);
    // Remove: the item leaves the list.
    await tester.tap(find.byKey(const ValueKey('notification-dismiss-n1')));
    await tester.pumpAndSettle();
    expect(messaging.states.last, ('n1', 'dismissed'));
    expect(find.text('Kallelse till match'), findsNothing);
    expect(find.text('Nytt meddelande i Cupresa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter sheet scrolls instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(390, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openInbox(tester, _Messaging(), resize: false);
    await tester.tap(find.byTooltip('Filtrera inkorgen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Teams sit under their club, which opens on tap.
    expect(find.text('P2010'), findsNothing);
    final club = find.byKey(const ValueKey('inbox-filter-club-Bergby FF'));
    await tester.ensureVisible(club);
    await tester.pumpAndSettle();
    await tester.tap(club);
    await tester.pumpAndSettle();
    expect(find.text('P2010'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Always closable from the top, however long the list is.
    await tester.tap(find.byKey(const ValueKey('inbox-filter-close')));
    await tester.pumpAndSettle();
    expect(find.text('Lag och klubbar'), findsNothing);
  });
}

Future<void> _openInbox(
  WidgetTester tester,
  _Messaging messaging, {
  bool resize = true,
}) async {
  if (resize) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    TeamZoneApp(
      environment: const AppEnvironment(name: 'msg09'),
      locale: const Locale('sv'),
      services: AppServices(
        identity: const _Identity(),
        messaging: messaging,
        isConfigured: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Inbox').last);
  await tester.pumpAndSettle();
}

class _Messaging extends UnconfiguredMessagingServices {
  final created = <(String, String, int)>[];
  final states = <(String, String)>[];

  NotificationItem _notification(String id, String title, bool unread) =>
      NotificationItem(
        id: id,
        eventType: 'callup.sent',
        createdAt: DateTime(2026, 9, 29, 12),
        category: 'callup',
        title: title,
        preview: 'Förhandsvisning',
        deepLink: '/calendar',
        unread: unread,
        canonicalKey: id,
        priority: 1,
      );

  @override
  Future<NotificationCenter> listNotifications() async => NotificationCenter(
    items: [
      if (!states.contains(('n1', 'dismissed')))
        _notification(
          'n1',
          'Kallelse till match',
          !states.contains(('n1', 'read')),
        ),
      _notification('n2', 'Nytt meddelande i Cupresa', false),
    ],
    unreadCount: states.contains(('n1', 'read')) ? 0 : 1,
  );

  @override
  Future<void> setNotificationState(String a, String b, String c) async =>
      states.add((a, b));

  @override
  Future<List<MessageThreadSummary>> listThreads(
    List<String> contextIds,
  ) async => [
    MessageThreadSummary(
      id: 't1',
      type: 'group',
      subject: 'Träningstider',
      revision: 1,
      unreadCount: 1,
      muted: false,
      lastAt: DateTime(2026, 9, 29, 18),
      scopeLabels: const ['F2012 · Alby IF'],
    ),
    MessageThreadSummary(
      id: 't2',
      type: 'group',
      subject: 'Cupresa',
      revision: 1,
      unreadCount: 2,
      muted: false,
      lastAt: DateTime(2026, 9, 28, 18),
      scopeLabels: const ['P2010 · Bergby FF'],
    ),
  ];

  @override
  Future<List<AllowedRecipient>> resolveRecipients(
    String contextId, {
    String? query,
  }) async => const [
    AllowedRecipient(
      profileId: 'ada',
      displayName: 'Ada Andersson',
      rolePackage: 'player',
    ),
    AllowedRecipient(
      profileId: 'bo',
      displayName: 'Bo Berg',
      rolePackage: 'leader',
    ),
  ];

  @override
  Future<String> createThread({
    required String contextId,
    required String type,
    required String subject,
    required List<String> recipientIds,
    required String idempotencyKey,
  }) async {
    created.add((type, subject, recipientIds.length));
    // Stop here: opening the new thread is covered elsewhere.
    throw StateError('recorded');
  }
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
      rolePackage: 'leader',
      capabilities: {'team.read'},
    ),
    TeamZoneContext(
      id: 'context-a2',
      clubId: 'alby',
      clubName: 'Alby IF',
      teamId: 'team-a2',
      teamName: 'F2013',
      rolePackage: 'leader',
      capabilities: {'team.read'},
    ),
    TeamZoneContext(
      id: 'context-b',
      clubId: 'bergby',
      clubName: 'Bergby FF',
      teamId: 'team-b',
      teamName: 'P2010',
      rolePackage: 'leader',
      capabilities: {'team.read'},
    ),
    TeamZoneContext(
      id: 'context-b2',
      clubId: 'bergby',
      clubName: 'Bergby FF',
      teamId: 'team-b2',
      teamName: 'P2011',
      rolePackage: 'leader',
      capabilities: {'team.read'},
    ),
    TeamZoneContext(
      id: 'context-c',
      clubId: 'cby',
      clubName: 'Cby BK',
      teamId: 'team-c',
      teamName: 'F2014',
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
