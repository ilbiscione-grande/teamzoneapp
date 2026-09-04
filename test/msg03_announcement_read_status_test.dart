import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827145227_msg03_announcement_read_status.sql',
  ).readAsStringSync();
  final participantHardeningMigration = File(
    'supabase/migrations/20260828103629_msg03_bind_announcement_participants_to_assignments.sql',
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

  test('announcement has a separate per-participant read model', () {
    expect(migration, contains('create table core.announcement_reads'));
    expect(migration, contains('primary key(thread_id,profile_id)'));
    expect(migration, contains("thread.thread_type='announcement'"));
    expect(migration, contains('announcement_read.through_revision'));
    expect(migration, contains("if thread_kind='announcement' then"));
  });

  test('announcement is one-way and limited to active leaders', () {
    expect(migration, contains('create_announcement_for_actor'));
    expect(
      migration,
      contains("assignment.role_package in('leader','club_functionary')"),
    );
    expect(
      migration,
      contains("participant.participant_role in('creator','moderator')"),
    );
    expect(migration, contains("thread_row.thread_type='announcement'"));
  });

  test('announcement participants bind to current assignments', () {
    expect(
      participantHardeningMigration,
      contains('join core.assignments assignment'),
    );
    expect(
      participantHardeningMigration,
      contains('assignment.starts_at <= now()'),
    );
    expect(
      participantHardeningMigration,
      contains('(assignment.ends_at is null or assignment.ends_at > now())'),
    );
    expect(
      participantHardeningMigration,
      contains(
        '(context_row.team_id is null or assignment.team_id = context_row.team_id)',
      ),
    );
    expect(
      participantHardeningMigration,
      contains('materialized_count <> recipient_count'),
    );
    expect(
      participantHardeningMigration,
      contains("message = 'relationship_changed'"),
    );
  });

  test('mark all routes messages and announcements atomically', () {
    expect(migration, contains('mark_all_threads_read_for_actor'));
    expect(migration, contains('message.all.read.v1'));
    expect(migration, contains('insert into core.message_reads'));
    expect(migration, contains('insert into core.announcement_reads'));
    expect(services, contains("operation: 'mark_all_threads_read'"));
    expect(surface, contains("feature('Markera alla som lästa')"));
  });

  test('recipient UI cannot render an announcement composer', () {
    expect(models, contains('final bool canSend'));
    expect(models, contains("json['can_send'] as bool? ?? true"));
    expect(surface, contains('if (!widget.thread.canSend)'));
    expect(surface, contains('if (widget.thread.canSend)'));
    expect(surface, contains("value: 'announcement'"));
  });
}
