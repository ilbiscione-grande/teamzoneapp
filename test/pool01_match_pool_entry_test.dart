import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/push/push_services.dart';
import 'package:teamzone_app/src/features/messaging/match_pool.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';

Map<String, dynamic> _listing({bool verified = true}) => {
  'id': 'l1',
  'kind': 'home_slot',
  'team_name': 'P2012',
  'club_name': 'Alby IF',
  'verified': verified,
  'starts_at': '2026-11-14T09:00:00Z',
  'ends_at': '2026-11-14T10:30:00Z',
  'place_label': 'Alby, Botkyrka',
  'venue_name': 'Alby IP',
  'match_format': '7v7',
  'age_class': 'P12',
  'current': true,
};

class _Messaging extends UnconfiguredMessagingServices {
  String state = 'pending';
  bool? acceptedWithCalendar;
  final sent = <String>[];

  @override
  Future<List<MatchPoolConversationSummary>>
  listMatchPoolConversations() async => [
    MatchPoolConversationSummary.fromJson({
      'id': 'i1',
      'my_side': 'listing',
      'state': state,
      'other_team_name': 'P2012',
      'other_club_name': 'Bro BK',
      'other_verified': false,
      'unread': true,
      'last_message': 'Vi kommer gärna!',
      'last_activity_at': '2026-10-17T10:00:00Z',
      'listing': _listing(),
    }),
  ];

  @override
  Future<MatchPoolConversation> getMatchPoolConversation(
    String interestId,
  ) async => MatchPoolConversation.fromJson({
    'my_side': 'listing',
    'my_event_id': state == 'accepted' ? 'e1' : null,
    'listing': _listing(),
    'interest': {
      'team_name': 'P2012',
      'club_name': 'Bro BK',
      'verified': false,
      'state': state,
    },
    'messages': [
      {
        'id': 'm1',
        'side': 'interest',
        'body': 'Vi kommer gärna!',
        'created_at': '2026-10-17T10:00:00Z',
        'author_name': 'Bo',
      },
      for (final (index, body) in sent.indexed)
        {
          'id': 'r$index',
          'side': 'listing',
          'body': body,
          'created_at': '2026-10-17T11:00:00Z',
        },
    ],
  });

  @override
  Future<void> sendMatchPoolMessage({
    required String interestId,
    required String body,
    required String idempotencyKey,
  }) async => sent.add(body);

  @override
  Future<void> acceptMatchPoolInterest(
    String interestId,
    bool addToCalendar,
  ) async {
    acceptedWithCalendar = addToCalendar;
    state = 'accepted';
  }
}

void main() {
  test('the match pool summary reads leader and unread', () {
    final summary = MatchPoolSummary.fromJson({'leader': true, 'unread': 3});
    expect(summary.leader, isTrue);
    expect(summary.unread, 3);
    final empty = MatchPoolSummary.fromJson({});
    expect(empty.leader, isFalse);
    expect(empty.unread, 0);
  });

  test('without a backend nobody is a leader in the pool', () async {
    final summary = await const UnconfiguredMessagingServices()
        .getMatchPoolSummary();
    expect(summary.leader, isFalse);
  });

  test('a match pool notification may open its conversation', () {
    const route = '/inbox?pool=6f0e8a1c-2b3d-4e5f-8a9b-0c1d2e3f4a5b';
    expect(PushRoutes.safe(route), route);
    expect(PushRoutes.safe('/inbox?pool=x'), isNull);
  });

  testWidgets('the list shows the other club as unverified', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MatchPoolPage(services: _Messaging())),
    );
    await tester.pumpAndSettle();
    expect(find.text('P2012 · Bro BK'), findsOneWidget);
    expect(find.text('! Ej verifierad klubb'), findsOneWidget);
    expect(find.text('Väntar på svar'), findsOneWidget);
    expect(find.text('Vi kommer gärna!'), findsOneWidget);
  });

  testWidgets('a conversation is answered and booked without the calendar', (
    tester,
  ) async {
    final services = _Messaging();
    await tester.pumpWidget(
      MaterialApp(
        home: MatchPoolConversationPage(services: services, interestId: 'i1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('inte verifierad av TeamZone'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('match-pool-reply')),
      'Kl 10 funkar!',
    );
    await tester.tap(find.byKey(const ValueKey('match-pool-send')));
    await tester.pumpAndSettle();
    expect(services.sent, ['Kl 10 funkar!']);
    expect(find.text('Kl 10 funkar!'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('match-pool-calendar')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('match-pool-accept')));
    await tester.tap(find.byKey(const ValueKey('match-pool-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boka'));
    await tester.pumpAndSettle();
    expect(services.acceptedWithCalendar, isFalse);
    expect(find.byKey(const ValueKey('match-pool-decide')), findsNothing);
    expect(find.textContaining('Matchen är bokad'), findsWidgets);
  });
}
