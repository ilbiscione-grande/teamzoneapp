import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827150144_msg04_message_history_cursor.sql',
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

  test('thread subscription resyncs and history merge deduplicates', () {
    expect(services, contains("'message:thread:\$threadId'"));
    expect(services, contains('status == RealtimeSubscribeStatus.subscribed'));
    expect(surface, contains('const Duration(milliseconds: 250)'));
    expect(surface, contains('message.id: message'));
    expect(surface, contains('a.revision.compareTo(b.revision)'));
  });
}
