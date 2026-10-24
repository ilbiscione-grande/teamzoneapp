import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/match_workspace/match_plan_services.dart';

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
  group('match live (match module, step 3)', () {
    test('who is on the pitch follows the substitutions in order', () {
      final facts = [
        _fact('substitution', 60, player: 'b', second: 'd'),
        _fact('substitution', 30, player: 'a', second: 'c'),
        _fact('substitution', 70, player: 'c', second: 'a'),
        _fact('substitution', 50, player: 'x', second: 'y', state: 'voided'),
        _fact('substitution', 55, side: 'opponent', player: 'b'),
        _fact('goal', 10, player: 'a'),
      ];
      expect(onPitch(['a', 'b'], facts), ['a', 'd']);
      expect(onPitch(['a', 'b'], const []), ['a', 'b']);
    });

    test('a planned substitution is done once a substitution carries it', () {
      final facts = [
        _fact('substitution', 30, detail: {'plan_id': 'p1'}),
        _fact('substitution', 40, detail: {'plan_id': 'p2'}, state: 'voided'),
        _fact('shot', 41, detail: {'plan_id': 'p3'}),
      ];
      expect(donePlannedSubstitutions(facts), {'p1'});
    });

    test('the tally counts standing events per side', () {
      final facts = [
        _fact('shot', 1),
        _fact('shot', 2),
        _fact('shot', 3, side: 'opponent'),
        _fact('corner', 4, state: 'voided'),
      ];
      expect(eventTally(facts, 'us'), {'shot': 2});
      expect(eventTally(facts, 'opponent'), {'shot': 1});
    });

    test('every kind is one Match Space v2 records, with a known result', () {
      const recorded = {
        'substitution', 'goal', 'card', 'injury', 'corner', 'free_kick', //
        'penalty', 'save', 'half_time', 'shot',
      };
      for (final kind in liveEventKinds) {
        expect(recorded.contains(kind.type), isTrue, reason: kind.type);
        if (kind.defaultResult != null) {
          expect(kind.results.map((r) => r.$1), contains(kind.defaultResult));
        }
      }
      expect(liveEventKind('card')!.resultKey, 'color');
      expect(liveEventKind('goal'), isNull);
    });

    test('placed shots and goals make the shot map, from our attack', () {
      final facts = [
        _fact(
          'shot',
          5,
          detail: {
            'result': 'on_target',
            'location': {'x': 0.8, 'y': 0.4},
          },
        ),
        _fact(
          'goal',
          9,
          detail: {
            'location': {'x': 0.9, 'y': 1.4},
          },
        ),
        _fact(
          'shot',
          12,
          side: 'opponent',
          detail: {
            'location': {'x': 0.2, 'y': 0.5},
          },
        ),
        _fact('shot', 14, detail: {'result': 'missed'}),
        _fact(
          'card',
          15,
          detail: {
            'location': {'x': 0.5, 'y': 0.5},
          },
        ),
        _fact(
          'shot',
          16,
          state: 'voided',
          detail: {
            'location': {'x': 0.7, 'y': 0.5},
          },
        ),
      ];
      expect(shotPoints(facts), [
        (x: 0.8, y: 0.4, side: 'us', outcome: 'on_target', id: ''),
        (x: 0.9, y: 1.0, side: 'us', outcome: 'goal', id: ''),
        (x: 0.2, y: 0.5, side: 'opponent', outcome: 'missed', id: ''),
      ]);
      expect(locationDetail(0.12345, 1.2), {'x': 0.123, 'y': 1.0});
      expect(factLocation(facts[3]), isNull);
      expect(
        liveEventKinds.where((k) => k.locatable).map((k) => k.type).toSet(),
        {'shot', 'card', 'free_kick', 'injury'},
      );
    });

    test('own buttons count their standing taps; Min vy hides the rest', () {
      final buttons = MatchButtons.fromJson({
        'buttons': [
          {'id': 'wins', 'label': 'Brytningar'},
        ],
        'revision': 2,
        'can_edit': true,
        'my_view': ['shot', 'button:wins'],
      });
      expect(buttons.buttons.single.toJson(), {
        'id': 'wins',
        'label': 'Brytningar',
      });
      expect(buttons.myView, {'shot', 'button:wins'});
      expect(MatchButtons.fromJson({'my_view': null}).myView, isNull);
      expect(shownInView(buttons.myView, buttonKey('wins')), isTrue);
      expect(shownInView(buttons.myView, kpiKey('t1')), isFalse);
      expect(shownInView(null, noteKey), isTrue);
      final facts = [
        _fact('kpi', 3, detail: {'button_id': 'wins'}),
        _fact('kpi', 4, detail: {'button_id': 'wins'}),
        _fact('kpi', 5, detail: {'button_id': 'wins'}, state: 'voided'),
        _fact('kpi', 6, detail: {'target_id': 't1'}),
      ];
      expect(buttonCounts(facts), {'wins': 2});
    });
  });
}
