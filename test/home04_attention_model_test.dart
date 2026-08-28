import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    expect(messagingModels, contains("json['priority']"));
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
    expect(overviewSurface, contains('if (!wide) {'));
    expect(overviewSurface, contains('return Row('));
  });
}
