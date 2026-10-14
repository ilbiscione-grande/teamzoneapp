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
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

void main() {
  testWidgets('sent contact details show as a badge on their team heading', (
    tester,
  ) async {
    final roster = _Roster();
    await _openInbox(
      tester,
      _Messaging(),
      identity: const _Identity(manager: true),
      roster: roster,
    );
    final heading = find.byKey(const ValueKey('inbox-team-Alby IF-F2012'));
    expect(heading, findsOneWidget);
    final icon = find.descendant(
      of: heading,
      matching: find.byKey(const ValueKey('inbox-intake')),
    );
    expect(find.descendant(of: icon, matching: find.text('2')), findsOneWidget);
    // Only the selected team's details count; the other team's wait.
    expect(find.byKey(const ValueKey('inbox-intake')), findsOneWidget);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('Inskickade kontakter · F2012'), findsOneWidget);
    expect(find.text('Nina Ny'), findsOneWidget);
    expect(find.text('Olle Ny'), findsOneWidget);
    expect(find.text('Pia Annan'), findsNothing);
    // The pages themselves stay in the team's contact update view.
    expect(find.text('Aktiva sidor'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('intake-add-sub-1')));
    await tester.pumpAndSettle();
    expect(roster.accepted, ['sub-1']);
    expect(find.text('Nina Ny'), findsNothing);
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('inbox-intake')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a team without conversations still shows its sent details', (
    tester,
  ) async {
    await _openInbox(
      tester,
      _Messaging(threads: false),
      identity: const _Identity(manager: true),
      roster: _Roster(),
    );
    expect(find.text('Inkorgen är tom'), findsNothing);
    expect(
      find.byKey(const ValueKey('inbox-team-Alby IF-F2012')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('inbox-intake')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('people who cannot add to the team see no badge', (tester) async {
    final roster = _Roster();
    await _openInbox(tester, _Messaging(), roster: roster);
    expect(find.byKey(const ValueKey('inbox-intake')), findsNothing);
    expect(roster.overviewCalls, 0);
  });

  testWidgets('a notification from another team widens the inbox to it', (
    tester,
  ) async {
    // Only Alby F2012 is selected; the thread belongs to Bergby P2010.
    final messaging = _Messaging(onlyInScope: true);
    await _openInbox(
      tester,
      messaging,
      push: const _Push('/inbox?thread=42000000-0000-4000-8000-000000000002'),
      tapInbox: false,
    );
    expect(messaging.scopes.first, ['context-a']);
    expect(messaging.scopes.last, contains('context-b'));
    expect(messaging.openedThreads, ['42000000-0000-4000-8000-000000000002']);
  });

  testWidgets('threads show who they are with, and how many', (tester) async {
    await _openInbox(tester, _Messaging(avatars: true));
    // Träningstider has seven others: two pictures (initials here) and +5.
    final group = find.byKey(const ValueKey('inbox-avatars-t1'));
    expect(group, findsOneWidget);
    expect(
      find.descendant(of: group, matching: find.text('AA')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: group, matching: find.text('BB')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: group, matching: find.text('+5')),
      findsOneWidget,
    );
    expect(find.descendant(of: group, matching: find.text('CC')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picture or initials of a sender stand before the name', (
    tester,
  ) async {
    final messaging = _Messaging(onlyInScope: true, conversation: true);
    await _openInbox(
      tester,
      messaging,
      push: const _Push('/inbox?thread=42000000-0000-4000-8000-000000000002'),
      tapInbox: false,
    );
    final avatar = find.byKey(const ValueKey('sender-avatar-m1'));
    expect(avatar, findsOneWidget);
    // In a group the title has no picture.
    expect(find.byKey(const ValueKey('thread-title-avatar')), findsNothing);
    expect(
      find.descendant(of: avatar, matching: find.text('BB')),
      findsOneWidget,
    );
    // Your own messages show no name and no picture.
    expect(find.byKey(const ValueKey('sender-avatar-m2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a one-to-one conversation has the picture in its title', (
    tester,
  ) async {
    final messaging = _Messaging(
      onlyInScope: true,
      conversation: true,
      direct: true,
    );
    await _openInbox(
      tester,
      messaging,
      push: const _Push('/inbox?thread=42000000-0000-4000-8000-000000000002'),
      tapInbox: false,
    );
    final title = find.byKey(const ValueKey('thread-title-avatar'));
    expect(title, findsOneWidget);
    expect(
      find.descendant(of: title, matching: find.text('BB')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sender-avatar-m1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
  _Identity identity = const _Identity(),
  RosterServices roster = const UnconfiguredRosterServices(),
  PushServices push = const UnconfiguredPushServices(),
  bool tapInbox = true,
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
        identity: identity,
        messaging: messaging,
        roster: roster,
        push: push,
        isConfigured: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (!tapInbox) return;
  await tester.tap(find.text('Inbox').last);
  await tester.pumpAndSettle();
}

/// Push that started the app from a tapped notification.
class _Push extends UnconfiguredPushServices {
  const _Push(this.route);
  final String route;
  @override
  bool get supported => true;
  @override
  Future<String?> initialRoute() async => route;
}

class _Roster extends UnconfiguredRosterServices {
  final accepted = <String>[];
  int overviewCalls = 0;

  IntakeSubmission _submission(String id, String name, String teamId) =>
      IntakeSubmission(
        id: id,
        fullName: name,
        phone: '070-1234567',
        email: '$id@mail.se',
        birthDate: DateTime(2012, 5, 3),
        streetAddress: 'Storgatan 1',
        postalCode: '575 31',
        city: 'Eksjö',
        createdAt: DateTime(2026, 10, 13),
        teamId: teamId,
        teamName: teamId == 'team-a' ? 'F2012' : 'F2013',
      );

  @override
  Future<IntakeOverview> getIntakeOverview({required String clubId}) async {
    overviewCalls++;
    return IntakeOverview(
      canManageClub: false,
      teams: const [
        IntakeTeam(id: 'team-a', name: 'F2012'),
        IntakeTeam(id: 'team-a2', name: 'F2013'),
      ],
      forms: const [],
      submissions: [
        for (final item in [
          _submission('sub-1', 'Nina Ny', 'team-a'),
          _submission('sub-2', 'Olle Ny', 'team-a'),
          _submission('sub-3', 'Pia Annan', 'team-a2'),
        ])
          if (!accepted.contains(item.id)) item,
      ],
    );
  }

  @override
  Future<String> acceptIntakeSubmission({
    required String submissionId,
    required String teamId,
    required String role,
    required String idempotencyKey,
  }) async {
    accepted.add(submissionId);
    return 'person-$submissionId';
  }
}

class _Messaging extends UnconfiguredMessagingServices {
  _Messaging({
    this.threads = true,
    this.onlyInScope = false,
    this.avatars = false,
    this.conversation = false,
    this.direct = false,
  });
  final bool threads;
  final bool avatars;

  /// One message from Bo Berg, then one of your own.
  final bool conversation;

  /// The second thread is a one-to-one conversation with Bo Berg.
  final bool direct;

  /// Like the server: a thread is listed only for its own team's context.
  final bool onlyInScope;
  final scopes = <List<String>>[];
  final openedThreads = <String>[];
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
  ) async {
    scopes.add(contextIds);
    final all = await _threads();
    if (!onlyInScope) return all;
    return [
      for (final thread in all)
        if (contextIds.contains(thread.id == 't1' ? 'context-a' : 'context-b'))
          thread,
    ];
  }

  @override
  Future<Map<String, ThreadAvatars>> listThreadAvatars(
    List<String> threadIds,
  ) async => {
    if (avatars && threadIds.contains('t1'))
      't1': const ThreadAvatars(
        participantCount: 7,
        people: [
          ThreadAvatarPerson(name: 'Ada Andersson'),
          ThreadAvatarPerson(name: 'Bo Berg'),
          ThreadAvatarPerson(name: 'Cia Carlsson'),
        ],
      ),
  };

  @override
  Future<MessagePage> listMessagePage(
    String threadId, {
    int? beforeRevision,
  }) async {
    openedThreads.add(threadId);
    return MessagePage(
      messages: [
        if (conversation) ...[
          ThreadMessage(
            id: 'm1',
            revision: 1,
            state: 'sent',
            createdAt: DateTime(2026, 10, 14, 9),
            senderName: 'Bo Berg',
            senderProfileId: 'bo',
            mine: false,
            body: 'Hej!',
          ),
          ThreadMessage(
            id: 'm2',
            revision: 2,
            state: 'sent',
            createdAt: DateTime(2026, 10, 14, 10),
            senderName: 'Test',
            senderProfileId: 'profile',
            mine: true,
            body: 'Hej själv',
          ),
        ],
      ],
      hasMore: false,
    );
  }

  @override
  Future<List<MessageFile>> listFiles(String threadId) async => const [];

  Future<List<MessageThreadSummary>> _threads() async => [
    if (threads) ...[
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
        id: '42000000-0000-4000-8000-000000000002',
        type: direct ? 'direct' : 'group',
        subject: direct ? 'Bo Berg' : 'Cupresa',
        revision: 1,
        unreadCount: 2,
        muted: false,
        lastAt: DateTime(2026, 9, 28, 18),
        scopeLabels: const ['P2010 · Bergby FF'],
      ),
    ],
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
  const _Identity({this.manager = false});

  /// Lets the active team's leader add people to the roster.
  final bool manager;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => [
    TeamZoneContext(
      id: 'context-a',
      clubId: 'alby',
      clubName: 'Alby IF',
      teamId: 'team-a',
      teamName: 'F2012',
      rolePackage: 'leader',
      capabilities: {'team.read', if (manager) 'team.roster.manage'},
    ),
    ...const [
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
    ],
  ];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}
