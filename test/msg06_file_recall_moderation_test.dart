import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827154559_msg06_file_authorization_moderation.sql',
  ).readAsStringSync();
  final filesMigration = File(
    'supabase/migrations/20260808141138_s06_private_files_retention_realtime.sql',
  ).readAsStringSync();
  final recallMigration = File(
    'supabase/migrations/20260815073924_s06_fix_recall_thread_revision.sql',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/messaging/messaging_services.dart',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/messaging/inbox_surface.dart',
  ).readAsStringSync();

  test('file id is authorized before a short signed URL is created', () {
    expect(migration, contains('authorize_message_file_for_actor'));
    expect(
      migration,
      contains('internal.actor_can_access_thread(file_row.thread_id,false)'),
    );
    expect(migration, contains("'expires_in_seconds',120"));
    expect(
      migration,
      contains('create function internal.list_message_files_for_actor'),
    );
    expect(
      migration,
      contains(
        'returns table(id uuid,message_id uuid,original_name text,mime_type text,size_bytes bigint)',
      ),
    );
    expect(
      filesMigration,
      contains("values('message-files','message-files',false"),
    );
    expect(filesMigration, contains('storage.allow_any_operation'));
    expect(services, contains("rpc<Object?>('authorize_message_file'"));
    expect(services, contains('.createSignedUrl(value['));
    expect(surface, contains('signedFileUrl(widget.file.id)'));
  });

  test('recall creates a tombstone and revisioned retention trail', () {
    expect(recallMigration, contains("interval '15 minutes'"));
    expect(recallMigration, contains("body='[recalled]'"));
    expect(recallMigration, contains("'recalled',actor_id"));
    expect(recallMigration, contains("state='withdrawn'"));
    expect(recallMigration, contains('next_thread_revision'));
  });

  test('report blocks and service moderation is auditable', () {
    expect(
      recallMigration,
      contains(
        "control_type,state)\n values(actor_id,message_row.sender_profile_id,'block','active')",
      ),
    );
    expect(
      migration,
      contains('create table audit.message_moderation_actions'),
    );
    expect(
      migration,
      contains("current_user not in('postgres','service_role')"),
    );
    expect(migration, contains("new_action='hide_message'"));
    expect(migration, contains("body='[moderated]'"));
    expect(migration, contains("new_action='legal_hold'"));
    expect(migration, contains('to service_role'));
  });

  test('client collects a structured safeguarding reason', () {
    for (final reason in [
      'harassment',
      'sexual_content',
      'threat',
      'spam',
      'other',
    ]) {
      expect(surface, contains("('$reason',"));
    }
    expect(surface, contains('reportReason!'));
    expect(
      surface,
      contains("feature('Rapporten blockerar också avsändaren.')"),
    );
  });
}
