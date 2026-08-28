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
  testWidgets('leader archives an active assignment with visible history', (
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
    await tester.tap(find.text('Arkivering och personuppgifter'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Spelare'), findsWidgets);
    expect(find.textContaining('två separata ansvariga'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arkivera från laget').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Slutat i laget');
    await tester.tap(find.text('Bekräfta'));
    await tester.pumpAndSettle();
    expect(roster.archiveCalls, 1);
  });

  test('TEAM-08 SQL enforces dual control and preserves references', () {
    final sql = File(
      'supabase/migrations/20260827055529_team08_roster_lifecycle_erasure.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('club_person_erasure_requests'));
    expect(sql, contains('approved_by<>initiated_by'));
    expect(sql, contains('separate_approver_required'));
    expect(sql, contains("current_user not in('service_role','postgres')"));
    expect(sql, contains('reviewer_profile_id=request_row.requested_by'));
    expect(sql, contains("display_name='tidigare spelare'"));
    expect(sql, contains("display_name='raderad användare'"));
    expect(sql, contains("provenance='anonymized'"));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('revoke all on function'));
    expect(sql, isNot(contains('delete from core.team_assignments')));
    expect(sql, isNot(contains('delete from core.events')));
    expect(sql, isNot(contains('delete from core.club_people')));
  });

  test('lifecycle parser separates archived people and erasure requests', () {
    final options = RosterLifecycleOptions.fromJson(const {
      'people': [
        {
          'club_person_id': 'person',
          'person_name': 'Tidigare spelare',
          'assignment_id': 'assignment',
          'assignment_state': 'ended',
          'assignment_revision': 2,
        },
      ],
      'requests': [
        {
          'request_id': 'request',
          'club_person_id': 'person',
          'person_name': 'Ada',
          'state': 'requested',
          'initiated_by': 'leader',
          'revision': 1,
        },
      ],
    });
    expect(options.people.single.canArchive, isFalse);
    expect(options.requests.single.canApprove, isTrue);
  });
}

Widget _app(_Roster roster) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team08'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: const _Identity(),
    roster: roster,
    isConfigured: true,
  ),
);

class _Roster extends UnconfiguredRosterServices {
  int archiveCalls = 0;
  @override
  Future<RosterLifecycleOptions> getRosterLifecycle({
    required String clubId,
    required String teamId,
  }) async => RosterLifecycleOptions(
    people: [
      RosterLifecyclePerson(
        personId: 'person',
        personName: 'Ada Spelare',
        assignmentId: 'assignment',
        assignmentState: archiveCalls == 0 ? 'active' : 'ended',
        assignmentRevision: 1 + archiveCalls,
      ),
    ],
    requests: const [],
  );
  @override
  Future<int> archiveTeamAssignment({
    required String clubId,
    required String teamId,
    required String personId,
    required String assignmentId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) async => ++archiveCalls;
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
