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
  testWidgets('roster supports status filter, pagination and mobile details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(role: 'leader', canView: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();

    expect(find.text('Person 00'), findsOneWidget);
    final rosterList = find.ancestor(
      of: find.text('Person 00'),
      matching: find.byType(ListView),
    );
    final rosterScroll = tester.state<ScrollableState>(
      find.descendant(of: rosterList, matching: find.byType(Scrollable)),
    );
    rosterScroll.position.jumpTo(rosterScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Visa fler'), findsOneWidget);
    await tester.tap(find.text('Tidigare'));
    await tester.pumpAndSettle();
    expect(find.text('Tidigare 00'), findsOneWidget);
    expect(find.text('Person 00'), findsNothing);
    await tester.tap(find.text('Tidigare 00'));
    await tester.pumpAndSettle();
    expect(find.text('Administrativa uppgifter'), findsOneWidget);
    expect(find.text('Testimport'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Administrativa uppgifter'), findsNothing);
    expect(find.text('Tidigare 00'), findsOneWidget);
  });

  testWidgets('unknown role is fail closed before roster data is shown', (
    tester,
  ) async {
    await tester.pumpWidget(_app(role: 'guest', canView: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    expect(find.text('Truppen är inte tillgänglig'), findsOneWidget);
    expect(find.text('Person 00'), findsNothing);
  });

  test('role-minimized detail parser omits management for ordinary member', () {
    final minimal = RosterPersonDetails.fromJson(const {
      'club_person_id': 'person',
      'display_name': 'Ada',
      'team_id': 'team',
      'team_name': 'F2012',
      'assignment_state': 'active',
    });
    expect(minimal.hasManagementDetails, isFalse);
    expect(minimal.safeguardingRequired, isNull);
  });

  test('TEAM-03 SQL enforces capability, role and explicit grants', () {
    final sql = File(
      'supabase/migrations/20260824155142_team03_roster_details.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'team.roster.view'"));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains("'player','leader','guardian','club_functionary'"));
    expect(sql, contains("message='role_not_supported'"));
    expect(sql, contains("'management',case when can_manage"));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('grant execute on function'));
  });
}

Widget _app({required String role, required bool canView}) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team03'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: _Identity(role, canView),
    roster: const _Roster(),
    isConfigured: true,
  ),
);

class _Roster extends UnconfiguredRosterServices {
  const _Roster();

  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async => [
    for (var index = 0; index < 35; index++)
      RosterPersonSummary(
        id: 'active-$index',
        displayName: 'Person ${index.toString().padLeft(2, '0')}',
        ageClass: '2012',
        teamId: 'team',
        teamName: 'F2012',
        assignmentState: 'active',
        safeguardingRequired: false,
      ),
    for (var index = 0; index < 2; index++)
      RosterPersonSummary(
        id: 'ended-$index',
        displayName: 'Tidigare ${index.toString().padLeft(2, '0')}',
        teamId: 'team',
        teamName: 'F2012',
        assignmentState: 'ended',
        safeguardingRequired: false,
      ),
  ];

  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) async => RosterPersonDetails(
    id: personId,
    displayName: 'Tidigare 00',
    teamId: teamId,
    teamName: 'F2012',
    assignmentState: 'ended',
    provenance: 'Testimport',
  );
}

class _Identity implements IdentityServices {
  const _Identity(this.role, this.canView);
  final String role;
  final bool canView;
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
      rolePackage: role,
      capabilities: canView
          ? const {'team.read', 'team.roster.view', 'club.memberships.manage'}
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
