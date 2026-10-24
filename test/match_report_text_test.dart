import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/match_workspace/match_report_text.dart';

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

const _names = {'a': 'Mia', 'b': 'Ali', 'c': 'Noa'};
String _name(String? id) => _names[id] ?? 'Okänd';

String _report(
  List<Map<String, dynamic>> facts, {
  int variant = 0,
  String? homeAway = 'home',
}) => generatedMatchReport(
  team: 'P2012',
  opponent: 'Aneby SK',
  homeAway: homeAway,
  scoreUs: 2,
  scoreOpponent: 1,
  completed: true,
  periodMinutes: const [30, 30],
  name: _name,
  facts: facts,
  variant: variant,
);

void main() {
  test('the match told as a report, then numbers, scorers and goals', () {
    final text = generatedMatchReport(
      team: 'P2012',
      opponent: 'Aneby SK',
      homeAway: 'home',
      scoreUs: 2,
      scoreOpponent: 1,
      completed: true,
      periodMinutes: const [30, 30],
      name: _name,
      facts: [
        _fact('goal', 40, player: 'a'),
        _fact('goal', 12, player: 'a', second: 'b'),
        _fact('goal', 25, side: 'opponent'),
        _fact('goal', 50, player: 'c', state: 'voided'),
        _fact('shot', 13, player: 'b', detail: {'result': 'on_target'}),
        _fact('corner', 14),
        _fact('substitution', 35, player: 'b', second: 'c'),
        _fact('card', 44, side: 'opponent', detail: {'color': 'yellow'}),
        _fact('card', 45, player: 'b', detail: {'color': 'none'}),
        _fact('note', 20, detail: {'text': 'Bra press'}),
        _fact('shot', 52, detail: {'result': 'woodwork'}),
      ],
      kpis: const [
        (label: 'Avslut på mål', value: '4', goal: 'minst 5', achieved: false),
      ],
    );
    expect(
      text,
      'P2012 mötte Aneby SK på hemmaplan och vann med 2–1.\n'
      'I halvtid stod det 1–1.\n'
      '\n'
      'Matchens gång\n'
      'I matchens 12:e spelminut slog hemmalagets Mia till efter en fin '
      'passning från Ali och gav P2012 ledningen med 1–0.\n'
      'I matchens 13:e spelminut fick hemmalagets Ali iväg ett skott på mål, '
      'men gästernas målvakt var med och räddade.\n'
      'Aneby SK kvitterade i 25:e minuten, och det stod 1–1.\n'
      'I matchens 35:e spelminut gjorde P2012 ett byte: Noa kom in och '
      'ersatte Ali.\n'
      'Jublet var stort i 40:e minuten när Mia hittade nätet för P2012. '
      'Det stod nu 2–1.\n'
      'I matchens 44:e spelminut fick gästerna ett gult kort.\n'
      'Det var nära i matchens 52:a spelminut när P2012 sköt i ramen. '
      'Där saknades bara några centimeter.\n'
      '\n'
      'Statistik (P2012–Aneby SK)\n'
      'Avslut 4–1 (på mål 3–1), hörnor 1–0, fouls 1–1.\n'
      '\n'
      'Målskyttar: Mia 2.\n'
      '\n'
      'Matchmål: 0 av 1 uppnådda\n'
      'Avslut på mål: 4 (mål minst 5) ✗',
    );
    expect(text, isNot(contains('Bra press')), reason: 'notes stay out');
  });

  test('wordings vary: shots in a row differ, another variant words anew', () {
    final shots = [
      for (final minute in [3, 7, 11, 21, 22, 31])
        _fact('shot', minute, player: 'b', detail: {'result': 'missed'}),
    ];
    final lines = _report(
      shots,
    ).split('\n').where((line) => line.contains('Ali')).toList();
    expect(lines.length, 6);
    expect(lines.take(5).toSet().length, 5, reason: 'five wordings in turn');
    expect(lines[2], contains('11'));
    expect(_report(shots), contains('21:a'));
    expect(_report(shots), contains('22:a'));
    expect(_report(shots, variant: 1), isNot(_report(shots)));
  });

  test(
    'without a venue the teams are named; without a player, no team twice',
    () {
      final text = _report([
        _fact('shot', 50, detail: {'result': 'woodwork'}),
        _fact('shot', 51, detail: {'result': 'woodwork'}),
        _fact('shot', 52, side: 'opponent', detail: {'result': 'on_target'}),
      ], homeAway: null);
      expect(text, startsWith('P2012 mötte Aneby SK och vann med 2–1.'));
      expect(text, isNot(contains('P2012 fick P2012')));
      expect(text, contains('P2012:s målvakt'));
    },
  );

  test('a match under way, without events, says only how it stands', () {
    expect(
      generatedMatchReport(
        team: 'P2012',
        opponent: 'Aneby SK',
        homeAway: 'away',
        scoreUs: 0,
        scoreOpponent: 0,
        completed: false,
        periodMinutes: const [30, 30],
        name: _name,
        facts: const [],
      ),
      'Det står 0–0 på bortaplan mot Aneby SK.',
    );
  });
}
