import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827160606_msg08_notification_center.sql',
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

  test('center has account-synced unread, read and dismiss state', () {
    expect(migration, contains('core.notification_receipts'));
    expect(migration, contains("state in('read','dismissed')"));
    expect(migration, contains('recipient_profile_id=actor_id'));
    expect(migration, contains('mark_all_notifications_read_for_actor'));
    expect(models, contains('class NotificationCenter'));
    expect(surface, contains('isLabelVisible: _notificationUnread > 0'));
  });

  test('projection is data minimized and deep links are server calculated', () {
    expect(migration, contains('internal.notification_title'));
    expect(migration, contains('internal.notification_preview'));
    expect(migration, contains("'/inbox?thread='"));
    expect(migration, contains("'/calendar?event='"));
    expect(migration, isNot(contains("payload_ref->>'body'")));
    expect(surface, contains('widget.onNavigate(item.deepLink)'));
    expect(services, contains("operation: 'set_notification_state'"));
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
}
