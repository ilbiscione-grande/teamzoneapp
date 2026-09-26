import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827145227_msg03_announcement_read_status.sql',
  ).readAsStringSync();
  final participantHardeningMigration = File(
    'supabase/migrations/20260828103629_msg03_bind_announcement_participants_to_assignments.sql',
  ).readAsStringSync();
  final roleGroupMigration = File(
    'supabase/migrations/20260922043656_msg03_role_group_announcements.sql',
  ).readAsStringSync();
  final roleGroupGrantMigration = File(
    'supabase/migrations/20260922074609_msg03_grant_role_group_announcement_execution.sql',
  ).readAsStringSync();
  final immutableAnnouncementMigration = File(
    'supabase/migrations/20260922131951_msg03_close_announcement_after_initial_message.sql',
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
  final gateway = File(
    'supabase/functions/critical-flow-command/index.ts',
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

  test('announcement targets role groups and creates its message atomically', () {
    expect(
      roleGroupMigration,
      contains('create_role_group_announcement_for_actor'),
    );
    expect(roleGroupMigration, contains("'player', 'leader', 'guardian'"));
    expect(roleGroupMigration, contains("'club.messaging.manage'"));
    expect(
      roleGroupMigration,
      contains('internal.messaging_relationship_allowed'),
    );
    expect(
      roleGroupMigration,
      contains('internal.create_announcement_for_actor'),
    );
    expect(roleGroupMigration, contains('internal.send_message_for_actor'));
    expect(services, contains("operation: 'create_role_group_announcement'"));
    expect(services, contains('including FunctionException'));
    expect(services, contains(".rpc<String>('create_role_group_announcement'"));
    expect(gateway, contains('create_role_group_announcement: "messaging"'));
    expect(
      roleGroupGrantMigration,
      contains(
        'grant execute on function internal.create_role_group_announcement_for_actor',
      ),
    );
    expect(roleGroupGrantMigration, contains('to authenticated'));
    expect(surface, contains("('all', 'Alla')"));
    expect(surface, contains("feature('Meddelande')"));
    expect(surface, contains("message.contains('no_recipients')"));
    expect(surface, contains('Serverkod: {code}'));
    expect(surface, contains('canCreateAnnouncement'));
    expect(surface, contains("rolePackage == 'leader'"));
    expect(surface, contains("thread.type == 'announcement'"));
    expect(surface, contains('Behöver din uppmärksamhet'));
    expect(surface, contains('Arkiverade anslag'));
    expect(surface, contains("strings.feature('Information')"));
    expect(surface, contains('SelectableText('));
    expect(surface, contains("canSend: draft.type != 'announcement'"));
    expect(
      immutableAnnouncementMigration,
      contains(
        "thread_row.thread_type = 'announcement' and thread_row.revision >= 2",
      ),
    );
    expect(
      immutableAnnouncementMigration,
      contains("message = 'announcement_closed'"),
    );
    expect(surface, isNot(contains('participant_profile_ids')));
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
    expect(
      surface,
      contains(
        "if (!widget.thread.canSend && widget.thread.type != 'announcement')",
      ),
    );
    expect(
      surface,
      contains(
        "if (widget.thread.canSend && widget.thread.type != 'announcement')",
      ),
    );
    expect(surface, contains("value: 'announcement'"));
  });
}
