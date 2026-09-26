import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827150144_msg04_message_history_cursor.sql',
  ).readAsStringSync();
  final senderMigration = File(
    'supabase/migrations/20260923074843_msg04_sender_identity_for_grouping.sql',
  ).readAsStringSync();
  final messagingFoundation = File(
    'supabase/migrations/20260808110033_s06_messaging_foundation.sql',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/messaging/messaging_services.dart',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/messaging/inbox_surface.dart',
  ).readAsStringSync();
  final browserSignals = File(
    'lib/src/shared/connectivity/browser_online_signals_web.dart',
  ).readAsStringSync();

  test('history uses a stable exclusive revision cursor', () {
    expect(
      migration,
      contains('(before_revision is null or message.revision<before_revision)'),
    );
    expect(
      migration,
      contains('order by message.revision desc,message.id desc'),
    );
    expect(migration, contains('limit page_limit+1'));
    expect(migration, contains("'next_before_revision'"));
    expect(migration, contains("'has_more'"));
  });

  test('every send rechecks active participant access', () {
    expect(
      messagingFoundation,
      contains('internal.actor_can_access_thread(target_thread_id,true)'),
    );
    expect(messagingFoundation, contains("participant.state='active'"));
  });

  test('send is optimistic and retry reuses the idempotency key', () {
    expect(surface, contains('class _PendingMessage'));
    expect(surface, contains('_pending.add(pending)'));
    expect(surface, contains('pending.idempotencyKey'));
    expect(surface, contains('pending.failed = true'));
    expect(surface, contains("feature('Försök skicka igen')"));
  });

  test('lost thread access is distinct from retryable send failure', () {
    expect(surface, contains('if (browserIsOnline())'));
    expect(
      surface,
      contains('await widget.messaging.listMessagePage(widget.thread.id)'),
    );
    expect(surface, contains("readError.code == '42501'"));
    expect(surface, contains('pending.accessLost = accessLost'));
    expect(surface, contains('if (pending.accessLost)'));
    expect(surface, contains('SelectableText(pending.body)'));
  });

  test('thread subscription resyncs and history merge deduplicates', () {
    final models = File(
      'lib/src/features/messaging/messaging_models.dart',
    ).readAsStringSync();
    expect(services, contains("'message:thread:\$threadId'"));
    expect(services, contains('status == RealtimeSubscribeStatus.subscribed'));
    expect(surface, contains('const Duration(milliseconds: 250)'));
    expect(models, contains('message.id: message'));
    expect(models, contains('a.revision.compareTo(b.revision)'));
  });

  test('new message keeps more than 50 loaded older messages in order', () {
    ThreadMessage message(int revision, {String? body}) => ThreadMessage(
      id: 'message-$revision',
      revision: revision,
      state: 'sent',
      createdAt: DateTime.utc(2026, 9, 23),
      senderName: 'Test',
      mine: false,
      body: body ?? 'Message $revision',
    );

    final first = MessagePage(
      messages: [for (var i = 6; i <= 55; i++) message(i)],
      hasMore: true,
      nextBeforeRevision: 6,
    );
    final loaded = mergeOlderMessagePage(
      first.messages,
      MessagePage(
        messages: [for (var i = 1; i <= 5; i++) message(i)],
        hasMore: false,
      ),
    );
    final resynced = mergeNewestMessagePage(
      MessagePage(
        messages: [
          for (var i = 7; i <= 56; i++)
            message(i, body: i == 55 ? 'Updated 55' : null),
        ],
        hasMore: true,
        nextBeforeRevision: 7,
      ),
      current: loaded.messages,
      hasLoadedOlder: true,
      olderHasMore: loaded.hasMore,
      olderCursor: loaded.nextBeforeRevision,
    );

    expect(resynced.messages.length, 56);
    expect(resynced.messages.map((item) => item.id).toSet().length, 56);
    expect(resynced.messages.first.revision, 1);
    expect(resynced.messages.last.revision, 56);
    expect(resynced.messages[54].body, 'Updated 55');
    expect(resynced.hasMore, isFalse);
    expect(resynced.nextBeforeRevision, isNull);

    final completeNewest = mergeNewestMessagePage(
      MessagePage(messages: [message(56)], hasMore: false),
      current: loaded.messages,
      hasLoadedOlder: true,
      olderHasMore: loaded.hasMore,
      olderCursor: loaded.nextBeforeRevision,
    );
    expect(completeNewest.messages.map((item) => item.revision), [56]);
  });

  test('browser reconnect resyncs an open thread without a page reload', () {
    expect(browserSignals, contains("web.window.addEventListener('online'"));
    expect(surface, contains('browserOnlineSignals().listen('));
    expect(surface, contains('void _resyncAfterReconnect()'));
    expect(surface, contains('unawaited(_replaceMessages())'));
    expect(surface, contains('_scheduleReconnectRetry()'));
  });

  test('each visual message group shows its localized timestamp above', () {
    expect(surface, contains('_inboxTime(context, group.first.createdAt)'));
    expect(surface, contains('textTheme.labelSmall'));
  });

  test('chat bubbles are compact and split by sender side', () {
    expect(surface, contains('MediaQuery.sizeOf(context).width * 0.78'));
    expect(surface, contains('BoxConstraints(maxWidth: bubbleMaxWidth)'));
    expect(
      surface,
      matches(
        RegExp(
          r'group\.first\.mine\s*\?\s*Alignment\.centerRight\s*:\s*Alignment\.centerLeft',
        ),
      ),
    );
    expect(surface, contains('horizontal: 10'));
    expect(surface, contains('vertical: 6'));
  });

  test('sender and time sit together above the message card', () {
    final bubble = surface.substring(
      surface.indexOf('for (final group in groupMessagesForDisplay(messages))'),
      surface.indexOf('for (final pending in _pending)'),
    );
    final sender = bubble.indexOf('group.first.senderName');
    final card = bubble.indexOf('Card(');
    final timestamp = bubble.indexOf(
      '_inboxTime(context, group.first.createdAt)',
    );
    expect(sender, greaterThanOrEqualTo(0));
    expect(sender, lessThan(card));
    expect(timestamp, greaterThan(sender));
    expect(timestamp, lessThan(card));
    expect(bubble, contains('if (message != group.first)'));
    expect(bubble, contains('const SizedBox(height: 6)'));
  });

  test('announcement title appears in the header, not inside its message', () {
    final announcement = surface.substring(
      surface.indexOf("if (widget.thread.type == 'announcement')"),
      surface.indexOf('final bubbleMaxWidth = min('),
    );
    expect(announcement, isNot(contains('widget.thread.subject')));
    expect(surface, contains('title: Text(widget.thread.subject'));
  });

  test('history returns sender identity after checking thread access', () {
    expect(senderMigration, contains('internal.actor_can_access_thread'));
    expect(senderMigration, contains('message.sender_profile_id,'));
    expect(senderMigration, contains('page_limit+1'));
  });

  test('consecutive messages group only within three minutes and by ID', () {
    final start = DateTime.utc(2026, 9, 23, 10);
    ThreadMessage message(int minute, String senderId, {String? name}) =>
        ThreadMessage(
          id: '$minute-$senderId',
          revision: minute + 1,
          state: 'sent',
          createdAt: start.add(Duration(minutes: minute)),
          senderName: name ?? 'Samma namn',
          senderProfileId: senderId,
          mine: false,
        );

    final groups = groupMessagesForDisplay([
      message(0, 'a'),
      message(2, 'a'),
      message(3, 'a'),
      message(4, 'a'),
      message(5, 'b'),
      message(6, 'a'),
    ]);
    expect(groups.map((group) => group.messages.length), [3, 1, 1, 1]);
    expect(groups.first.first.createdAt, start);
    expect(groups.first.last.createdAt, start.add(const Duration(minutes: 3)));
  });

  test('missing sender identity never joins a visual group', () {
    final start = DateTime.utc(2026, 9, 23, 10);
    final rows = [
      for (var i = 0; i < 2; i++)
        ThreadMessage(
          id: '$i',
          revision: i + 1,
          state: 'sent',
          createdAt: start,
          senderName: 'Samma namn',
          mine: false,
        ),
    ];
    expect(groupMessagesForDisplay(rows).length, 2);
  });

  test(
    'stale resync and pagination responses cannot overwrite newer state',
    () {
      expect(surface, contains('MessageHistoryRequestGate()'));
      expect(surface, contains('_historyRequestGate.startLatest()'));
      expect(surface, contains('_historyRequestGate.startOlder()'));
      expect(surface, contains('_historyRequestGate.finishLatest('));
      expect(surface, contains('if (replayOlder) unawaited(_loadOlder())'));
    },
  );

  test('overlapping resync replays the older-page request', () async {
    final gate = MessageHistoryRequestGate();
    final olderResponse = Completer<MessagePage>();
    final latestResponse = Completer<MessagePage>();
    final replayResponse = Completer<MessagePage>();
    final olderGeneration = gate.startOlder();
    final latestGeneration = gate.startLatest();

    final older = olderResponse.future.then((page) {
      if (!gate.isCurrent(olderGeneration)) return false;
      gate.finishOlder();
      return true;
    });
    final latest = latestResponse.future.then((page) {
      if (!gate.isCurrent(latestGeneration)) return false;
      return gate.finishLatest(hasMore: page.hasMore);
    });

    olderResponse.complete(const MessagePage(messages: [], hasMore: false));
    expect(await older, isFalse);
    latestResponse.complete(
      const MessagePage(messages: [], hasMore: true, nextBeforeRevision: 51),
    );
    expect(await latest, isTrue);

    final replayGeneration = gate.startOlder();
    final replay = replayResponse.future.then((page) {
      if (!gate.isCurrent(replayGeneration)) return false;
      gate.finishOlder();
      return page.messages.length == 1;
    });
    replayResponse.complete(
      MessagePage(
        messages: [
          ThreadMessage(
            id: 'older',
            revision: 50,
            state: 'sent',
            createdAt: DateTime.utc(2026, 9, 23),
            senderName: 'Test',
            mine: false,
          ),
        ],
        hasMore: false,
      ),
    );
    expect(await replay, isTrue);
  });

  test('newest page ending history does not replay an older request', () {
    final gate = MessageHistoryRequestGate();
    final olderGeneration = gate.startOlder();
    final latestGeneration = gate.startLatest();
    expect(gate.isCurrent(olderGeneration), isFalse);
    expect(gate.isCurrent(latestGeneration), isTrue);
    expect(gate.finishLatest(hasMore: false), isFalse);
  });
}
