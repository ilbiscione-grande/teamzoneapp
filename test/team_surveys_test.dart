import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/core/push/push_services.dart';
import 'package:teamzone_app/src/features/team_development/team_survey_services.dart';

void main() {
  final token = 'a' * 32;

  test('a survey is read with its links and answers', () {
    final survey = TeamSurvey.fromJson({
      'id': 's1',
      'team_id': 't1',
      'title': 'Inför spelarsamtal',
      'intro': '',
      'state': 'open',
      'can_edit': true,
      'open_token': token,
      'questions': [
        {'id': 'q1abc', 'kind': 'scale', 'label': 'Trivsel', 'required': true},
        {
          'id': 'q2abc',
          'kind': 'multi',
          'label': 'Position',
          'options': ['Back', 'Mitt'],
        },
      ],
      'invites': [
        {
          'id': 'i1',
          'person_id': 'p1',
          'name': 'Ada',
          'token': token,
          'has_account': true,
          'answered_at': '2026-11-22T10:00:00Z',
        },
      ],
      'responses': [
        {
          'id': 'r1',
          'invite_id': 'i1',
          'person_id': 'p1',
          'person_name': 'Ada',
          'answers': {
            'q1abc': 4,
            'q2abc': ['Back'],
          },
          'submitted_at': '2026-11-22T10:00:00Z',
          'updated_at': '2026-11-22T10:00:00Z',
        },
      ],
      'players': [
        {'person_id': 'p1', 'name': 'Ada', 'has_account': true},
        {'person_id': 'p2', 'name': 'Bo', 'has_account': false},
      ],
    });
    expect(survey.open, isTrue);
    expect(survey.uninvited.map((p) => p.name), ['Bo']);
    expect(survey.responseOf(survey.invites.single)?.name, 'Ada');
    expect(survey.openUrl, endsWith('/enkat/$token'));
    expect(survey.questions.first.describe(4), '4 av 5');
    expect(survey.questions.last.describe(['Back', 'Mitt']), 'Back, Mitt');
    expect(survey.questions.last.toJson()['options'], ['Back', 'Mitt']);
    expect(survey.questions.first.toJson().containsKey('options'), isFalse);
  });

  test('a survey link from a notification is allowed and kept', () {
    expect(PushRoutes.safe('/enkat/$token'), '/enkat/$token');
    expect(PushRoutes.safe('/enkat/../x'), isNull);
    expect(ProductRouteContract.isCanonical('/enkat/$token'), isTrue);
    expect(
      ProductRouteContract.canonicalInitialLocation('/enkat/$token'),
      '/enkat/$token',
    );
  });

  test('a refusal is told in words', () {
    expect(
      const TeamSurveyException('survey_has_answers').message(true),
      contains('har svar'),
    );
  });
}
