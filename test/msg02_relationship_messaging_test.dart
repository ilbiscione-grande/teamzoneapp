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
  final globalInboxMigration = File(
    'supabase/migrations/20260920224500_msg02_global_inbox_context_labels.sql',
  ).readAsStringSync();
  final crossClubDirectoryMigration = File(
    'supabase/migrations/20260921192106_msg02_search_cross_club_directory.sql',
  ).readAsStringSync();
  final descriptiveRequestsMigration = File(
    'supabase/migrations/20260921200612_msg02_descriptive_contact_requests.sql',
  ).readAsStringSync();
  final clubScopeVisibilityMigration = File(
    'supabase/migrations/20260921202524_msg02_show_club_scoped_threads_in_team_contexts.sql',
  ).readAsStringSync();
  final counterpartyNameMigration = File(
    'supabase/migrations/20260921203502_msg02_direct_thread_counterparty_name_fallback.sql',
  ).readAsStringSync();
  final counterpartyAliasMigration = File(
    'supabase/migrations/20260921205711_msg02_restore_counterparty_display_name_alias.sql',
  ).readAsStringSync();
  final requestFirstMessageMigration = File(
    'supabase/migrations/20260921210307_msg02_contact_request_becomes_first_message.sql',
  ).readAsStringSync();
  final crossClubFixture = File(
    'supabase/migrations/20260921081500_msg02_cross_club_verification_fixture.sql',
  ).readAsStringSync();
  final crossClubVerificationFixture = File(
    'supabase/migrations/20260921185236_msg02_cross_club_leader_verification_fixture.sql',
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
        contains(
          "actor_assignment.role_package in ('leader','club_functionary')",
        ),
      ),
    );
    expect(
      functionaryCapabilityMigration,
      contains('internal.messaging_relationship_allowed('),
    );
    expect(
      functionaryCapabilityMigration,
      contains(
        'revoke all on function internal.messaging_relationship_allowed',
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

  test('hosted leader application approval is exact and fails closed', () {
    expect(
      crossClubFixture,
      contains("lower(account.email) = 'coach.emilson+tzexternal@gmail.com'"),
    );
    expect(crossClubFixture, contains("application.status = 'pending'"));
    expect(crossClubFixture, contains('matching_applications <> 1'));
    expect(
      crossClubFixture,
      contains('internal.decide_membership_application_v2('),
    );
    expect(
      crossClubFixture,
      contains("lower(club.name) = lower('Genomfångsklubben')"),
    );
    expect(
      crossClubFixture,
      contains(
        "grant_row.capability in ('club.memberships.manage','team.roster.manage')",
      ),
    );
    expect(
      crossClubFixture,
      contains("perform set_config('request.jwt.claim.sub'"),
    );
    expect(crossClubFixture, contains("'approved',\n    'leader'"));
  });

  test('hosted cross-club leaders are exact, verified and disjoint', () {
    expect(
      crossClubVerificationFixture,
      contains("lower(account.email) = 'coach.emilson+tzleader@gmail.com'"),
    );
    expect(
      crossClubVerificationFixture,
      contains("lower(account.email) = 'coach.emilson+tzexternal@gmail.com'"),
    );
    expect(
      crossClubVerificationFixture,
      contains("lower(club.name) = lower('Thomas klubb')"),
    );
    expect(
      crossClubVerificationFixture,
      contains("lower(club.name) = lower('Genomfångsklubben')"),
    );
    expect(
      crossClubVerificationFixture,
      contains('internal.actors_share_active_club(requester_id, target_id)'),
    );
    expect(
      crossClubVerificationFixture,
      contains(
        "raise exception 'msg02_cross_club_fixture_actors_share_active_club'",
      ),
    );
    expect(
      crossClubVerificationFixture,
      contains('on conflict (profile_id) do update'),
    );
  });

  test('cross-club directory searches club, team and leader', () {
    expect(crossClubDirectoryMigration, contains('normalized_search'));
    expect(
      crossClubDirectoryMigration,
      contains("club.name ilike '%' || normalized_search || '%'"),
    );
    expect(
      crossClubDirectoryMigration,
      contains("team.name ilike '%' || normalized_search || '%'"),
    );
    expect(
      crossClubDirectoryMigration,
      contains('internal.actors_share_active_club(auth.uid(), profile.id)'),
    );
    expect(surface, contains("'Klubb, lag eller ledare'"));
    expect(surface, contains('_leaderDirectoryEntries(context, leaders)'));
    expect(surface, contains('Icons.verified_user_outlined'));
  });

  test('contact requests explain sender, affiliation and consequence', () {
    expect(descriptiveRequestsMigration, contains('requester_affiliation'));
    expect(
      descriptiveRequestsMigration,
      contains("assignment.role_package = 'leader'"),
    );
    expect(surface, contains('_contactReasonLabel(request.reasonCode)'));
    expect(surface, contains("contactReasonLabel('club_business')"));
    expect(surface, contains('request.requesterAffiliation'));
    expect(
      surface,
      contains('Om du accepterar kan ni starta en privat konversation'),
    );
    expect(surface, contains('formatShortDate(request.expiresAt.toLocal())'));
  });

  test('accepted club-scoped thread is visible and opened', () {
    expect(
      clubScopeVisibilityMigration,
      contains('scope.team_id IS NULL OR context.team_id = scope.team_id'),
    );
    expect(services, contains('Future<String?> decideRequest'));
    expect(services, contains("result['thread_id'] as String?"));
    expect(surface, contains('acceptedThreadId = await widget.messaging'));
    expect(surface, contains("type: 'cross_club_direct'"));
  });

  test('direct thread title identifies the other participant', () {
    expect(
      counterpartyNameMigration,
      contains("lower(account.email) = 'coach.emilson+tzleader@gmail.com'"),
    );
    expect(counterpartyNameMigration, contains("'Thomas-ledare'"));
    expect(
      counterpartyNameMigration,
      contains('other_club_person.display_name'),
    );
    expect(
      counterpartyNameMigration,
      contains('other_participant.club_person_id'),
    );
    expect(counterpartyNameMigration, contains("'Deltagare'"));
    expect(counterpartyAliasMigration, contains('as display_name'));
  });

  test('accepted contact request becomes the first chat message', () {
    expect(
      requestFirstMessageMigration,
      contains('internal.seed_contact_request_first_message'),
    );
    expect(requestFirstMessageMigration, contains('request_row.request_text'));
    expect(requestFirstMessageMigration, contains('request_row.reason_code'));
    expect(requestFirstMessageMigration, contains('audit.message_versions'));
    expect(requestFirstMessageMigration, contains('internal.domain_outbox'));
    expect(
      requestFirstMessageMigration,
      contains('internal.notification_outbox'),
    );
    expect(
      requestFirstMessageMigration,
      contains('not exists (\n        select 1 from core.messages'),
    );
    expect(
      requestFirstMessageMigration,
      contains("thread.thread_type = 'cross_club_direct'"),
    );
  });

  test('client supports direct, group and server-validated additions', () {
    // The thread type follows the number of chosen recipients.
    expect(
      surface,
      matches(RegExp(r"_selected\.length > 1\s*\?\s*'group'\s*:\s*'direct'")),
    );
    expect(surface, contains("strings.feature('Gruppnamn')"));
    expect(surface, contains('_ParticipantPickerDialog'));
    expect(services, contains("operation: 'add_thread_participants'"));
    expect(surface, contains("strings.feature('Välj minst en mottagare.')"));
    expect(surface, contains("'Ange ett gruppnamn.'"));
    expect(surface, contains('strings.selectedRecipients(_selected.length)'));
    expect(surface, contains('onPressed: _submit'));
    expect(surface, contains('DropdownButtonFormField<String>'));
    expect(surface, contains("String reason = 'match'"));
    expect(surface, contains("'Anledning till kontakt'"));
    expect(surface, contains("'Ytterligare information (valfritt)'"));
    expect(surface, contains("value: 'match'"));
    expect(surface, contains("value: 'event'"));
    expect(surface, contains("value: 'transfer'"));
    expect(surface, contains("value: 'club_business'"));
    expect(surface, contains("value: 'other'"));
    expect(surface, contains('request.reason'));
    expect(surface, contains('request.message'));
    expect(
      services,
      matches(
        RegExp(
          "operation: 'add_thread_participants',[\\s\\S]*?'thread_id': threadId,[\\s\\S]*?'profile_ids': profileIds,",
        ),
      ),
    );
    expect(
      services,
      isNot(
        matches(
          RegExp(
            "operation: 'add_thread_participants',[\\s\\S]*?'thread_id': threadId,[\\s\\S]*?'participant_profile_ids': profileIds,",
          ),
        ),
      ),
    );
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
    expect(directThreadReuseMigration, contains("'message.thread.reused.v1'"));
    expect(
      directThreadReuseMigration,
      contains(
        "jsonb_build_object('thread_id', function_body.thread_id, 'reused', true)",
      ),
    );
  });

  test(
    'personal inbox spans all active contexts with server-derived labels',
    () {
      expect(surface, contains('required this.contexts'));
      expect(surface, contains('widget.messaging.listThreads(_contextIds)'));
      expect(
        surface,
        contains('thread.scopeLabels.contains(_activeScopeLabel)'),
      );
      expect(globalInboxMigration, contains("'schema_version', 4"));
      expect(
        globalInboxMigration,
        contains('context.context_id = any(target_context_ids)'),
      );
      expect(globalInboxMigration, contains('scope_labels'));
      expect(
        globalInboxMigration,
        contains("context.team_name || ' · ' || context.club_name"),
      );
      expect(
        globalInboxMigration,
        contains('internal.actor_can_access_thread(thread.id, false)'),
      );
      // Conversations are grouped per club, then per team inside a club.
      expect(surface, contains('_groupByClub(conversations)'));
      expect(surface, contains('_groupThreads('));
      expect(surface, contains("thread.type != 'announcement'"));
      expect(surface, contains("title: 'Flera lag'"));
      expect(surface, contains("title: 'Övriga konversationer'"));
      expect(surface, contains('count: group.threads.length'));
      expect(surface, contains('_InboxClubHeader('));
    },
  );
}
