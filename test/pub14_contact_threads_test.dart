import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/messaging/contact_threads.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';

// PUB-14: messages from the club site as threads in the app.

class _Messaging extends UnconfiguredMessagingServices {
  final replies = <(String, String)>[];
  final handled = <(String, bool)>[];
  bool failNextReply = false;
  bool isHandled = false;
  final messages = <Map<String, dynamic>>[
    {
      'id': 't1',
      'direction': 'in',
      'body': 'Hej! Kan min son börja?',
      'created_at': '2026-10-16T18:37:00Z',
    },
  ];

  Map<String, dynamic> _summary(String id, {bool handled = false}) => {
    'id': id,
    'club_name': 'Alby IF',
    'team_name': id == 't1' ? 'P2012' : null,
    'sender_name': id == 't1' ? 'Ada Andersson' : 'Bo Berg',
    'sender_email': 'ada@example.se',
    'subject': id == 't1' ? 'Ny spelare' : 'Sponsring',
    'preview': 'Hej!',
    'last_activity_at': '2026-10-16T18:37:00Z',
    'expires_at': '2026-11-15T18:37:00Z',
    'handled': handled,
    'unread': !handled,
  };

  @override
  Future<List<ContactThreadSummary>> listContactThreads() async {
    return [
      ContactThreadSummary.fromJson(_summary('t1', handled: isHandled)),
      ContactThreadSummary.fromJson(_summary('t2', handled: true)),
    ];
  }

  @override
  Future<ContactThread> getContactThread(String threadId) async =>
      ContactThread.fromJson({
        ..._summary(threadId, handled: isHandled),
        'messages': messages,
      });

  @override
  Future<void> replyContactThread({
    required String threadId,
    required String body,
    required String idempotencyKey,
  }) async {
    replies.add((body, idempotencyKey));
    if (failNextReply) {
      failNextReply = false;
      throw StateError('network');
    }
    messages.add({
      'id': 'r${messages.length}',
      'direction': 'out',
      'body': body,
      'created_at': '2026-10-16T19:00:00Z',
      'author_name': 'Tränare Tina',
      'email_state': 'pending',
    });
  }

  @override
  Future<void> setContactThreadHandled(String threadId, bool value) async {
    handled.add((threadId, value));
    isHandled = value;
  }
}

Future<void> _open(WidgetTester tester, _Messaging messaging) async {
  await tester.pumpWidget(
    MaterialApp(home: ContactThreadsPage(services: messaging)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('threads are split into to handle and handled', (tester) async {
    final messaging = _Messaging();
    await _open(tester, messaging);
    expect(find.text('Att hantera (1)'), findsOneWidget);
    expect(find.textContaining('Ada Andersson · Ny spelare'), findsOneWidget);
    expect(find.textContaining('P2012 · Alby IF'), findsOneWidget);
    expect(find.textContaining('Bo Berg'), findsNothing);
    await tester.tap(find.text('Hanterade (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bo Berg · Sponsring'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an answer is sent once, and retried with the same key', (
    tester,
  ) async {
    final messaging = _Messaging()..failNextReply = true;
    await _open(tester, messaging);
    await tester.tap(find.textContaining('Ada Andersson · Ny spelare'));
    await tester.pumpAndSettle();
    expect(find.text('Hej! Kan min son börja?'), findsOneWidget);
    expect(find.textContaining('ada@example.se'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('contact-reply-field')),
      'Välkommen på torsdag!',
    );
    await tester.tap(find.byKey(const ValueKey('contact-reply-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('kunde inte sparas'), findsOneWidget);
    // Let the message clear the send button first.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('contact-reply-send')));
    await tester.pumpAndSettle();
    expect(messaging.replies, hasLength(2));
    expect(
      messaging.replies.first.$2,
      messaging.replies.last.$2,
      reason: 'the retry reuses the idempotency key',
    );
    expect(find.text('Välkommen på torsdag!'), findsOneWidget);
    expect(find.text('Skickas…'), findsOneWidget);
    expect(find.textContaining('Tränare Tina'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('contact-reply-field')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('marking handled closes the thread and moves it', (tester) async {
    final messaging = _Messaging();
    await _open(tester, messaging);
    await tester.tap(find.textContaining('Ada Andersson · Ny spelare'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('contact-thread-handled')));
    await tester.pumpAndSettle();
    expect(messaging.handled, [('t1', true)]);
    expect(find.text('Att hantera (0)'), findsOneWidget);
    expect(find.text('Hanterade (2)'), findsOneWidget);
  });
}
