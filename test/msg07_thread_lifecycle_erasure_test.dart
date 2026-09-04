import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827155531_msg07_thread_lifecycle_erasure.sql',
  ).readAsStringSync();
  final applicationHardeningMigration = File(
    'supabase/migrations/20260828115514_msg07_dual_control_erasure_application.sql',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/messaging/messaging_services.dart',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/messaging/inbox_surface.dart',
  ).readAsStringSync();

  test('personal hide and voluntary leave preserve shared history', () {
    expect(migration, contains('core.thread_personal_visibility'));
    expect(
      migration,
      contains("thread_type not in('group','direct','cross_club_direct')"),
    );
    expect(migration, contains("set state='left',left_at=now()"));
    expect(migration, isNot(contains('delete from core.messages')));
    expect(services, contains("operation: 'set_thread_visibility'"));
    expect(services, contains("operation: 'leave_thread'"));
    expect(surface, contains("feature('Dölj för mig')"));
    expect(surface, contains("feature('Lämna konversation')"));
  });

  test('closing is capability checked and never erases history', () {
    expect(migration, contains("'message.moderate'"));
    expect(migration, contains("set state='closed',closed_at=now()"));
    expect(migration, contains("thread_type not in('group','announcement')"));
    expect(surface, contains("feature('Stäng för nya meddelanden')"));
  });

  test('global erasure has independent approval and service application', () {
    expect(migration, contains('approved_by<>initiated_by'));
    expect(migration, contains('separate_approver_required'));
    expect(
      migration,
      contains("current_user not in('service_role','postgres')"),
    );
    expect(migration, contains("'teamzone_review'"));
    expect(migration, contains("thread_row.thread_type='cross_club_direct'"));
  });

  test('ordinary erasure is exactly dual control and replay safe', () {
    expect(
      applicationHardeningMigration,
      contains("if request_row.state = 'completed' then"),
    );
    expect(
      applicationHardeningMigration,
      contains('reviewer_profile_id is distinct from request_row.approved_by'),
    );
    expect(
      applicationHardeningMigration,
      contains("message = 'approved_reviewer_required'"),
    );
    expect(
      applicationHardeningMigration,
      contains("message = 'independent_teamzone_reviewer_required'"),
    );
    expect(
      applicationHardeningMigration,
      contains(
        "when request_row.requires_teamzone_review then 'teamzone_review'",
      ),
    );
    expect(applicationHardeningMigration, contains("else 'dual_control'"));
  });

  test('neutral tombstones preserve references and ordering', () {
    expect(
      migration,
      contains("body='Meddelandet är borttaget',state='moderated'"),
    );
    expect(
      migration,
      contains('reply_to_message_id uuid references core.messages(id)'),
    );
    expect(migration, contains("'tombstone_preserves_ordering',true"));
    expect(migration, isNot(contains('delete from core.message_reads')));
    expect(
      migration,
      isNot(contains('delete from internal.notification_outbox')),
    );
  });
}
