import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/membership/membership_models.dart';
import 'package:teamzone_app/src/features/membership/membership_services.dart';

void main() {
  test('approved and future leaders receive explicit baseline grants', () {
    final sql = File(
      'supabase/migrations/20260920172500_auth04_materialize_leader_capability_bundle.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('assignments_materialize_leader_capabilities'));
    expect(sql, contains("'team.roster.view'"));
    expect(sql, contains("'team.roster.manage'"));
    expect(sql, contains("'event.manage'"));
    expect(sql, contains('insert into core.capability_grants'));
    expect(
      sql,
      contains(
        'on conflict(assignment_id, capability, scope_type, scope_id) do nothing',
      ),
    );
    expect(sql, isNot(contains('actor_has_capability')));
  });

  test('AUTH-04 runtime patch disambiguates requested membership role', () {
    final sql = File(
      'supabase/migrations/20260903103734_auth04_fix_membership_request_role_ambiguity.sql',
    ).readAsStringSync();
    expect(sql, contains('#variable_conflict use_column'));
    expect(sql, contains('request_team_membership_for_actor.requested_role'));
  });

  test('AUTH-04 permits review only within a team leader capability scope', () {
    final sql = File(
      'supabase/migrations/20260910175749_auth04_allow_team_leader_membership_review.sql',
    ).readAsStringSync();
    expect(sql, contains("'team.roster.manage'"));
    expect(sql, contains('target_team_id is not null'));
    expect(sql, contains('row_value.team_id'));
  });

  test(
    'AUTH-04 reviewer role override preserves request and audits decision',
    () {
      final sql = File(
        'supabase/migrations/20260910181550_auth04_reviewer_role_override.sql',
      ).readAsStringSync();
      expect(sql, contains('approved_role'));
      expect(sql, contains("'membership.application.role_override.v1'"));
      expect(sql, contains("'requested_role',row_value.requested_role"));
      expect(sql, contains("'approved_role',selected_role"));
      expect(sql, contains("'team.roster.manage'"));
      final surface = File(
        'lib/src/features/roster/roster_surface.dart',
      ).readAsStringSync();
      expect(surface, contains("feature('Godkänn som')"));
      expect(surface, contains('approvedRole: approve ? approvedRole : null'));
    },
  );

  test('membership wire models are strict and expose minimal fields', () {
    final result = ClubTeamSearchResult.fromJson(const {
      'club_id': 'club',
      'club_name': 'Testklubben',
      'club_is_official': true,
      'team_id': 'team',
      'team_name': 'F2012',
    });
    expect(result.clubIsOfficial, isTrue);
    expect(MembershipRole.clubFunctionary.wireName, 'club_functionary');
    final review = MembershipReviewItem.fromJson(const {
      'application_id': 'review',
      'applicant_display_name': 'Ada',
      'team_name': 'F2012',
      'requested_role': 'player',
      'created_at': '2026-08-24T00:00:00Z',
    });
    expect(review.applicantDisplayName, 'Ada');
    expect(
      () => MembershipApplication.fromJson(const {
        'application_id': 'application',
        'club_name': 'Club',
        'team_name': 'Team',
        'requested_role': 'unknown',
        'status': 'pending',
        'created_at': '2026-08-24T00:00:00Z',
      }),
      throwsStateError,
    );
  });

  testWidgets('waiting room searches, labels official club and applies', (
    tester,
  ) async {
    final membership = _MembershipFake();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _WaitingIdentity(),
          membership: membership,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hitta klubb eller lag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'test');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.textContaining('Officiell klubb'), findsOneWidget);
    await tester.tap(find.text('Ansök'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skicka ansökan'));
    await tester.pumpAndSettle();
    expect(membership.appliedTeamId, 'team');
  });

  testWidgets('waiting room exposes the requester support inbox', (
    tester,
  ) async {
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _WaitingIdentity(),
          membership: _MembershipFake(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mina supportärenden'), findsOneWidget);
  });

  for (final admin in [true, false]) {
    testWidgets('support queue sits in the inbox, not the menu '
        '(admin: $admin)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final membership = _MembershipFake()
        ..supportAdmin = admin
        ..supportQueue = [
          ProtectedNameSupportCase(
            id: 'case',
            requesterProfileId: 'requester',
            clubName: 'Skyddad IF',
            teamName: 'P2014',
            status: 'pending',
            message: 'Vi äger namnet.',
            resolutionNote: null,
            revision: 1,
            createdAt: DateTime.utc(2026, 10, 4),
            updatedAt: DateTime.utc(2026, 10, 4),
            unreadCount: 2,
          ),
        ];
      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'audit'),
          locale: const Locale('sv'),
          services: AppServices(
            identity: _CoachIdentity(),
            membership: membership,
            isConfigured: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Supportärenden'), findsNothing);
      expect(find.text('Nyhetsredaktion'), findsNothing);
      expect(find.text('Publika sidor'), findsNothing);

      await tester.tap(find.text('Inbox').first);
      await tester.pumpAndSettle();
      final queue = find.byKey(const Key('inbox-support-queue'));
      if (!admin) {
        expect(queue, findsNothing);
        debugDefaultTargetPlatformOverride = null;
        return;
      }
      expect(queue, findsOneWidget);
      expect(find.text('2 nya meddelanden från användare'), findsOneWidget);
      await tester.tap(queue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inbox-support-queue')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  test('club verification tolerates a deleted requester profile name', () {
    final request = ClubVerificationRequest.fromJson({
      'request_id': 'request',
      'club_id': 'club',
      'club_name': 'Testklubben',
      'requester_name': null,
      'evidence_summary': 'Underlag finns',
      'status': 'approved',
      'created_at': '2026-09-11T14:48:18Z',
      'resolved_at': '2026-09-11T14:51:26Z',
      'decision_reason': 'Kontrollerad',
      'revision': 2,
    });

    expect(request.requesterName, 'Okänd användare');
  });

  testWidgets(
    'repeated application explains that the existing one is pending',
    (tester) async {
      final membership = _MembershipFake()
        ..applications = [
          MembershipApplication(
            id: 'application',
            clubName: 'Testklubben',
            teamName: 'F2012',
            role: MembershipRole.player,
            status: MembershipApplicationStatus.pending,
            createdAt: DateTime.utc(2026, 8, 24),
          ),
        ];
      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'audit'),
          locale: const Locale('sv'),
          services: AppServices(
            identity: _WaitingIdentity(),
            membership: membership,
            isConfigured: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hitta klubb eller lag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'test');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ansök'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skicka ansökan'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Du har redan en väntande ansökan'),
        findsOneWidget,
      );
    },
  );

  testWidgets('verified waiting user creates unofficial club and first team', (
    tester,
  ) async {
    final membership = _MembershipFake();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _WaitingIdentity(),
          membership: membership,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skapa klubb och första lag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Nya Klubben');
    await tester.enterText(find.byType(TextFormField).at(1), 'F2014');
    await tester.tap(find.text('Skapa klubb och lag'));
    await tester.pumpAndSettle();
    expect(membership.createdClubName, 'Nya Klubben');
    expect(membership.createdTeamName, 'F2014');
  });

  testWidgets('protected club name is stopped before creation', (tester) async {
    final membership = _MembershipFake()
      ..nameStatus = ClubNameCheckStatus.reviewRequired;
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _WaitingIdentity(),
          membership: membership,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skapa klubb och första lag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'TeamZone');
    await tester.enterText(find.byType(TextFormField).at(1), 'F2014');
    await tester.tap(find.text('Skapa klubb och lag'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Namnet är skyddat'), findsOneWidget);
    expect(find.text('Kontakta TeamZone'), findsOneWidget);
    expect(membership.createdClubName, isNull);
  });

  testWidgets('protected name support case is prefilled and submitted', (
    tester,
  ) async {
    final membership = _MembershipFake()
      ..nameStatus = ClubNameCheckStatus.reviewRequired;
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _WaitingIdentity(),
          membership: membership,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skapa klubb och första lag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Team-Zone');
    await tester.enterText(find.byType(TextFormField).at(1), 'AUTH06 testlag');
    await tester.tap(find.text('Skapa klubb och lag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kontakta TeamZone'));
    await tester.pumpAndSettle();
    expect(find.text('Team-Zone'), findsOneWidget);
    expect(find.text('AUTH06 testlag'), findsOneWidget);
    await tester.tap(find.text('Skicka ärende'));
    await tester.pumpAndSettle();
    expect(membership.supportClubName, 'Team-Zone');
    expect(membership.supportTeamName, 'AUTH06 testlag');
    expect(membership.supportMessage, contains('Team-Zone'));
    expect(find.textContaining('Ärendet är skickat'), findsOneWidget);
  });

  test('migration freezes enumeration and private command boundary', () {
    final sql = File(
      'supabase/migrations/20260824044909_auth04_membership_applications.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('length(normalized_query) < 3'));
    expect(sql, contains('limit 20'));
    expect(sql, contains('membership_applications_one_pending_target'));
    expect(sql, contains('for update'));
    expect(sql, contains("'membership.application.request.v1'"));
    expect(sql, contains("'membership.application.decide.v1'"));
    expect(sql, contains('list_pending_membership_applications'));
    expect(sql, contains("'club.memberships.manage'"));
    expect(
      sql,
      contains(
        'revoke all on table core.membership_applications from public,anon,authenticated',
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          'grant execute on function api.search_joinable_club_teams(text) to anon',
        ),
      ),
    );
    final reviewer = File(
      'lib/src/features/roster/roster_surface.dart',
    ).readAsStringSync();
    expect(reviewer, contains("can('club.memberships.manage')"));
    expect(reviewer, contains('listPendingReviews'));
    expect(reviewer, contains('.decide('));
    expect(reviewer, contains('.createTeam('));
    expect(reviewer, isNot(contains('controller.dispose();')));
    // The applications deep link stays gated on club.memberships.manage.
    expect(reviewer, contains("action == 'applications'"));
    expect(reviewer, contains('onOpenApplications'));
    expect(reviewer, contains('_showMembershipReviews'));
    final shell = File('lib/src/app/product_shell.dart').readAsStringSync();
    expect(shell, contains("strings.feature('Hitta klubb eller lag')"));
    expect(shell, contains('_MembershipJoinSheet('));
  });

  test('AUTH-05 migration is atomic, idempotent and creates active context', () {
    final sql = File(
      'supabase/migrations/20260824103737_auth05_club_team_creation.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("email_confirmed_at is not null"));
    expect(sql, contains("'unofficial'"));
    expect(sql, contains("'organization.club.create.v1'"));
    expect(sql, contains('person_account_links'));
    expect(sql, contains("'club_functionary'"));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains("'context_id',assignment_id"));
    expect(sql, contains('create_team_in_club_for_actor'));
    expect(
      sql,
      isNot(
        contains(
          'grant execute on function api.create_club_with_first_team(text,text,uuid) to anon',
        ),
      ),
    );
  });

  test(
    'AUTH-05 additional teams create and refresh a club functionary context',
    () {
      final sql = File(
        'supabase/migrations/20260910183540_auth05_create_team_context.sql',
      ).readAsStringSync().toLowerCase();
      expect(sql, contains('insert into core.assignments'));
      expect(sql, contains("'club_functionary','active'"));
      expect(sql, contains("grant_row.scope_type='club'"));
      expect(sql, contains('context_assignment_id'));
      final roster = File(
        'lib/src/features/roster/roster_surface.dart',
      ).readAsStringSync();
      expect(roster, contains('await widget.onTeamCreated(teamId);'));
      final selector = File(
        'lib/src/features/auth/auth_surfaces.dart',
      ).readAsStringSync();
      expect(selector, contains('context.teamId == teamId'));
      expect(selector, contains('_activeContext = next'));
      final shell = File('lib/src/app/product_shell.dart').readAsStringSync();
      expect(shell, contains("_router.go('/home');"));
    },
  );

  test('AUTH-06 protects confusing names and reserves decisions for service', () {
    final sql = File(
      'supabase/migrations/20260824105130_auth06_protected_club_names.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('normalize_club_name'));
    expect(sql, contains("'а','a'"));
    expect(sql, contains("normalize_club_name('teamzone')"));
    expect(sql, contains('clubs_enforce_protected_name'));
    expect(sql, contains("'status','review_required'"));
    expect(sql, contains("'club.verification.request.v1'"));
    expect(sql, contains("'club.verification.decide.v1'"));
    expect(sql, contains("'club.verification.revoke.v1'"));
    expect(
      sql,
      contains(
        'api.revoke_club_official_status(uuid,text,text) to service_role',
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          'grant execute on function api.decide_club_verification(uuid,text,text,text) to authenticated',
        ),
      ),
    );
    final client = File(
      'lib/src/features/roster/roster_surface.dart',
    ).readAsStringSync();
    expect(client, contains('Officiell klubb'));
    expect(client, contains('Semantics('));
    expect(client, isNot(contains('decideClubVerification')));
  });

  test('protected-name support cases have a separate support-admin boundary', () {
    final sql = File(
      'supabase/migrations/20260911151216_auth06_protected_name_support_cases.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('create table internal.support_admins'));
    expect(sql, contains('create table internal.protected_name_support_cases'));
    expect(
      sql,
      contains(
        'revoke all on table internal.support_admins,internal.protected_name_support_cases',
      ),
    );
    expect(sql, contains('internal.actor_is_support_admin()'));
    expect(sql, contains("name_check->>'status'<>'review_required'"));
    expect(sql, contains('to authenticated'));
    expect(
      sql,
      isNot(contains('grant select on internal.protected_name_support_cases')),
    );
  });

  test('AUTH-06 verification retry resolves dedupe before pending status', () {
    final sql = File(
      'supabase/migrations/20260910202427_auth06_fix_verification_request_replay.sql',
    ).readAsStringSync().toLowerCase();
    final dedupePosition = sql.indexOf('select result into existing_result');
    final statusPosition = sql.indexOf(
      "verification_status in ('unofficial','rejected','revoked')",
    );
    expect(dedupePosition, greaterThan(-1));
    expect(statusPosition, greaterThan(dedupePosition));
    expect(sql, contains("actor_profile_id=actor_id"));
    expect(sql, contains("command_type='club.verification.request.v1'"));
  });

  test('support queue joins club verification without emailing evidence', () {
    final sql = File(
      'supabase/migrations/20261003094810_support_club_verification_queue.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('internal.actor_is_support_admin()'));
    expect(sql, contains('expected_revision'));
    expect(sql, contains('support.club_verification.decide.v1'));
    expect(sql, contains('create table internal.support_email_outbox'));
    expect(sql, contains("'club_verification','protected_name'"));
    final tableStart = sql.indexOf(
      'create table internal.support_email_outbox',
    );
    final tableEnd = sql.indexOf(');', tableStart);
    final outboxDefinition = sql.substring(tableStart, tableEnd);
    expect(outboxDefinition, isNot(contains('evidence_summary')));
    expect(outboxDefinition, isNot(contains('email_address')));
    final worker = File(
      'supabase/functions/support-email-worker/index.ts',
    ).readAsStringSync();
    expect(worker, contains('Underlag och personuppgifter visas endast'));
    expect(worker, isNot(contains('evidence_summary')));
  });

  test('protected-name approval completes official club registration', () {
    final sql = File(
      'supabase/migrations/20261003171000_complete_protected_name_registration.sql',
    ).readAsStringSync();
    expect(sql, contains('approve_protected_name_support_case_for_admin'));
    expect(sql, contains("status='resolved'"));
    expect(sql, contains("verification_status='official'"));
    expect(sql, contains("'club_functionary'"));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains("'event.attendance.correct_late'"));
    expect(sql, contains("'support.protected_name.approve.v1'"));
    expect(
      sql,
      contains(
        'grant execute on function\n  internal.approve_protected_name_support_case_for_admin',
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          'grant execute on function\n  api.approve_protected_name_support_case(uuid,text,bigint,uuid)\nto anon',
        ),
      ),
    );
  });

  test('protected-name support conversation is case-bound and private', () {
    final sql = File(
      'supabase/migrations/20261003180000_protected_name_support_conversation.sql',
    ).readAsStringSync();
    expect(
      sql,
      contains('create table internal.protected_name_support_messages'),
    );
    expect(sql, contains('sender_kind in (\'requester\',\'support\')'));
    expect(sql, contains('internal.actor_is_support_admin()'));
    expect(sql, contains('support_case.requester_profile_id=actor_id'));
    expect(sql, contains("status not in ('pending','in_review')"));
    expect(sql, contains("'support.protected_name.message.v1'"));
    expect(
      sql,
      contains("values('protected_name',support_case.id,next_revision)"),
    );
    expect(sql, isNot(contains("jsonb_build_object('body'")));
    expect(
      sql,
      isNot(
        contains(
          'grant execute on function\n  api.send_protected_name_support_message(uuid,text,boolean,uuid)\nto anon',
        ),
      ),
    );
  });

  test('support inbox unread cursors and attachments stay private', () {
    final sql = File(
      'supabase/migrations/20261004133943_support_inbox_unread_attachments.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('create table internal.protected_name_support_reads'));
    expect(sql, contains('create table internal.protected_name_support_files'));
    expect(sql, contains("'support-case-files'"));
    expect(
      sql,
      contains(
        "values('support-case-files','support-case-files',false,10485760",
      ),
    );
    expect(sql, contains('unread_count bigint'));
    expect(sql, contains('mark_protected_name_support_case_read'));
    expect(sql, contains('authorize_protected_name_support_file'));
    expect(
      sql,
      contains('internal.actor_can_access_protected_name_support_case'),
    );
    expect(
      sql,
      isNot(
        contains(
          'grant execute on function\n  api.authorize_protected_name_support_file(uuid)\nto anon',
        ),
      ),
    );

    final shell = File('lib/src/app/product_shell.dart').readAsStringSync();
    expect(shell, isNot(contains('onOpenMySupportCases')));
    final inbox = File(
      'lib/src/features/messaging/inbox_surface.dart',
    ).readAsStringSync();
    expect(inbox, contains('_supportInboxEntry(context)'));
    expect(inbox, contains('Badge.count(count: unread)'));
  });

  test('support models parse unread counts and message attachments', () {
    final supportCase = ProtectedNameSupportCase.fromJson({
      'case_id': 'case',
      'requester_profile_id': 'profile',
      'candidate_club_name': 'Klubb',
      'candidate_team_name': 'Lag',
      'status': 'in_review',
      'message': 'Ursprungligt meddelande',
      'resolution_note': null,
      'revision': 3,
      'created_at': '2026-10-04T10:00:00Z',
      'updated_at': '2026-10-04T11:00:00Z',
      'unread_count': 2,
    });
    final message = ProtectedNameSupportMessage.fromJson({
      'message_id': 'message',
      'sender_kind': 'support',
      'sender_name': 'Support',
      'body': null,
      'created_at': '2026-10-04T11:00:00Z',
      'attachments': [
        {
          'file_id': 'file',
          'name': 'underlag.pdf',
          'mime_type': 'application/pdf',
          'size_bytes': 1234,
        },
      ],
    });

    expect(supportCase.unreadCount, 2);
    expect(message.body, isEmpty);
    expect(message.attachments.single.name, 'underlag.pdf');
  });
}

class _CoachIdentity implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Coach', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'club_functionary',
      capabilities: {'team.read'},
    ),
  ];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _WaitingIdentity implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _MembershipFake implements MembershipServices {
  String? appliedTeamId;
  String? createdClubName;
  String? createdTeamName;
  String? supportClubName;
  String? supportTeamName;
  String? supportMessage;
  ClubNameCheckStatus nameStatus = ClubNameCheckStatus.available;
  List<MembershipApplication> applications = const [];

  @override
  Future<List<ClubTeamSearchResult>> search({required String query}) async =>
      const [
        ClubTeamSearchResult(
          clubId: 'club',
          clubName: 'Testklubben',
          clubIsOfficial: true,
          teamId: 'team',
          teamName: 'F2012',
        ),
      ];

  @override
  Future<List<MembershipApplication>> listMine() async => applications;

  @override
  Future<String> apply({
    required String teamId,
    required MembershipRole role,
    required String idempotencyKey,
  }) async {
    appliedTeamId = teamId;
    return 'application';
  }

  @override
  Future<void> withdraw({
    required String applicationId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<List<MembershipReviewItem>> listPendingReviews({
    required String clubId,
    String? teamId,
  }) async => const [];

  @override
  Future<void> decide({
    required String applicationId,
    required bool approve,
    MembershipRole? approvedRole,
    required String idempotencyKey,
  }) async {}

  @override
  Future<ClubCreationResult> createClubWithFirstTeam({
    required String clubName,
    required String teamName,
    required String idempotencyKey,
  }) async {
    createdClubName = clubName;
    createdTeamName = teamName;
    return const ClubCreationResult(
      clubId: 'club',
      teamId: 'team',
      contextId: 'context',
    );
  }

  @override
  Future<String> createTeam({
    required String clubId,
    required String teamName,
    required String idempotencyKey,
  }) async => 'team';

  @override
  Future<String> requestTeamCreation({
    required String clubId,
    required String sourceAssignmentId,
    required String teamName,
    required String idempotencyKey,
  }) async => 'request';

  @override
  Future<List<TeamCreationRequest>> listTeamCreationRequests({
    required String clubId,
  }) async => const [];

  @override
  Future<void> decideTeamCreationRequest({
    required String requestId,
    required bool approve,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {}

  @override
  Future<ClubNameCheck> checkClubName({required String name}) async =>
      ClubNameCheck(nameStatus);

  @override
  Future<String> submitProtectedNameSupportCase({
    required String clubName,
    required String teamName,
    required String message,
    required String idempotencyKey,
  }) async {
    supportClubName = clubName;
    supportTeamName = teamName;
    supportMessage = message;
    return 'support-case';
  }

  bool supportAdmin = false;
  List<ProtectedNameSupportCase> supportQueue = const [];

  @override
  Future<bool> isSupportAdmin() async => supportAdmin;

  @override
  Future<List<ProtectedNameSupportCase>> listProtectedNameSupportCases({
    String? status,
  }) async => supportQueue;

  @override
  Future<List<ProtectedNameSupportCase>>
  listMyProtectedNameSupportCases() async => const [];

  @override
  Future<List<ProtectedNameSupportMessage>> listProtectedNameSupportMessages({
    required String caseId,
  }) async => const [];

  @override
  Future<void> markProtectedNameSupportCaseRead({
    required String caseId,
  }) async {}

  @override
  Future<StagedProtectedNameSupportFile> stageProtectedNameSupportFile({
    required String caseId,
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) => throw UnimplementedError();

  @override
  Future<String> protectedNameSupportFileUrl({required String fileId}) =>
      throw UnimplementedError();

  @override
  Future<String> sendProtectedNameSupportMessage({
    required String caseId,
    required String body,
    required bool asSupport,
    required String idempotencyKey,
    List<String> stagedFileIds = const [],
  }) async => 'message';

  @override
  Future<int> updateProtectedNameSupportCase({
    required String caseId,
    required String status,
    required String resolutionNote,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => expectedRevision + 1;

  @override
  Future<List<GlobalPersonErasureCase>> listGlobalPersonErasureCases() async =>
      const [];

  @override
  Future<String> decideGlobalPersonErasure({
    required String requestId,
    required bool approve,
    required String reason,
  }) async => approve ? 'completed' : 'rejected';

  @override
  Future<String> requestClubVerification({
    required String clubId,
    required String evidenceSummary,
    required String idempotencyKey,
  }) async => 'verification';

  @override
  Future<ClubVerificationStatus> getClubVerificationStatus({
    required String clubId,
  }) async =>
      const ClubVerificationStatus(clubId: 'club', status: 'unofficial');

  @override
  Future<List<ClubVerificationRequest>> listClubVerificationRequests({
    String? status,
  }) async => const [];

  @override
  Future<int> decideClubVerificationRequest({
    required String requestId,
    required bool approve,
    required String decisionReason,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => expectedRevision + 1;
}
