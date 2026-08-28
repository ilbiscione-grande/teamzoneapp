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
  testWidgets('leader sees and ends cross-team representation', (tester) async {
    final roster = _Roster();
    await tester.pumpWidget(_app(roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hantera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Representation i andra lag'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Spelare'), findsOneWidget);
    expect(find.textContaining('Utvecklingsspel'), findsOneWidget);
    await tester.tap(find.text('Avsluta'));
    await tester.pumpAndSettle();
    expect(roster.endCalls, 1);
  });

  test(
    'TEAM-06 SQL preserves home team and validates event-time eligibility',
    () {
      final sql = File(
        'supabase/migrations/20260827044300_team06_cross_team_representation.sql',
      ).readAsStringSync().toLowerCase();
      expect(sql, contains("('development','dispensation','loan','guest')"));
      expect(sql, contains("('season','fixed','indefinite')"));
      expect(sql, contains('review_due_at'));
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(sql, contains('overlapping_play_eligibility'));
      expect(sql, contains('eligibility.starts_at<=event_row.starts_at'));
      expect(sql, contains('eligibility.review_due_at>event_row.starts_at'));
      expect(sql, isNot(contains('update core.team_assignments')));
      expect(sql, isNot(contains('update core.events')));
      expect(sql, contains('revoke all on function'));
    },
  );

  test('representation parser keeps validity and revisions separate', () {
    final item = PlayEligibilitySummary.fromJson(const {
      'eligibility_id': 'eligibility',
      'club_person_id': 'person',
      'person_name': 'Ada',
      'target_team_id': 'target',
      'target_team_name': 'F2011',
      'eligibility_kind': 'dispensation',
      'validity_kind': 'season',
      'state': 'active',
      'starts_at': '2026-08-01T00:00:00Z',
      'ends_at': '2027-06-30T23:59:59Z',
      'season_ends_on': '2027-06-30',
      'revision': 3,
    });
    expect(item.canEnd, isTrue);
    expect(item.validityKind, 'season');
    expect(item.revision, 3);
  });
}

Widget _app(_Roster roster) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team06'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: const _Identity(),
    roster: roster,
    isConfigured: true,
  ),
);

class _Roster extends UnconfiguredRosterServices {
  int endCalls = 0;
  @override
  Future<List<PlayEligibilitySummary>> listPlayEligibilities({
    required String clubId,
    required String teamId,
  }) async => [
    PlayEligibilitySummary(
      id: 'eligibility',
      personId: 'person',
      personName: 'Ada Spelare',
      targetTeamId: teamId,
      targetTeamName: 'F2011',
      kind: 'development',
      validityKind: 'season',
      state: endCalls == 0 ? 'active' : 'ended',
      startsAt: DateTime(2026, 8, 1),
      endsAt: DateTime(2027, 6, 30),
      seasonEndsOn: DateTime(2027, 6, 30),
      revision: 1 + endCalls,
    ),
  ];
  @override
  Future<int> endPlayEligibility({
    required String eligibilityId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => ++endCalls;
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
      teamId: 'target',
      teamName: 'F2011',
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
