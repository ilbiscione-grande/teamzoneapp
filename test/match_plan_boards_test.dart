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
