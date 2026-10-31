import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/match_workspace/match_plan_models.dart';

void main() {
  test('the plan reads its Tacticsboard boards apart from its links', () {
    final plan = MatchPlan.fromJson({
      'event_id': 'e',
      'can_edit': false,
      'published': true,
      'revision': 3,
      'sections': <String, dynamic>{},
      'links': <Object>[],
      'boards': [
        {
          'id': 'a',
          'title': 'Press · Matchplan',
          'visible': true,
          'project_id': 'p',
          'board_id': 'B',
        },
      ],
    });
    expect(plan.boards.single.title, 'Press · Matchplan');
    expect(plan.boards.single.visible, isTrue);
    expect(plan.isEmpty, isFalse, reason: 'a board alone is worth a card');
    expect(
      MatchPlan.fromJson({'sections': <String, dynamic>{}}).boards,
      isEmpty,
    );
  });

  test('a board draws its first frame in the view it is set to', () {
    final board = MatchPlanBoard.fromJson({
      'id': 'a',
      'title': 'Press',
      'visible': true,
      'preview': {
        'view': 'attack',
        'teams': {
          'home': {'color': '#f00', 'numberColor': '#fff'},
        },
        'objects': [
          {'type': 'player', 'side': 'home', 'x': 80, 'y': 34, 'number': 9},
          {'type': 'player', 'side': 'away', 'x': 10, 'y': 34},
          {'type': 'ball', 'x': 81, 'y': 34, 'attachedTo': null},
          {'type': 'ball', 'x': 60, 'y': 30, 'attachedTo': 'p'},
          {'type': 'arrow', 'x': 70, 'y': 30},
        ],
      },
    });
    final preview = board.preview!;
    expect(preview.aspect, closeTo(58.5 / 74, 1e-9));
    expect(
      preview.dots.map((dot) => (dot.label, dot.ball)),
      [('9', false), ('', true)],
      reason: 'the away player is outside the attacking half',
    );
    expect(preview.dots.first.fill, 0xffff0000);
    expect(preview.dots.first.left, closeTo((80 - 49.5) / 58.5, 1e-9));
    expect(
      MatchPlanBoard.fromJson({'id': 'b', 'title': 'Borta'}).preview,
      isNull,
    );
  });

  test('a project to choose lists its boards', () {
    final choice = TacticsBoardChoice.fromJson({
      'project_id': 'p',
      'name': 'Matchplan',
      'team_name': 'P2012',
      'boards': [
        {'id': 'A', 'name': 'Uppspel'},
        {'id': 'B', 'name': 'Press'},
      ],
    });
    expect(choice.boards.map((board) => board.name), ['Uppspel', 'Press']);
    expect(choice.teamName, 'P2012');
  });
}
