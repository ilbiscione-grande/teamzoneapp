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
  testWidgets('leader sees team identity, shortcuts and administrative needs', (
    tester,
  ) async {
    await tester.pumpWidget(_app(canManage: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    expect(find.text('F2012'), findsWidgets);
    expect(find.text('Ada Ledare'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Öppna trupp'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Öppna trupp'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Kräver åtgärd'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Kräver åtgärd'), findsOneWidget);
    expect(find.text('Aktiva inbjudningar'), findsOneWidget);
    expect(find.text('Väntande ansökningar'), findsOneWidget);
    expect(find.text('Redigera lagprofil'), findsOneWidget);
    expect(find.byIcon(Icons.groups_outlined), findsWidgets);
  });

  testWidgets('player never sees administrative team needs', (tester) async {
    await tester.pumpWidget(_app(canManage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    expect(find.text('F2012'), findsWidgets);
    expect(find.text('Ada Ledare'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Kräver åtgärd'), findsNothing);
    expect(find.text('Aktiva inbjudningar'), findsNothing);
    expect(find.text('Väntande ansökningar'), findsNothing);
    expect(find.text('Redigera lagprofil'), findsNothing);
  });

  test('TEAM-02 projection minimizes admin data behind capability', () {
    final sql = File(
      'supabase/migrations/20260824151510_team02_role_based_overview.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('create table core.team_profiles'));
    expect(sql, contains('internal.actor_has_club_access'));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains("'active_invitation_count',case when can_manage"));
    expect(sql, contains("'pending_application_count',case when can_manage"));
    expect(sql, contains("else 0 end"));
    expect(
      sql,
      contains(
        'revoke all on table core.team_profiles from public,anon,authenticated',
      ),
    );
    expect(
      sql,
      isNot(contains('grant select on core.membership_applications')),
    );
  });

  test('TEAM-02 profile editing is capability scoped and revision safe', () {
    final sql = File(
      'supabase/migrations/20260901100421_team02_team_profile_edit.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains('expected_revision'));
    expect(sql, contains("'team.profile.update.v1'"));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains("normalized_image!~'^https://'"));
    expect(sql, contains('revoke all on function'));
  });

  test('TEAM-02 permits a team-scoped leader without club-wide access', () {
    final sql = File(
      'supabase/migrations/20260901104226_team02_allow_team_leader_profile_edit.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'team.roster.manage'"));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains('team_row.id'));
    expect(sql, contains('revoke all on function'));
  });
}

Widget _app({required bool canManage}) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team02'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: _Identity(canManage),
    roster: const _Roster(),
    isConfigured: true,
  ),
);

class _Roster extends UnconfiguredRosterServices {
  const _Roster();
  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) async =>
      const TeamOverview(
        teamId: 'team',
        clubId: 'club',
        teamName: 'F2012',
        clubName: 'Testklubben',
        teamType: 'Flicklag',
        ageClass: '2012',
        summary: 'Lagets officiella interna presentation.',
        leaders: [
          TeamLeaderSummary(personId: 'leader', displayName: 'Ada Ledare'),
        ],
        memberCount: 18,
        canManage: true,
        activeInvitationCount: 2,
        pendingApplicationCount: 3,
      );
}

class _Identity implements IdentityServices {
  const _Identity(this.canManage);
  final bool canManage;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: canManage ? 'leader' : 'player',
      capabilities: canManage
          ? const {'team.read', 'team.roster.manage'}
          : const {'team.read'},
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
