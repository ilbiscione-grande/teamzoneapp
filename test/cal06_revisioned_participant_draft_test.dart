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

  test('candidate parser preserves event-time eligibility group', () {
    final candidate = SquadCandidate.fromJson({
      'person_id': 'person-1',
      'name': 'Kim Andersson',
      'eligibility_kind': 'development',
    });
    expect(candidate.eligibilityKind, 'development');
  });
}
