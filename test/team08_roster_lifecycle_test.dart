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
import 'package:teamzone_app/src/features/membership/membership_models.dart';

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
    await tester.tap(find.byTooltip('Hantera'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Arkivering och personuppgifter'));
    await tester.tap(find.text('Arkivering och personuppgifter'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Spelare'), findsWidgets);
    expect(find.textContaining('två separata ansvariga'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avsluta i laget').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Slutat i laget');
    await tester.tap(find.text('Bekräfta'));
    await tester.pumpAndSettle();
    expect(roster.archiveCalls, 1);
    await tester.tap(find.text('Arkiverade'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Spelare'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Återaktivera i laget').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tillbaka i laget');
    await tester.tap(find.text('Bekräfta'));
    await tester.pumpAndSettle();
    expect(roster.restoreCalls, 1);
  });

  testWidgets(
    'club approval remains visible while functionary uses a leader context',
    (tester) async {
      await tester.pumpWidget(_app(_Roster(includeRequest: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laget'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trupp'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hantera'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Arkivering och personuppgifter'));
      await tester.tap(find.text('Arkivering och personuppgifter'));
      await tester.pumpAndSettle();
      expect(find.text('Godkänn'), findsOneWidget);
    },
  );

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

  test('member profile exposes the same history-preserving archive flow', () {
    final surface = File(
      'lib/src/features/roster/roster_surface.dart',
    ).readAsStringSync();
    expect(surface, contains('onEdit: canManage'));
    expect(surface, contains('_archivePersonFromDetails('));
    expect(surface, contains('roster.getRosterLifecycle('));
    expect(surface, contains('roster.archiveTeamAssignment('));
    expect(
      surface,
      contains(
        'Spelaren flyttas till Arkiverade. Namn, matcher, närvaro och annan historik bevaras.',
      ),
    );
  });

  test('global erasure worker is support-scoped and retry-safe', () {
    final sql = File(
      'supabase/migrations/20260913124518_team08_global_person_erasure_worker.sql',
    ).readAsStringSync().toLowerCase();
    final worker = File(
      'supabase/functions/person-erasure-worker/index.ts',
    ).readAsStringSync();
    expect(sql, contains('internal.actor_is_support_admin()'));
    expect(sql, contains("current_user not in ('service_role','postgres')"));
    expect(
      sql,
      contains(
        'grant execute on function api.get_global_person_erasure_worker_item(uuid)\nto service_role',
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          'grant execute on function api.get_global_person_erasure_worker_item(uuid)\nto authenticated',
        ),
      ),
    );
    expect(worker, contains('userClient.auth.getUser()'));
    expect(worker, contains('.rpc("is_support_admin")'));
    expect(worker, contains('else if (input.decision !== "approved")'));
    expect(worker, contains('auth.admin.deleteUser'));
    expect(worker, contains('"finalize_global_person_erasure"'));
  });

  test('global erasure queue parser preserves only minimized case fields', () {
    final item = GlobalPersonErasureCase.fromJson(const {
      'request_id': 'request',
      'requester_name': 'Test Person',
      'state': 'requested',
      'reason': 'Egen begäran',
      'requested_at': '2026-09-13T10:00:00Z',
      'reviewed_at': null,
      'completed_at': null,
      'revision': 1,
    });
    expect(item.id, 'request');
    expect(item.state, 'requested');
    expect(item.reviewedAt, isNull);
  });

  test('restoration creates a new assignment and never reopens history', () {
    final sql = File(
      'supabase/migrations/20260913131353_team08_restore_archived_assignment.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("command_type='roster.assignment.restore.v1'"));
    expect(sql, contains('insert into core.team_assignments'));
    expect(sql, contains("archived_row.state<>'ended'"));
    expect(sql, contains("active_assignment.state='active'"));
    expect(
      sql,
      isNot(contains("update core.team_assignments set state='active'")),
    );
  });

  test('roster periods synchronize only the matching player app context', () {
    final sql = File(
      'supabase/migrations/20260920163500_team08_sync_player_context_with_roster.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('team_assignments_sync_player_context'));
    expect(sql, contains("assignment.role_package = 'player'"));
    expect(sql, contains("set state = 'ended'"));
    expect(sql, contains('insert into core.assignments'));
    expect(sql, contains("'player',\n      'active'"));
    expect(sql, contains('not exists('));
    expect(sql, isNot(contains("role_package in ('player','leader'")));
    expect(sql, isNot(contains('update core.person_account_links')));
  });

  test('legacy person detail remains non-null without birth year', () {
    final sql = File(
      'supabase/migrations/20260913133759_team04_null_safe_person_details.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('if person_row.birth_year is not null then'));
    expect(sql, contains('if person_row.birth_date is not null then'));
    expect(
      sql,
      isNot(
        contains(
          "jsonb_set(result,'{management,birth_year}',to_jsonb(person_row.birth_year),true)",
        ),
      ),
    );
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
  _Roster({this.includeRequest = false});

  final bool includeRequest;
  int archiveCalls = 0;
  int restoreCalls = 0;
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
        assignmentState: archiveCalls == 0 || restoreCalls > 0
            ? 'active'
            : 'ended',
        assignmentRevision: 1 + archiveCalls,
        canReactivate: archiveCalls > 0 && restoreCalls == 0,
      ),
    ],
    requests: includeRequest
        ? const [
            ClubErasureRequest(
              id: 'request',
              personId: 'person',
              personName: 'Ada Spelare',
              state: 'requested',
              initiatedBy: 'other-profile',
              revision: 1,
            ),
          ]
        : const [],
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

  @override
  Future<String> restoreArchivedTeamAssignment({
    required String clubId,
    required String teamId,
    required String personId,
    required String assignmentId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) async {
    restoreCalls += 1;
    return 'new-assignment';
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
