import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/localization/app_strings.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

void main() {
  testWidgets('leader sees invitation status and can revoke an issued code', (
    tester,
  ) async {
    final roster = _Roster();
    await tester.pumpWidget(_app(roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hantera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbjudningar och lagkoder'));
    await tester.pumpAndSettle();
    expect(find.text('F2012 · player'), findsOneWidget);
    expect(find.text('Återkalla'), findsOneWidget);
    await tester.tap(find.text('Återkalla'));
    await tester.pumpAndSettle();
    expect(roster.revokeCalls, 1);
  });

  testWidgets('team code creates a reviewed membership application', (
    tester,
  ) async {
    final roster = _Roster();
    await tester.pumpWidget(_app(roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Använd kod'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardianinbjudan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lagkod').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      _textFieldWithLabel('Säker inbjudningskod'),
      'a' * 40,
    );
    await tester.tap(find.text('Acceptera'));
    await tester.pumpAndSettle();
    expect(roster.claimCodeCalls, 1);
    expect(find.text('Medlemsansökan har skapats.'), findsOneWidget);
  });

  testWidgets('leader can reveal and copy a recoverable team code', (
    tester,
  ) async {
    final roster = _Roster();
    await tester.pumpWidget(_app(roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hantera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbjudningar och lagkoder'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Visa kod'));
    await tester.pumpAndSettle();
    expect(roster.revealCodeCalls, 1);
    expect(find.text('r' * 64), findsOneWidget);
    expect(find.text('Kopiera'), findsOneWidget);
  });

  testWidgets('guardian invite explains when no child is eligible', (
    tester,
  ) async {
    final roster = _Roster();
    await tester.pumpWidget(_app(roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hantera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbjudningar och lagkoder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardian'));
    await tester.pumpAndSettle();
    expect(
      find.text('Markera först ett barn som behöver vårdnadshavarkoppling.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'targeted invite keeps invalid email visible and submits valid email',
    (tester) async {
      final roster = _Roster();
      await tester.pumpWidget(_app(roster));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laget'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trupp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hantera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inbjudningar och lagkoder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Riktad'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _textFieldWithLabel('Mottagarens e-post'),
        'ogiltig',
      );
      await tester.tap(find.text('Skapa'));
      await tester.pumpAndSettle();
      expect(find.text('Ange en giltig e-postadress.'), findsOneWidget);
      expect(find.text('Riktad inbjudan'), findsOneWidget);
      expect(roster.targetedInviteCalls, 0);
      await tester.enterText(
        _textFieldWithLabel('Mottagarens e-post'),
        'test@example.com',
      );
      await tester.tap(find.text('Skapa'));
      await tester.pumpAndSettle();
      expect(roster.targetedInviteCalls, 1);
      expect(find.text('Koden är skapad'), findsOneWidget);
    },
  );

  test(
    'TEAM-05 SQL keeps shared codes reviewed and guardian acting-as explicit',
    () {
      final sql = File(
        'supabase/migrations/20260826203502_team05_invite_guardian_lifecycle.sql',
      ).readAsStringSync().toLowerCase();
      expect(sql, contains('create table core.team_join_codes'));
      expect(sql, contains('insert into core.membership_applications'));
      final claimCode = sql
          .split('create function internal.claim_team_join_code_for_actor')[1]
          .split('create function internal.list_invitation_admin_for_actor')[0];
      expect(
        claimCode,
        isNot(contains('insert into core.person_account_links')),
      );
      expect(sql, contains("'roster.invitation.revoke.v1'"));
      expect(sql, contains("'roster.guardian_relation.end.v1'"));
      expect(sql, contains("'acting_as_guardian_person_id'"));
      expect(sql, contains('club_person_id=relation.guardian_person_id'));
      expect(sql, contains('revoke all on function'));
    },
  );

  test('expired invitations cannot expose a revoke action', () {
    final item = InvitationAdminItem(
      id: 'invite',
      kind: 'targeted',
      subjectName: 'Ada',
      state: 'issued',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      revision: 1,
    );
    expect(item.canRevoke, isFalse);
  });

  testWidgets('invitation states are localized in Swedish', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(AppStrings.of(context).domainValue('issued'), 'Utfärdad');
    expect(AppStrings.of(context).domainValue('revoked'), 'Återkallad');
    expect(AppStrings.of(context).domainValue('expired'), 'Utgången');
    expect(AppStrings.of(context).domainValue('consumed'), 'Använd');
  });

  test('TEAM-05 orders the compound invitation projection outside UNION', () {
    final sql = File(
      'supabase/migrations/20260901150836_team05_fix_invitation_admin_ordering.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('from ('));
    expect(sql, contains(') as item'));
    expect(sql, contains('order by item.expires_at desc nulls last'));
    expect(sql, contains('revoke all on function'));
  });

  test('TEAM-05 scopes targeted invites to an actively managed team', () {
    final sql = File(
      'supabase/migrations/20260901202344_team05_allow_team_scoped_targeted_invite.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('from core.team_assignments target_assignment'));
    expect(sql, contains("target_assignment.state = 'active'"));
    expect(sql, contains("'team.roster.manage'"));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains('target_assignment.team_id'));
    expect(sql, contains("message = 'not_found'"));
  });

  test('TEAM-05 stores recoverable team codes in Vault behind an audited RPC', () {
    final sql = File(
      'supabase/migrations/20260901211827_team05_reveal_encrypted_team_code.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('vault.create_secret'));
    expect(sql, contains('vault.decrypted_secrets'));
    expect(sql, contains('roster.team_code.reveal.v1'));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('api.reveal_team_join_code'));
  });

  test('TEAM-05 repairs the qualified parameter after claim function rename', () {
    final sql = File(
      'supabase/migrations/20260902215140_team05_fix_renamed_guardian_claim_parameter.sql',
    ).readAsStringSync();
    expect(
      sql,
      contains(
        'accept_guardian_invite_and_link_for_actor.idempotency_key',
      ),
    );
    expect(sql, contains('pg_get_functiondef'));
  });

  test('TEAM-05 guardian issue is scoped to the child active team', () {
    final sql = File(
      'supabase/migrations/20260901215526_team05_guardian_team_scope_and_child_flag.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('set_guardian_requirement_for_actor'));
    expect(sql, contains('child_assignment.team_id'));
    expect(sql, contains("child.safeguarding_required"));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains('roster.person.guardian_requirement.set.v1'));
  });
}

Finder _textFieldWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Widget _app(_Roster roster) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team05'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: const _Identity(),
    roster: roster,
    isConfigured: true,
  ),
);

class _Roster extends UnconfiguredRosterServices {
  int revokeCalls = 0,
      claimCodeCalls = 0,
      targetedInviteCalls = 0,
      revealCodeCalls = 0;
  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async => const [
    RosterPersonSummary(
      id: 'person',
      displayName: 'Testperson',
      safeguardingRequired: false,
      teamId: 'team',
      teamName: 'F2012',
      assignmentState: 'active',
    ),
  ];
  @override
  Future<List<InvitationAdminItem>> listInvitationAdmin({
    required String clubId,
    required String teamId,
  }) async => [
    InvitationAdminItem(
      id: 'code',
      kind: 'team_code',
      subjectName: 'F2012 · player',
      state: revokeCalls == 0 ? 'issued' : 'revoked',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      revision: 1 + revokeCalls,
    ),
  ];
  @override
  Future<int> revokeInvitation({
    required String kind,
    required String invitationId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => ++revokeCalls;
  @override
  Future<String> claimTeamCode({
    required String token,
    required String idempotencyKey,
  }) async {
    claimCodeCalls++;
    return 'application';
  }

  @override
  Future<String> issueTargetedInvitation({
    required String personId,
    required String intendedEmail,
    required String token,
    required DateTime expiresAt,
    required String idempotencyKey,
  }) async {
    targetedInviteCalls++;
    return 'invite';
  }

  @override
  Future<String> revealTeamCode({required String codeId}) async {
    revealCodeCalls++;
    return 'r' * 64;
  }
}

class _Identity implements IdentityServices {
  const _Identity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'leader',
      capabilities: {
        'team.read',
        'team.roster.view',
        'club.memberships.manage',
      },
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
