import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827151434_msg05_notification_preferences_pin_redaction.sql',
  ).readAsStringSync();
  final gateway = File(
    'supabase/functions/critical-flow-command/index.ts',
  ).readAsStringSync();
  final worker = File(
    'supabase/functions/notification-worker/index.ts',
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

  test('optional messaging push is explicit and fail closed', () {
    expect(migration, contains("'push_enabled',coalesce"));
    expect(migration, contains("'message.message.sent.v1','push',new_enabled"));
    expect(
      migration,
      contains('or not exists(select 1 from core.notification_preferences'),
    );
    expect(migration, contains("last_error_code='preference_or_mute'"));
    expect(services, contains("operation: 'set_messaging_push'"));
    expect(surface, contains("feature('Frivilliga pushnotiser')"));
  });

  test('pin is account synced and visible in inbox', () {
    expect(migration, contains('create table core.thread_pins'));
    expect(migration, contains('primary key(thread_id,profile_id)'));
    expect(migration, contains('pins_inbox_invalidation'));
    expect(migration, contains('coalesce(pin.pinned,false)pinned'));
    expect(models, contains('final bool pinned'));
    expect(services, contains("operation: 'set_thread_pin'"));
    expect(surface, contains("('pinned', 'Fästa')"));
  });

  test('push payload and logs never contain message body', () {
    expect(migration, contains('sanitize_messaging_notification_payload'));
    expect(migration, contains("'preview_key','new_message'"));
    expect(migration, isNot(contains("'body',new.payload_ref")));
    expect(worker, contains('without logging payloads'));
    expect(worker, isNot(contains('console.log(item)')));
  });

  test('messaging commands are allowlisted by the measured gateway', () {
    for (final operation in [
      'add_thread_participants',
      'create_announcement',
      'mark_all_threads_read',
      'set_thread_pin',
      'set_messaging_push',
    ]) {
      expect(gateway, contains('$operation: "messaging"'));
    }
  });

  test('preference UX prevents duplicate and stale toggles', () {
    expect(surface, contains('bool _settingsPending = false'));
    expect(surface, contains('if (_settingsPending) return'));
    expect(
      surface,
      contains('onPressed: _settingsPending ? null : _showMessagingSettings'),
    );
    expect(surface, contains('final targetMuted = !_muted'));
    expect(surface, contains('_muted = targetMuted'));
    expect(surface, contains('final targetPinned = !_pinned'));
    expect(surface, contains('_pinned = targetPinned'));
    expect(surface, contains("feature('Slå på notiser')"));
  });
}
