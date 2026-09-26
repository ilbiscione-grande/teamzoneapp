import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  test('squad projection exposes selection and late-dispatch metadata', () {
    final squad = SquadDetails.fromJson({
      'event_id': 'event-1',
      'squad_revision_id': 'revision-2',
      'squad_revision': 2,
      'squad_state': 'draft',
      'selection_source': 'generator',
      'selection_context': {'generator': 'balanced_v1', 'target_count': 2},
      'dispatch_kind': 'late',
      'members': <Map<String, dynamic>>[],
      'callups': <Map<String, dynamic>>[],
      'attendance': <Map<String, dynamic>>[],
      'caller_actions': ['save_squad'],
    });

    expect(squad.selectionSource, 'generator');
    expect(squad.selectionContext['target_count'], 2);
    expect(squad.dispatchKind, 'late');
  });

  test('CAL-06 migration freezes one revisioned and retry-safe draft', () {
    final sql = File(
      'supabase/migrations/20260827073426_cal06_revisioned_participant_draft.sql',
    ).readAsStringSync();

    for (final source in ['manual', 'all', 'group', 'generator']) {
      expect(sql, contains("'$source'"));
    }
    expect(sql, contains("'squad.draft.saved.v2'"));
    expect(sql, contains("'event-squad:'"));
    expect(sql, contains("message='stale_revision'"));
    expect(sql, contains('internal.person_eligibility_at_event'));
    expect(sql, contains("'callup.callup.late_sent.v1'"));
    expect(sql, contains("message='no_new_recipients'"));
    expect(sql, contains('on conflict do nothing'));
  });

  test('lock and send commands name every deduplication column', () {
    final correction = File(
      'supabase/migrations/20260831202517_cal06_fix_command_deduplication_inserts.sql',
    ).readAsStringSync();
    expect(
      correction,
      contains(
        'internal.command_deduplication(actor_profile_id,idempotency_key,command_type,result)',
      ),
    );
    expect(
      correction,
      isNot(contains('internal.command_deduplication values')),
    );
    expect(correction, contains("'squad.locked.v1'"));
    expect(correction, contains("'callup.callup.sent.v1'"));
  });

  test('an unlocked manual draft can be cleared completely', () {
    final correction = File(
      'supabase/migrations/20260920094411_cal06_allow_empty_manual_draft.sql',
    ).readAsStringSync();

    expect(
      correction,
      contains('cardinality(member_ids) not between 0 and 100'),
    );
    expect(
      correction,
      contains("selection_source<>'manual' and cardinality(member_ids)=0"),
    );
    expect(correction, contains("command_type='squad.draft.saved.v2'"));
    expect(correction, contains("message='stale_revision'"));
  });

  test('candidate parser preserves event-time eligibility group', () {
    final candidate = SquadCandidate.fromJson({
      'person_id': 'person-1',
      'name': 'Kim Andersson',
      'eligibility_kind': 'development',
    });
    expect(candidate.eligibilityKind, 'development');
  });

  test('multi-team assignments produce one event participant per person', () {
    final squad = SquadDetails.fromJson({
      'event_id': 'event-1',
      'squad_state': 'sent',
      'members': <Map<String, dynamic>>[],
      'callups': <Map<String, dynamic>>[],
      'attendance': <Map<String, dynamic>>[],
      'caller_actions': <String>[],
      'roster': [
        {
          'person_id': 'leader-1',
          'name': 'Ledare Larsson',
          'team_id': 'team-primary',
          'team_name': 'P16',
          'role_package': 'leader',
          'in_draft': true,
          'callup_id': 'callup-1',
          'callup_state': 'pending',
        },
        {
          'person_id': 'leader-1',
          'name': 'Ledare Larsson',
          'team_id': 'team-shared',
          'team_name': 'P15',
          'role_package': 'leader',
          'in_draft': true,
          'callup_id': 'callup-1',
          'callup_state': 'pending',
        },
      ],
    });

    expect(squad.roster, hasLength(1));
    expect(squad.roster.single.personId, 'leader-1');
    expect(squad.roster.single.callupId, 'callup-1');
  });

  test('a cancelled callup is not carried into the next working draft', () {
    final squad = SquadDetails.fromJson({
      'event_id': 'event-1',
      'squad_revision_id': 'sent-revision',
      'squad_revision': 3,
      'squad_state': 'sent',
      'members': [
        {
          'person_id': 'cancelled-person',
          'name': 'Återkallad Spelare',
          'selection_state': 'selected',
          'source': 'manual',
        },
      ],
      'callups': [
        {
          'callup_id': 'cancelled-callup',
          'person_id': 'cancelled-person',
          'name': 'Återkallad Spelare',
          'state': 'cancelled',
          'revision': 2,
        },
      ],
      'attendance': <Map<String, dynamic>>[],
      'roster': [
        {
          'person_id': 'cancelled-person',
          'name': 'Återkallad Spelare',
          'team_id': 'team-1',
          'team_name': 'P16',
          'role_package': 'player',
          'in_draft': true,
        },
      ],
      'caller_actions': ['save_squad'],
    });

    expect(squad.members, isEmpty);
    expect(squad.roster.single.inDraft, isFalse);
    expect(squad.callups.single.state, 'cancelled');
  });
}
