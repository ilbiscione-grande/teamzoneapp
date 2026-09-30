import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827160606_msg08_notification_center.sql',
  ).readAsStringSync();
  final canonicalEventLinkMigration = File(
    'supabase/migrations/20260924143236_msg08_event_notification_deep_link.sql',
  ).readAsStringSync();
  final groupedMessagesMigration = File(
    'supabase/migrations/20260924200408_msg08_group_message_notifications_by_thread.sql',
  ).readAsStringSync();
  final announcementReadMigration = File(
    'supabase/migrations/20260924201443_msg08_announcement_read_cursor_for_grouped_notifications.sql',
  ).readAsStringSync();
  final privatePreviewMigration = File(
    'supabase/migrations/20260924215000_msg08_private_message_notification_preview.sql',
  ).readAsStringSync();
  final inaccessibleMessagesMigration = File(
    'supabase/migrations/20260924224500_msg08_hide_inaccessible_message_notifications.sql',
  ).readAsStringSync();
  final models = File(
    'lib/src/features/messaging/messaging_models.dart',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/messaging/messaging_services.dart',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/messaging/inbox_surface.dart',
  ).readAsStringSync();
  final shell = File('lib/src/app/product_shell.dart').readAsStringSync();

  test('center has account-synced unread, read and dismiss state', () {
    expect(migration, contains('core.notification_receipts'));
    expect(migration, contains("state in('read','dismissed')"));
    expect(migration, contains('recipient_profile_id=actor_id'));
    expect(migration, contains('mark_all_notifications_read_for_actor'));
    expect(models, contains('class NotificationCenter'));
    expect(surface, contains('isLabelVisible: _notificationUnread > 0'));
  });

  test('message attention groups by thread and follows the read cursor', () {
    expect(groupedMessagesMigration, contains("'message_thread:'"));
    expect(
      groupedMessagesMigration,
      contains('message.revision>coalesce(message_read.through_revision,0)'),
    );
    expect(
      groupedMessagesMigration,
      contains('message_reads_center_invalidation_advance'),
    );
    expect(
      announcementReadMigration,
      contains("thread.thread_type='announcement'"),
    );
    expect(
      announcementReadMigration,
      contains('announcement_read.through_revision'),
    );
    expect(
      announcementReadMigration,
      contains('announcement_reads_center_invalidation_advance'),
    );
    expect(groupedMessagesMigration, contains('message_count'));
    expect(surface, contains('_notificationPreview(item)'));
    final center = NotificationCenter.fromJson({
      'unread_count': 1,
      'items': [
        {
          'id': 'latest',
          'event_type': 'message.message.sent.v1',
          'category': 'message',
          'title': 'Nytt meddelande',
          'preview': 'Öppna inkorgen.',
          'deep_link': '/inbox?thread=thread-1',
          'unread': true,
          'canonical_key': 'message_thread:thread-1',
          'priority': 40,
          'message_count': 3,
          'created_at': '2026-09-24T12:00:00Z',
        },
      ],
    });
    expect(center.unreadCount, 1);
    expect(center.items.single.messageCount, 3);
  });

  test('projection is data minimized and deep links are server calculated', () {
    expect(migration, contains('internal.notification_title'));
    expect(migration, contains('internal.notification_preview'));
    expect(migration, contains("'/inbox?thread='"));
    expect(migration, contains("'/calendar?event='"));
    expect(
      canonicalEventLinkMigration,
      contains("'/calendar/event/'||(outbox.payload_ref->>'event_id')"),
    );
    expect(
      canonicalEventLinkMigration,
      contains("'/calendar/event/'||outbox.aggregate_id::text"),
    );
    expect(
      canonicalEventLinkMigration,
      contains('create or replace function internal.notification_deep_link'),
    );
    expect(migration, isNot(contains("payload_ref->>'body'")));
    expect(surface, contains('widget.onNavigate(item.deepLink)'));
    expect(services, contains("operation: 'set_notification_state'"));
  });

  test('in-app message preview has actor-scoped sender, chat and excerpt', () {
    expect(
      privatePreviewMigration,
      contains('outbox.recipient_profile_id=actor_id'),
    );
    expect(
      privatePreviewMigration,
      contains('internal.actor_can_access_thread(latest_thread.id,false)'),
    );
    expect(privatePreviewMigration, contains("latest_thread.state<>'hidden'"));
    expect(
      privatePreviewMigration,
      contains('not coalesce(visibility.hidden,false)'),
    );
    expect(privatePreviewMigration, contains("latest_message.state='sent'"));
    expect(privatePreviewMigration, contains('sender_name'));
    expect(privatePreviewMigration, contains('chat_name'));
    expect(privatePreviewMigration, contains('message_preview'));
    expect(
      privatePreviewMigration,
      isNot(contains('update internal.notification_outbox')),
    );
    expect(
      privatePreviewMigration,
      isNot(contains('update core.notification_receipts')),
    );
    final item = NotificationItem.fromJson({
      'id': 'notification-1',
      'event_type': 'message.message.sent.v1',
      'category': 'message',
      'title': 'Nytt meddelande',
      'preview': 'Öppna inkorgen.',
      'deep_link': '/inbox?thread=thread-1',
      'unread': true,
      'canonical_key': 'message_thread:thread-1',
      'message_count': 2,
      'created_at': '2026-09-24T12:00:00Z',
      'sender_name': 'Coach Emilson',
      'chat_name': 'F2014 lagchatt',
      'message_preview': 'Vi ses vid planen klockan 18.',
    });
    expect(item.senderName, 'Coach Emilson');
    expect(item.chatName, 'F2014 lagchatt');
    expect(item.messagePreview, 'Vi ses vid planen klockan 18.');
    expect(surface, contains(r'Från ${item.senderName}'));
    expect(surface, contains('_notificationPreview(item)'));
  });

  test('unread message groups exclude threads without current access', () {
    expect(inaccessibleMessagesMigration, contains('source_visibility.hidden'));
    expect(
      inaccessibleMessagesMigration,
      contains('internal.actor_can_access_thread(thread.id,false)'),
    );
    expect(
      inaccessibleMessagesMigration,
      contains("outbox.event_type<>'message.message.sent.v1'"),
    );
    expect(
      inaccessibleMessagesMigration,
      contains('outbox.recipient_profile_id=actor_id'),
    );
  });

  testWidgets('event opened from Inbox closes back to Inbox', (tester) async {
    final inboxBranch = shell
        .split("destination.path == '/inbox'")[1]
        .split("destination.path == '/development'")[0];
    expect(inboxBranch, contains('onNavigate: _navigateFromSurface'));
    expect(shell, contains('_router.push(location)'));
    final router = GoRouter(
      initialLocation: '/inbox',
      routes: [
        GoRoute(path: '/inbox', builder: (_, _) => const Text('Inbox')),
        GoRoute(
          path: '/calendar/event/:eventId',
          builder: (_, _) => const Text('Event'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.push('/calendar/event/event-1');
    await tester.pumpAndSettle();
    expect(find.text('Event'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
  });

  test('Watchpoints and premature Assistant Coach signals are excluded', () {
    expect(migration, contains("not like'%watchpoint%'"));
    expect(migration, contains("not like'%assistant%'"));
    expect(migration, contains("not like'%ac_signal%'"));
    expect(surface.toLowerCase(), isNot(contains('watchpoint')));
  });

  test('private realtime invalidation refreshes the badge', () {
    expect(
      migration,
      contains("'notification:center:'||target_profile_id::text"),
    );
    expect(migration, contains('realtime.messages.extension'));
    expect(services, contains("'notification:center:\$profileId'"));
    expect(surface, contains('watchNotificationInvalidations()'));
  });

  test('an open notification sheet refreshes from the same invalidation', () {
    expect(surface, contains('_refreshOpenNotifications?.call()'));
    expect(surface, contains('generation == sheetRefreshGeneration'));
    expect(surface, contains('setSheetState(() => center = updated)'));
    expect(surface, contains('_refreshOpenNotifications = null'));
  });

  test('dismiss waits for server confirmation and rolls back on failure', () {
    // Swipe and the remove button share one server-confirmed dismiss.
    expect(surface, contains('confirmDismiss: (_) => dismiss(item)'));
    expect(surface, contains('Future<bool> dismiss(NotificationItem item)'));
    expect(surface, contains("await widget.messaging.setNotificationState("));
    expect(surface, contains("'dismissed'"));
    expect(surface, contains('return true;'));
    expect(surface, contains('return false;'));
    expect(surface, contains('onDismissed: (_)'));
  });
}
