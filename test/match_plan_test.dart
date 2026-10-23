import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/match_workspace/match_plan_services.dart';

void main() {
  group('match plan (Match module, step 1)', () {
    test('a coach reads every part, with visibility', () {
      final plan = MatchPlan.fromJson({
        'event_id': 'e1',
        'can_edit': true,
        'published': false,
        'revision': 3,
        'opponent_name': 'Aneby SK',
        'home_away': 'home',
        'starts_at': '2026-10-24T13:00:00Z',
        'sections': {
          'tactics': {'text': 'Hög press', 'visible': true},
          'set_pieces': {'text': '', 'visible': true},
          'opponent': {'text': '9:an farlig', 'visible': false},
        },
        'links': [
          {
            'id': 'l1',
            'title': 'Video',
            'url': 'https://v.example',
            'visible': false,
          },
        ],
      });
      expect(plan.canEdit, isTrue);
      expect(plan.revision, 3);
      expect(plan.opponent?.visible, isFalse);
      expect(plan.links.single.title, 'Video');
      expect(plan.isEmpty, isFalse);
    });

    test('a player gets only the shown parts; a hidden part is missing', () {
      final plan = MatchPlan.fromJson({
        'event_id': 'e1',
        'can_edit': false,
        'published': true,
        'revision': 3,
        'sections': {
          'tactics': {'text': 'Hög press', 'visible': true},
          'set_pieces': null,
          'opponent': null,
        },
        'links': [],
      });
      expect(plan.tactics?.text, 'Hög press');
      expect(plan.setPieces, isNull);
      expect(plan.opponent, isNull);
    });

    test('nothing written and no links counts as empty', () {
      final plan = MatchPlan.fromJson({
        'event_id': 'e1',
        'sections': {
          'tactics': {'text': '  ', 'visible': true},
        },
      });
      expect(plan.isEmpty, isTrue);
      expect(plan.revision, 0);
    });

    test('a match in the module list keeps how far it is prepared', () {
      final match = ModuleMatch.fromJson({
        'event_id': 'e1',
        'title': 'Match',
        'starts_at': '2026-10-24T13:00:00Z',
        'state': 'scheduled',
        'plan': 'published',
        'lineup': 'draft',
        'opponent_name': 'Aneby SK',
      });
      expect(
        [match.plan, match.lineup, match.opponentName],
        ['published', 'draft', 'Aneby SK'],
      );
    });
  });
}
