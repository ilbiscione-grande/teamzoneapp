import 'dart:async';
import 'dart:io';

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
  test('AUTH-04 runtime patch disambiguates requested membership role', () {
    final sql = File(
      'supabase/migrations/20260903103734_auth04_fix_membership_request_role_ambiguity.sql',
    ).readAsStringSync();
    expect(sql, contains('#variable_conflict use_column'));
    expect(sql, contains('request_team_membership_for_actor.requested_role'));
  });

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
    expect(membership.createdClubName, isNull);
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
  ClubNameCheckStatus nameStatus = ClubNameCheckStatus.available;

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
  Future<List<MembershipApplication>> listMine() async => const [];

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
  Future<ClubNameCheck> checkClubName({required String name}) async =>
      ClubNameCheck(nameStatus);

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
}
