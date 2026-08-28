import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260807220144_s02_roster_lifecycle.sql',
  ).readAsStringSync();
  final guardianMigration = File(
    'supabase/migrations/20260807221647_s02_guardian_policy.sql',
  ).readAsStringSync();

  test('S02 migration is greenfield and tenant-bound', () {
    expect(migration, isNot(contains('from public.members')));
    expect(migration, contains('foreign key (team_id, club_id)'));
    expect(migration, contains('foreign key (club_person_id, club_id)'));
    expect(migration, contains('source_club_id <> target_club_id'));
  });

  test('S02 commands are invoker wrappers over guarded internal commands', () {
    for (final command in [
      'create_roster_person',
      'issue_roster_invite',
      'claim_club_person',
      'end_team_assignment',
      'request_transfer',
      'decide_transfer',
      'complete_transfer',
    ]) {
      expect(migration, contains('create function api.$command'));
    }
    expect(migration, contains('security invoker'));
  });

  test('guardian policy requires invite, own account and third approval', () {
    expect(guardianMigration, contains('club.safeguarding.manage'));
    expect(guardianMigration, contains('guardian_account_mismatch'));
    expect(guardianMigration, contains("actor_side:='guardian'"));
    expect(
      guardianMigration,
      contains('case when guardian_required then 3 else 2 end'),
    );
    expect(guardianMigration, contains("guardian_invite_required"));
  });

  test('minimal roster projection parses without PII', () {
    final person = RosterPersonSummary.fromJson({
      'club_person_id': 'person-1',
      'display_name': 'Testspelare',
      'age_class': 'F2012',
      'safeguarding_required': true,
      'team_id': 'team-1',
      'team_name': 'F2012',
      'assignment_state': 'active',
    });
    expect(person.displayName, 'Testspelare');
    expect(person.safeguardingRequired, isTrue);
  });
}
