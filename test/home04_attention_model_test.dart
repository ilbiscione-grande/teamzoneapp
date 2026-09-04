import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827194321_home04_attention_model.sql',
  ).readAsStringSync();
  final overviewModels = File(
    'lib/src/features/overview/overview_models.dart',
  ).readAsStringSync();
  final overviewSurface = File(
    'lib/src/features/overview/overview_surface.dart',
  ).readAsStringSync();
  final messagingModels = File(
    'lib/src/features/messaging/messaging_models.dart',
  ).readAsStringSync();

  test('home and notification center share canonical priority levels', () {
    expect(migration, contains('internal.attention_priority'));
    expect(migration, contains("then 10"));
    expect(migration, contains("then 20"));
    expect(migration, contains("then 30"));
    expect(migration, contains("then 40"));
    expect(overviewModels, contains('int homeAttentionPriority'));
    expect(messagingModels, contains("priority: attentionPriority(category)"));
  });

  test('domain notifications deduplicate by canonical key', () {
    expect(migration, contains('internal.notification_attention_key'));
    expect(
      migration,
      contains('distinct on(internal.notification_attention_key(outbox))'),
    );
    expect(migration, contains("'canonical_key'"));
    expect(
      migration,
      contains(
        'internal.notification_attention_key(outbox)=internal.notification_attention_key(target_row)',
      ),
    );
    expect(overviewModels, contains('uniqueHomeAttention'));
  });

  test('next event is not repeated when already represented', () {
    expect(
      overviewSurface,
      contains("canonicalKey: (callup) => 'event:\${callup.eventId}'"),
    );
    expect(
      overviewSurface,
      contains('callup.eventId == widget.value.nextEvent?.id'),
    );
    expect(overviewSurface, contains('event.id == value.nextEvent?.id'));
  });

  test('screen density changes while data and actions stay identical', () {
    expect(overviewSurface, contains('MediaQuery.sizeOf(context).width'));
    expect(overviewSurface, contains('AppBreakpoints.tablet'));
    expect(overviewSurface, contains('final content = !wide'));
    expect(
      overviewSurface,
      contains('crossAxisAlignment: CrossAxisAlignment.start'),
    );
  });

  test('notification client defensively deduplicates and reprioritizes', () {
    final center = NotificationCenter.fromJson({
      'unread_count': 2,
      'items': [
        {
          'id': 'older',
          'event_type': 'callup.old',
          'category': 'callup',
          'title': 'Äldre',
          'preview': 'Äldre',
          'deep_link': '/calendar?event=1',
          'unread': true,
          'canonical_key': 'callup:1',
          'priority': 999,
          'created_at': '2026-08-28T08:00:00Z',
        },
        {
          'id': 'newer',
          'event_type': 'callup.new',
          'category': 'callup',
          'title': 'Nyare',
          'preview': 'Nyare',
          'deep_link': '/calendar?event=1',
          'unread': true,
          'canonical_key': 'callup:1',
          'priority': 999,
          'created_at': '2026-08-28T09:00:00Z',
        },
        {
          'id': 'urgent',
          'event_type': 'callup.cancelled',
          'category': 'callup_cancelled',
          'title': 'Inställd',
          'preview': 'Inställd',
          'deep_link': '/calendar?event=2',
          'unread': true,
          'canonical_key': 'callup:2',
          'priority': 999,
          'created_at': '2026-08-28T07:00:00Z',
        },
      ],
    });

    expect(center.items.map((item) => item.id), ['urgent', 'newer']);
    expect(center.items.map((item) => item.priority), [10, 20]);
  });
}
