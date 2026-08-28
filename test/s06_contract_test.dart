import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';

void main() {
  final root = Directory.current.path;
  String migration(String name) =>
      File('$root/supabase/migrations/$name').readAsStringSync();

  test('S06 uses one recipient helper for discovery and create validation', () {
    final sql = migration('20260808110033_s06_messaging_foundation.sql');
    expect(sql, contains('resolve_allowed_recipients_for_actor'));
    expect(
      sql,
      contains(
        "join internal.resolve_allowed_recipients_for_actor(target_context_id,null)",
      ),
    );
    expect(sql, contains('actor_can_access_thread(target_thread_id,true)'));
    expect(
      sql,
      contains("raise insufficient_privilege using message='not_found'"),
    );
  });

  test('S06 private files and realtime never broadcast message bodies', () {
    final sql = migration(
      '20260808141138_s06_private_files_retention_realtime.sql',
    );
    expect(sql, contains("values('message-files','message-files',false"));
    expect(sql, contains("'message:thread:'||new.thread_id::text,true"));
    expect(
      sql,
      contains(
        "jsonb_build_object('thread_id',new.thread_id,'revision',new.revision)",
      ),
    );
    expect(sql, contains("storage.allow_any_operation"));
    expect(sql, contains("staged_file_ids uuid[]"));
  });

  test('S06 safeguarding defaults player direct and cross-club closed', () {
    final foundation = migration('20260808110033_s06_messaging_foundation.sql');
    final moderation = migration(
      '20260808144116_s06_cross_club_moderation.sql',
    );
    expect(
      foundation,
      contains(
        "actor_context.role_package='player' and assignment.role_package in ('leader','guardian')",
      ),
    );
    expect(moderation, contains('actor_is_verified_adult_leader'));
    expect(moderation, contains("interval '14 days'"));
    expect(
      moderation,
      contains("control_type='block' and block.state='active'"),
    );
  });

  test(
    'S06 closure fixes preserve legal hold and enforce tenant boundaries',
    () {
      final retention = migration(
        '20260815073526_s06_preserve_legal_hold_retention.sql',
      );
      final crossClub = migration(
        '20260815073726_s06_enforce_cross_club_boundary.sql',
      );
      final recall = migration(
        '20260815073924_s06_fix_recall_thread_revision.sql',
      );
      expect(retention, contains("thread.state<>'legal_hold'"));
      expect(
        crossClub,
        contains('actors_share_active_club(actor_id,target_leader_id)'),
      );
      expect(recall, contains('next_thread_revision'));
      expect(recall, contains("message.message.recalled.v1"));
      expect(recall, contains("message.message.reported.v1"));
    },
  );

  test('message projections parse explicit state without backend leakage', () {
    final message = ThreadMessage.fromJson({
      'id': 'm',
      'revision': 2,
      'state': 'recalled',
      'body': null,
      'created_at': '2026-08-08T00:00:00Z',
      'sender_name': 'Leader',
      'mine': false,
    });
    expect(message.state, 'recalled');
    expect(message.body, isNull);
  });
}
