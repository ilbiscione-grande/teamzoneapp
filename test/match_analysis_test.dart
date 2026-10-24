import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/match_workspace/match_analysis_models.dart';

Map<String, dynamic> _fact(
  String type,
  int minute, {
  String side = 'us',
  String? player,
  String? second,
  Map<String, Object?> detail = const {},
  String state = 'active',
}) => {
  'fact_type': type,
  'minute': minute,
  'side': side,
  'club_person_id': player,
  'secondary_club_person_id': second,
  'detail': detail,
  'state': state,
};

void main() {
  group('match analysis (match module, step 4)', () {
    test('the match ends at full time, else its periods, else now', () {
      expect(
        matchEndMinute(
          state: 'completed',
          facts: [_fact('full_time', 62)],
          periodMinutes: const [30, 30],
          current: 70,
        ),
        62,
      );
      expect(
        matchEndMinute(
          state: 'completed',
          facts: const [],
          periodMinutes: const [30, 30],
          current: 70,
        ),
        60,
      );
      expect(
        matchEndMinute(
          state: 'live',
          facts: const [],
          periodMinutes: const [30, 30],
          current: 41,
        ),
        41,
      );
      expect(
        matchEndMinute(
          state: 'planning',
          facts: const [],
          periodMinutes: const [30, 30],
          current: 1,
        ),
        0,
      );
    });

    test('a minute belongs to its period', () {
      expect(periodOf(0, const [30, 30]), 1);
      expect(periodOf(30, const [30, 30]), 1);
      expect(periodOf(31, const [30, 30]), 2);
      expect(periodOf(75, const [30, 30]), 2);
      expect(periodOf(12, const []), 1);
    });

    test('minutes follow the substitutions, back on again included', () {
      final facts = [
        _fact('substitution', 20, player: 'a', second: 'c'),
        _fact('substitution', 40, player: 'c', second: 'a'),
        _fact('substitution', 45, player: 'b', second: 'd', state: 'voided'),
        _fact('substitution', 50, side: 'opponent', player: 'b'),
      ];
      expect(playingMinutes(['a', 'b'], facts, 60), {
        'a': 40,
        'b': 60,
        'c': 20,
      });
    });

    test('player stats count goals, assists, shots, cards and saves', () {
      final facts = [
        _fact('goal', 10, player: 'a', second: 'b'),
        _fact('shot', 12, player: 'a', detail: {'result': 'on_target'}),
        _fact('shot', 14, player: 'a', detail: {'result': 'missed'}),
        _fact('card', 30, player: 'b', detail: {'color': 'yellow'}),
        _fact('save', 33, player: 'k'),
        _fact('goal', 35, side: 'opponent'),
      ];
      final stats = {
        for (final s in playerStats(
          starters: ['a', 'b', 'k'],
          facts: facts,
          end: 60,
        ))
          s.personId: s,
      };
      expect(
        [stats['a']!.goals, stats['a']!.shots, stats['a']!.onTarget],
        [1, 3, 2],
      );
      expect(
        [stats['b']!.assists, stats['b']!.fouls, stats['b']!.yellow],
        [1, 1, 1],
      );
      expect(
        [stats['k']!.saves, stats['k']!.minutes, stats['k']!.started],
        [1, 60, true],
      );
    });

    test('team totals per side', () {
      final facts = [
        _fact('goal', 10),
        _fact('shot', 12, detail: {'result': 'on_target'}),
        _fact('corner', 13),
        _fact('corner', 14, side: 'opponent'),
        _fact('card', 20, side: 'opponent', detail: {'color': 'red'}),
        _fact('free_kick', 21, state: 'voided'),
      ];
      final us = teamTotals(facts, 'us');
      final them = teamTotals(facts, 'opponent');
      expect(
        [us.goals, us.shots, us.onTarget, us.corners, us.freeKicks],
        [1, 2, 2, 1, 0],
      );
      expect([them.corners, them.fouls, them.red], [1, 1, 1]);
    });
  });
}
