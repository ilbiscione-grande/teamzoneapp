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
  testWidgets('leader moves a player to another team with an explicit date', (
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
    await tester.tap(find.text('Flytta spelare'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Spelare'), findsOneWidget);
    await tester.tap(find.text('Flytta'));
    await tester.pumpAndSettle();
    expect(
      find.text('Det tidigare laget och all historik bevaras.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Flytta').last);
    await tester.pumpAndSettle();
    expect(roster.moveCalls, 1);
    expect(roster.targetTeam, 'target');
    expect(find.text('Spelaren är flyttad.'), findsOneWidget);
  });

  test('TEAM-07 SQL moves atomically and preserves historical rows', () {
    final sql = File(
      'supabase/migrations/20260827053705_team07_intra_club_player_move.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains("set state='ended',ends_at=effective_at"));
    expect(sql, contains('insert into core.team_assignments'));
    expect(sql, contains('overlapping_home_assignment'));
    expect(sql, contains('stale_revision'));
    expect(sql, contains("'roster.move.within_club.v1'"));
    expect(sql, contains('target_source_team_id=target_target_team_id'));
    expect(sql, contains('revoke all on function'));
    expect(sql, isNot(contains('delete from core.team_assignments')));
    expect(sql, isNot(contains('update core.events')));
  });

  test('move options parser retains assignment identity and revision', () {
    final options = IntraClubMoveOptions.fromJson(const {
      'people': [
        {
          'club_person_id': 'person',
          'display_name': 'Ada',
          'source_team_id': 'source',
          'source_team_name': 'F2012',
          'assignment_id': 'assignment',
          'assignment_starts_at': '2026-08-01T00:00:00Z',
          'assignment_revision': 4,
        },
      ],
      'teams': [
        {'team_id': 'target', 'team_name': 'F2011'},
      ],
    });
    expect(options.canMove, isTrue);
    expect(options.people.single.assignmentRevision, 4);
    expect(options.teams.single.name, 'F2011');
  });
}

Widget _app(_Roster roster) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team07'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: const _Identity(),
    roster: roster,
    isConfigured: true,
  ),
);

class _Roster extends UnconfiguredRosterServices {
  int moveCalls = 0;
  String? targetTeam;
  @override
  Future<IntraClubMoveOptions> getIntraClubMoveOptions({
    required String clubId,
    required String sourceTeamId,
  }) async => IntraClubMoveOptions(
    people: [
      IntraClubMovePerson(
        personId: 'person',
        personName: 'Ada Spelare',
        sourceTeamId: sourceTeamId,
        sourceTeamName: 'F2012',
        assignmentId: 'assignment',
        assignmentStartsAt: DateTime(2026, 8, 1),
        assignmentRevision: 2,
      ),
    ],
    teams: const [IntraClubMoveTeam(id: 'target', name: 'F2011')],
  );
  @override
  Future<void> movePlayerWithinClub({
    required String clubId,
    required String sourceTeamId,
    required String targetTeamId,
    required String personId,
    required String assignmentId,
    required DateTime effectiveAt,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) async {
    moveCalls++;
    targetTeam = targetTeamId;
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
      teamId: 'source',
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
