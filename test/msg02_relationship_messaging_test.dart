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

  test('cross-club leader contact remains accepted and rate limited', () {
    expect(previousMessagingMigration, contains('request_cross_club_contact'));
    expect(idempotentDecisionMigration, contains('decide_contact_request'));
    expect(idempotentDecisionMigration, contains("decision = 'accepted'"));
    expect(previousMessagingMigration, contains("interval '24 hours'"));
    expect(previousMessagingMigration, contains("interval '30 days'"));
  });

  test('client supports direct, group and server-validated additions', () {
    expect(surface, contains("_type = 'direct'"));
    expect(surface, contains("value: 'group'"));
    expect(surface, contains("strings.feature('Gruppnamn')"));
    expect(surface, contains('_ParticipantPickerDialog'));
    expect(services, contains("operation: 'add_thread_participants'"));
  });
}
