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

  test('a link is sent to the player\'s phone or email', () {
    final message = surveyInviteMessage(
      name: 'Ada Lund',
      title: 'Inför spelarsamtal',
      url: 'https://x/enkat/$token',
    );
    expect(message, startsWith('Hej Ada! '));
    expect(message, endsWith('https://x/enkat/$token'));
    expect(whatsAppNumber('070-111 22 33'), '46701112233');
    expect(whatsAppNumber('+46 70 111 22 33'), '46701112233');
    expect(whatsAppNumber('0047 412 34 567'), '4741234567');
    expect(whatsAppNumber('123'), isNull);
    expect(
      whatsAppUri('a b', phone: '0701112233').toString(),
      'https://wa.me/46701112233?text=a%20b',
    );
    expect(whatsAppUri('a').toString(), 'https://wa.me/?text=a');
    expect(
      smsUri('a&b', phone: '070-111 22 33').toString(),
      'sms:0701112233?body=a%26b',
    );
    expect(
      emailUri('hej', email: 'ada@example.test', subject: 'Enkät').toString(),
      'mailto:ada%40example.test?subject=Enk%C3%A4t&body=hej',
    );
  });

  test('the statistics count answers, averages and choices', () {
    Map<String, Object?> response(String id, String name, Object answers) => {
      'id': id,
      'invite_id': null,
      'respondent_name': name,
      'answers': answers,
      'submitted_at': '2026-11-22T10:00:00Z',
      'updated_at': '2026-11-22T10:00:00Z',
    };
    final survey = TeamSurvey.fromJson({
      'id': 's1',
      'team_id': 't1',
      'state': 'open',
      'reminded': 2,
      'questions': [
        {'id': 'q1abc', 'kind': 'scale', 'label': 'Trivsel'},
        {'id': 'q2abc', 'kind': 'scale', 'label': 'Träning'},
        {
          'id': 'q3abc',
          'kind': 'multi',
          'label': 'Utveckla',
          'options': ['Skott', 'Pass'],
        },
        {'id': 'q4abc', 'kind': 'long_text', 'label': 'Mer\tnu'},
      ],
      'invites': [
        {
          'id': 'i1',
          'person_id': 'p1',
          'name': 'Ada',
          'token': token,
          'has_account': true,
          'phone': '070',
        },
        {
          'id': 'i2',
          'person_id': 'p2',
          'name': 'Bo',
          'token': token,
          'has_account': true,
          'reminded_at': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'id': 'i3',
          'person_id': 'p3',
          'name': 'Cia',
          'token': token,
          'answered_at': '2026-11-22T10:00:00Z',
        },
      ],
      'responses': [
        response('r1', 'Ada', {
          'q1abc': 4,
          'q2abc': 2,
          'q3abc': ['Skott', 'Pass'],
          'q4abc': 'Rad ett\nrad två',
        }),
        response('r2', 'Bo', {
          'q1abc': 5,
          'q3abc': ['Skott'],
        }),
      ],
    });
    expect(survey.reminded, 2);
    expect(survey.invites.first.phone, '070');
    expect(survey.remindable, 1, reason: 'Ada: Bo was just reminded');
    expect(survey.responseRate, closeTo(1 / 3, 0.001));
    expect(survey.average(survey.questions[0]), 4.5);
    expect(survey.average(survey.questions[1]), 2);
    expect(survey.scaleAverage, 3.25);
    expect(survey.optionCounts(survey.questions[2]), {'Skott': 2, 'Pass': 1});
    final table = survey.toTable().split('\n');
    expect(table.first, 'Namn\tSvarade\tTrivsel\tTräning\tUtveckla\tMer nu');
    expect(table[1], endsWith('\t4 av 5\t2 av 5\tSkott, Pass\tRad ett rad två'));
    expect(table[2].split('\t'), hasLength(6));
  });

  test('my surveys are read for the home page', () {
    final mine = MySurvey.fromJson({
      'survey_id': 's1',
      'title': 'Inför spelarsamtal',
      'team_name': 'P2012',
      'token': token,
    });
    expect(mine.answeredAt, isNull);
    expect(mine.url, endsWith('/enkat/$token'));
    final answer = PlayerSurveyAnswer.fromJson({
      'survey_id': 's1',
      'title': 'X',
      'questions': const [],
      'answers': const {},
      'updated_at': '2026-11-22T10:00:00Z',
      'response_count': 11,
      'averages': {'q1abc': 1.64, 'q2abc': null},
    });
    expect(answer.responseCount, 11);
    expect(answer.averages, {'q1abc': 1.64});
  });
}
