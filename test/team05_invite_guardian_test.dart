import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
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
    await tester.enterText(find.byType(TextField), 'a' * 40);
    await tester.tap(find.text('Acceptera'));
    await tester.pumpAndSettle();
    expect(roster.claimCodeCalls, 1);
    expect(find.text('Medlemsansökan har skapats.'), findsOneWidget);
  });

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
}

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
  int revokeCalls = 0, claimCodeCalls = 0;
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
