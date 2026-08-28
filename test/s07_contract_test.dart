import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/match/match_models.dart';

void main() {
  final root = Directory.current.path;
  String migration(String name) =>
      File('$root/supabase/migrations/$name').readAsStringSync();

  test('S07 preserves the ten frozen v2 mutation RPC names', () {
    final sql = migration('20260815075650_s07_v2_mutation_contract.sql');
    for (final name in <String>[
      'save_match_plan_v2',
      'record_match_event_v2',
      'update_match_event_v2',
      'void_match_event_v2',
      'adjust_match_score_v2',
      'adjust_match_kpi_v2',
      'transition_match_clock_v2',
      'complete_match_v2',
      'set_match_button_config_v2',
      'reset_match_v2',
    ]) {
      expect(sql, contains('api.$name'));
    }
  });

  test('S07 keeps facts derived and commands retry safe', () {
    final foundation = migration(
      '20260815074741_s07_match_v2_adapter_foundation.sql',
    );
    final engine = migration(
      '20260815075030_s07_command_roster_projection_engine.sql',
    );
    final contract = migration('20260815075650_s07_v2_mutation_contract.sql');
    expect(foundation, contains('match_commands_append_only'));
    expect(engine, contains('recompute_match_projection'));
    expect(contract, contains('internal.register_match_command'));
    expect(contract, contains("workspace.state<>'live'"));
    expect(contract, contains("void_reason='reset'"));
  });

  test('S07 client parses server revision, cursor and derived score', () {
    final snapshot = MatchSnapshot.fromJson({
      'event_id': 'event',
      'state': 'live',
      'revision': 7,
      'roster_revision': 2,
      'cursor': '2026-08-15/command',
      'clock': {'paused_at': null},
      'projection': {'score_us': 3, 'score_opponent': 1},
      'facts': <Object>[],
    });
    expect(snapshot.revision, 7);
    expect(snapshot.cursor, '2026-08-15/command');
    expect(snapshot.scoreUs, 3);
    expect(snapshot.scoreOpponent, 1);
  });

  test('S07 match clock subtracts pauses and freezes while paused', () {
    final snapshot = MatchSnapshot.fromJson({
      'event_id': 'event',
      'state': 'live',
      'revision': 8,
      'roster_revision': 1,
      'cursor': 'cursor',
      'clock': {
        'started_at': '2026-08-15T10:00:00Z',
        'paused_at': '2026-08-15T10:12:30Z',
        'paused_seconds': 150,
      },
      'projection': <String, Object?>{},
      'facts': <Object>[
        {
          'fact_type': 'period_end',
          'state': 'active',
          'detail': {
            'period': 1,
            'scheduled_minute': 45,
            'elapsed_seconds': 600,
          },
        },
      ],
    });
    expect(
      snapshot.elapsedAt(DateTime.parse('2026-08-15T11:00:00Z')),
      const Duration(minutes: 45),
    );
  });

  test('S07 supports configurable multi-period matches', () {
    final sql = migration('20260815091054_s07_halftime_clock_anchor.sql');
    expect(sql, contains('period_minutes'));
    expect(sql, contains('current_period'));
    expect(sql, contains('transition_match_period_v2'));
    expect(sql, contains("'period_end'"));
  });
}
