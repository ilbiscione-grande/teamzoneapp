import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827144006_msg02_relationship_messaging.sql',
  ).readAsStringSync();
  final previousMessagingMigration = File(
    'supabase/migrations/20260815073726_s06_enforce_cross_club_boundary.sql',
  ).readAsStringSync();
  final idempotentDecisionMigration = File(
    'supabase/migrations/20260822120244_xobs_command_idempotency.sql',
  ).readAsStringSync();
  final acceptanceHardeningMigration = File(
    'supabase/migrations/20260828112000_msg02_revalidate_cross_club_acceptance.sql',
  ).readAsStringSync();
  final functionaryCapabilityMigration = File(
    'supabase/migrations/20260831045035_msg02_explicit_functionary_messaging_capability.sql',
  ).readAsStringSync();
  final directThreadReuseMigration = File(
    'supabase/migrations/20260831151938_msg02_reuse_existing_direct_threads.sql',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/messaging/inbox_surface.dart',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/messaging/messaging_services.dart',
  ).readAsStringSync();

  test('one relationship rule gates search, create, add and send', () {
    expect(migration, contains('messaging_relationship_allowed'));
    expect(migration, contains('resolve_allowed_recipients_for_actor'));
    expect(migration, contains('create_thread_for_actor'));
    expect(migration, contains('add_thread_participants_for_actor'));
    expect(migration, contains('actor_can_access_thread'));
    expect(
      RegExp('messaging_relationship_allowed').allMatches(migration).length,
      greaterThanOrEqualTo(5),
    );
  });

  test('player direct contact excludes other players by default', () {
    expect(
      migration,
      contains(
        "actor_assignment.role_package='player' and target_assignment.role_package in('leader','guardian')",
      ),
    );
    expect(
      migration,
      isNot(
        contains(
          "actor_assignment.role_package='player' and target_assignment.role_package='player'",
        ),
      ),
    );
  });

  test('club functionary needs an explicit broad messaging capability', () {
    expect(
      functionaryCapabilityMigration,
      contains("grant_row.capability = 'club.messaging.manage'"),
    );
    expect(
      functionaryCapabilityMigration,
      contains("actor_assignment.role_package = 'club_functionary'"),
    );
    expect(
      functionaryCapabilityMigration,
      isNot(
        contains("actor_assignment.role_package in ('leader','club_functionary')"),
      ),
    );
    expect(
      functionaryCapabilityMigration,
      contains('internal.messaging_relationship_allowed('),
    );
    expect(
      functionaryCapabilityMigration,
      contains('revoke all on function internal.messaging_relationship_allowed'),
    );
  });

  test('cross-club leader contact remains accepted and rate limited', () {
    expect(previousMessagingMigration, contains('request_cross_club_contact'));
    expect(idempotentDecisionMigration, contains('decide_contact_request'));
    expect(idempotentDecisionMigration, contains("decision = 'accepted'"));
    expect(previousMessagingMigration, contains("interval '24 hours'"));
    expect(previousMessagingMigration, contains("interval '30 days'"));
  });

  test('cross-club acceptance revalidates the current relationship', () {
    expect(
      acceptanceHardeningMigration,
      contains('internal.actor_is_verified_adult_leader(actor_id)'),
    );
    expect(
      acceptanceHardeningMigration,
      contains(
        'internal.actor_is_verified_adult_leader(request_row.requester_profile_id)',
      ),
    );
    expect(
      acceptanceHardeningMigration,
      contains(
        'internal.actors_share_active_club(actor_id, request_row.requester_profile_id)',
      ),
    );
    expect(
      acceptanceHardeningMigration,
      contains("block.control_type = 'block'"),
    );
    expect(acceptanceHardeningMigration, contains("message.contact.decide.v1"));
    expect(
      acceptanceHardeningMigration,
      contains("message = 'relationship_changed'"),
    );
    expect(
      acceptanceHardeningMigration,
      contains('assignment.starts_at <= now()'),
    );
    expect(
      acceptanceHardeningMigration,
      contains('(assignment.ends_at is null or assignment.ends_at > now())'),
    );
  });

  test('client supports direct, group and server-validated additions', () {
    expect(surface, contains("_type = 'direct'"));
    expect(surface, contains("value: 'group'"));
    expect(surface, contains("strings.feature('Gruppnamn')"));
    expect(surface, contains('_ParticipantPickerDialog'));
    expect(services, contains("operation: 'add_thread_participants'"));
  });

  test('direct compose atomically reuses the existing profile-pair thread', () {
    expect(
      directThreadReuseMigration,
      contains('pg_catalog.pg_advisory_xact_lock'),
    );
    expect(
      directThreadReuseMigration,
      contains("thread.thread_type = 'direct'"),
    );
    expect(
      directThreadReuseMigration,
      contains('count(distinct participant.profile_id) = 2'),
    );
    expect(
      directThreadReuseMigration,
      contains("'message.thread.reused.v1'"),
    );
    expect(
      directThreadReuseMigration,
      contains("jsonb_build_object('thread_id', thread_id, 'reused', true)"),
    );
  });
}
