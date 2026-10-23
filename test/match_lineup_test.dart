import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/match_workspace/match_plan_services.dart';

void main() {
  group('match lineup (match module, step 2)', () {
    test('every offered formation fills the pitch for its format', () {
      for (final MapEntry(key: format, value: formations)
          in formationsByFormat.entries) {
        for (final formation in formations) {
          final slots = formationSlots(formation, format);
          expect(
            slots.length,
            playersOnPitch(format),
            reason: '$format $formation',
          );
          expect(slots.map((s) => s.code).toSet().length, slots.length);
          expect(
            slots.every((s) => s.x >= 0 && s.x <= 1 && s.y >= 0 && s.y <= 1),
            isTrue,
          );
        }
      }
      expect(
        formationSlots('1-1-1', '3v3').any((s) => s.code == 'GK'),
        isFalse,
      );
      expect(formationSlots('4-3-3', '11v11').first.label, 'MV');
      expect(formationSlots('4-3-3', '11v11').map((s) => s.label).toList(), [
        'MV', 'VB', 'MB', 'MB', 'HB', 'VM', 'CM', 'HM', 'VY', 'ANF', 'HY', //
      ]);
      expect(formationSlots('x-2', '7v7'), isEmpty);
    });

    test('auto fill places players by main position, then anyone', () {
      final slots = formationSlots('2-3-1', '7v7');
      final filled = autoFill(slots, const {}, [
        (personId: 'striker', main: 'striker', positions: const []),
        (personId: 'keeper', main: 'goalkeeper', positions: const []),
        (personId: 'back', main: 'left_back', positions: const []),
        (personId: 'any', main: null, positions: const ['central_midfielder']),
        (personId: 'other', main: null, positions: const []),
      ]);
      expect(filled['GK'], 'keeper');
      expect(filled['1A'], 'back');
      expect(filled['3A'], 'striker');
      expect(filled['2A'], 'any');
      expect(filled.values.toSet().length, 5);
      expect(
        autoFill(
          slots,
          {'GK': 'keeper'},
          [(personId: 'keeper', main: 'goalkeeper', positions: const [])],
        ),
        {'GK': 'keeper'},
      );
    });

    test('reads the line-up with places, numbers and the plan', () {
      final lineup = MatchLineup.fromJson({
        'can_edit': true,
        'published': false,
        'revision': 3,
        'formation': '2-3-1',
        'match_format': '7v7',
        'starters': [
          {
            'person_id': 'a',
            'name': 'Mia',
            'number': 1,
            'slot': 'GK',
            'x': 0.06,
            'y': 0.5,
          },
          {'person_id': 'b', 'name': 'Ali', 'position': 'VB'},
        ],
        'substitutes': [
          {'person_id': 'c', 'name': 'Noa', 'number': 12},
        ],
        'substitution_plan': [
          {
            'id': 's',
            'minute': 30,
            'out_id': 'b',
            'in_id': 'c',
            'note': 'om vi leder',
          },
        ],
        'players': [
          {
            'person_id': 'a',
            'name': 'Mia',
            'main_position': 'goalkeeper',
            'positions': ['goalkeeper'],
          },
        ],
      });
      expect(lineup.starters.first.x, 0.06);
      expect(lineup.starters.last.slot, isNull);
      expect(lineup.substitutes.single.number, 12);
      expect(lineup.plan.single.toJson(), {
        'id': 's',
        'out_id': 'b',
        'in_id': 'c',
        'minute': 30,
        'note': 'om vi leder',
      });
      expect(lineup.players.single.mainPosition, 'goalkeeper');
      expect(lineup.isEmpty, isFalse);
    });
  });
}
