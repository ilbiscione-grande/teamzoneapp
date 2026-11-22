/// Enkäter in Säsongsplanering (decided by the product owner 2026-11-22):
/// the team's leaders write a short survey, for instance before individual
/// player talks, share a personal link per player and an optional open
/// link, and keep the answers as a basis for the talks. The players answer
/// on Webtools' page `/enkat/<token>` without an account. Only the team's
/// leaders with Säsongsplanering see the answers.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// TeamZone Webtools, where a survey is answered.
const surveyWebtoolsOrigin = String.fromEnvironment(
  'WEBTOOLS_ORIGIN',
  defaultValue:
      'https://teamzoneapp-webtools--teamzoneapp-b02a2.europe-west4.hosted.app',
);

/// The page a link opens.
String surveyLinkUrl(String token) => '$surveyWebtoolsOrigin/enkat/$token';

enum SurveyQuestionKind {
  text('text', 'Kort svar', 'Short answer'),
  longText('long_text', 'Längre svar', 'Long answer'),
  scale('scale', 'Skala 1–5', 'Scale 1–5'),
  single('single', 'Ett alternativ', 'One choice'),
  multi('multi', 'Flera alternativ', 'Several choices');

  const SurveyQuestionKind(this.key, this.sv, this.en);
  final String key, sv, en;
  bool get hasOptions => this == single || this == multi;

  static SurveyQuestionKind parse(Object? value) =>
      values.firstWhere((kind) => kind.key == value, orElse: () => text);
}

class SurveyQuestion {
  const SurveyQuestion({
    required this.id,
    required this.kind,
    required this.label,
    this.required = false,
    this.options = const [],
    this.low = '',
    this.high = '',
  });
  factory SurveyQuestion.fromJson(Map<String, dynamic> json) => SurveyQuestion(
    id: json['id'] as String? ?? '',
    kind: SurveyQuestionKind.parse(json['kind']),
    label: json['label'] as String? ?? '',
    required: json['required'] == true,
    options: _strings(json['options']),
    low: json['low'] as String? ?? '',
    high: json['high'] as String? ?? '',
  );
  final String id, label, low, high;
  final SurveyQuestionKind kind;
  final bool required;
  final List<String> options;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.key,
    'label': label,
    'required': required,
    if (kind.hasOptions) 'options': options,
    if (kind == SurveyQuestionKind.scale) ...{'low': low, 'high': high},
  };

  SurveyQuestion copyWith({
    SurveyQuestionKind? kind,
    String? label,
    bool? required,
    List<String>? options,
    String? low,
    String? high,
  }) => SurveyQuestion(
    id: id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    required: required ?? this.required,
    options: options ?? this.options,
    low: low ?? this.low,
    high: high ?? this.high,
  );

  /// An answer in words: a scale as "4 av 5", choices joined.
  String describe(Object? answer, {bool swedish = true}) => switch (answer) {
    null => '',
    final int value when kind == SurveyQuestionKind.scale =>
      swedish ? '$value av 5' : '$value of 5',
    final List<dynamic> picked => picked.join(', '),
    _ => '$answer',
  };
}

class SurveySummary {
  const SurveySummary({
    required this.id,
    required this.title,
    required this.state,
    required this.questionCount,
    required this.invited,
    required this.answered,
    required this.openLink,
    required this.createdAt,
  });
  factory SurveySummary.fromJson(Map<String, dynamic> json) => SurveySummary(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    state: json['state'] as String? ?? 'draft',
    questionCount: (json['question_count'] as num?)?.toInt() ?? 0,
    invited: (json['invited'] as num?)?.toInt() ?? 0,
    answered: (json['answered'] as num?)?.toInt() ?? 0,
    openLink: json['open_link'] == true,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
  final String id, title, state;
  final int questionCount, invited, answered;
  final bool openLink;
  final DateTime createdAt;
}

class TeamSurveys {
  const TeamSurveys({required this.canEdit, required this.surveys});
  factory TeamSurveys.fromJson(Map<String, dynamic> json) => TeamSurveys(
    canEdit: json['can_edit'] == true,
    surveys: [
      for (final item in json['surveys'] as List? ?? const [])
        SurveySummary.fromJson(item as Map<String, dynamic>),
    ],
  );
  final bool canEdit;
  final List<SurveySummary> surveys;
}

class SurveyInvite {
  const SurveyInvite({
    required this.id,
    required this.personId,
    required this.name,
    required this.token,
    required this.hasAccount,
    this.notifiedAt,
    this.remindedAt,
    this.answeredAt,
    this.phone,
    this.email,
  });
  factory SurveyInvite.fromJson(Map<String, dynamic> json) => SurveyInvite(
    id: json['id'] as String,
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    token: json['token'] as String,
    hasAccount: json['has_account'] == true,
    notifiedAt: _time(json['notified_at']),
    remindedAt: _time(json['reminded_at']),
    answeredAt: _time(json['answered_at']),
    phone: json['phone'] as String?,
    email: json['email'] as String?,
  );
  final String id, personId, name, token;
  final bool hasAccount;
  final DateTime? notifiedAt, remindedAt, answeredAt;

  /// The player's contact, shown to the team's leaders only.
  final String? phone, email;
  String get url => surveyLinkUrl(token);
}

/// A text with a personal link, for a text message, WhatsApp or email.
String surveyInviteMessage({
  required String name,
  required String title,
  required String url,
  bool swedish = true,
}) {
  final first = name.trim().split(RegExp(r'\s+')).first;
  final hello = first.isEmpty ? '' : ' $first';
  return swedish
      ? 'Hej$hello! Svara gärna på ledarnas enkät "$title". Länken är din egen, så dela den inte med någon annan: $url'
      : 'Hi$hello! Please answer your coaches\' survey "$title". The link is your own, so do not share it: $url';
}

/// A phone number for wa.me: digits only, a Swedish 07… as 467….
String? whatsAppNumber(String? phone) {
  if (phone == null) return null;
  var digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+')) {
    digits = digits.substring(1);
  } else if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = '46${digits.substring(1)}';
  }
  digits = digits.replaceAll('+', '');
  return digits.length < 7 ? null : digits;
}

/// Opens WhatsApp with [text], to [phone] when it is known (otherwise
/// WhatsApp asks whom to send it to).
Uri whatsAppUri(String text, {String? phone}) {
  final number = whatsAppNumber(phone) ?? '';
  return Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
}

/// Opens the text messages with [text], to [phone] when it is known.
Uri smsUri(String text, {String? phone}) {
  final to = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  return Uri.parse('sms:$to?body=${Uri.encodeComponent(text)}');
}

/// Opens the email app with [text], to [email] when it is known.
Uri emailUri(String text, {String? email, required String subject}) =>
    Uri.parse(
      'mailto:${Uri.encodeComponent(email ?? '')}'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(text)}',
    );

/// One of the signed-in person's own links to an open survey.
class MySurvey {
  const MySurvey({
    required this.surveyId,
    required this.title,
    required this.teamName,
    required this.token,
    this.answeredAt,
  });
  factory MySurvey.fromJson(Map<String, dynamic> json) => MySurvey(
    surveyId: json['survey_id'] as String,
    title: json['title'] as String? ?? '',
    teamName: json['team_name'] as String? ?? '',
    token: json['token'] as String,
    answeredAt: _time(json['answered_at']),
  );
  final String surveyId, title, teamName, token;
  final DateTime? answeredAt;
  String get url => surveyLinkUrl(token);
}

class SurveyResponse {
  const SurveyResponse({
    required this.id,
    required this.answers,
    required this.submittedAt,
    required this.updatedAt,
    this.inviteId,
    this.personId,
    this.personName,
    this.respondentName,
  });
  factory SurveyResponse.fromJson(Map<String, dynamic> json) => SurveyResponse(
    id: json['id'] as String,
    inviteId: json['invite_id'] as String?,
    personId: json['person_id'] as String?,
    personName: json['person_name'] as String?,
    respondentName: json['respondent_name'] as String?,
    answers: Map<String, dynamic>.from(json['answers'] as Map? ?? const {}),
    submittedAt: DateTime.parse(json['submitted_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );
  final String id;
  final String? inviteId, personId, personName, respondentName;
  final Map<String, dynamic> answers;
  final DateTime submittedAt, updatedAt;

  /// Through the open link (the name was written by whoever answered).
  bool get open => inviteId == null;
  String get name => personName ?? respondentName ?? '';
}

class SurveyPlayer {
  const SurveyPlayer({
    required this.personId,
    required this.name,
    required this.hasAccount,
  });
  factory SurveyPlayer.fromJson(Map<String, dynamic> json) => SurveyPlayer(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    hasAccount: json['has_account'] == true,
  );
  final String personId, name;
  final bool hasAccount;
}

class TeamSurvey {
  const TeamSurvey({
    required this.id,
    required this.teamId,
    required this.title,
    required this.intro,
    required this.questions,
    required this.state,
    required this.canEdit,
    this.openToken,
    this.invites = const [],
    this.responses = const [],
    this.players = const [],
    this.reminded,
  });
  factory TeamSurvey.fromJson(Map<String, dynamic> json) => TeamSurvey(
    id: json['id'] as String,
    teamId: json['team_id'] as String,
    title: json['title'] as String? ?? '',
    intro: json['intro'] as String? ?? '',
    questions: [
      for (final item in json['questions'] as List? ?? const [])
        SurveyQuestion.fromJson(item as Map<String, dynamic>),
    ],
    state: json['state'] as String? ?? 'draft',
    canEdit: json['can_edit'] == true,
    openToken: json['open_token'] as String?,
    invites: [
      for (final item in json['invites'] as List? ?? const [])
        SurveyInvite.fromJson(item as Map<String, dynamic>),
    ],
    responses: [
      for (final item in json['responses'] as List? ?? const [])
        SurveyResponse.fromJson(item as Map<String, dynamic>),
    ],
    players: [
      for (final item in json['players'] as List? ?? const [])
        SurveyPlayer.fromJson(item as Map<String, dynamic>),
    ],
    reminded: (json['reminded'] as num?)?.toInt(),
  );
  final String id, teamId, title, intro, state;
  final List<SurveyQuestion> questions;
  final bool canEdit;
  final String? openToken;
  final List<SurveyInvite> invites;
  final List<SurveyResponse> responses;
  final List<SurveyPlayer> players;

  /// After a reminder: how many were reminded.
  final int? reminded;

  bool get draft => state == 'draft';
  bool get open => state == 'open';
  bool get closed => state == 'closed';
  bool get hasAnswers => responses.isNotEmpty;
  String? get openUrl => openToken == null ? null : surveyLinkUrl(openToken!);

  /// The team's players without a personal link yet.
  List<SurveyPlayer> get uninvited => [
    for (final player in players)
      if (!invites.any((invite) => invite.personId == player.personId)) player,
  ];

  SurveyResponse? responseOf(SurveyInvite invite) =>
      responses.where((response) => response.inviteId == invite.id).firstOrNull;

  /// Players with an account who have not answered and were not reminded
  /// in the last 12 hours: a reminder reaches them.
  int get remindable => invites
      .where(
        (invite) =>
            invite.hasAccount &&
            invite.answeredAt == null &&
            (invite.remindedAt == null ||
                DateTime.now().difference(invite.remindedAt!) >
                    const Duration(hours: 12)),
      )
      .length;

  /// The share of personal links answered, or null without links.
  double? get responseRate => invites.isEmpty
      ? null
      : invites.where((invite) => invite.answeredAt != null).length /
            invites.length;

  /// The answers given to [question].
  List<SurveyResponse> answersTo(SurveyQuestion question) => [
    for (final response in responses)
      if (response.answers[question.id] != null) response,
  ];

  /// A scale question's answers, 1–5.
  List<int> scaleValues(SurveyQuestion question) => [
    for (final response in answersTo(question))
      if (response.answers[question.id] case final num value) value.toInt(),
  ];

  /// A scale question's average, or null before anyone answered.
  double? average(SurveyQuestion question) {
    final values = scaleValues(question);
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  /// How many chose each option of a choice question, in the options'
  /// order.
  Map<String, int> optionCounts(SurveyQuestion question) => {
    for (final option in question.options)
      option: answersTo(question).where((response) {
        final answer = response.answers[question.id];
        return answer == option || (answer is List && answer.contains(option));
      }).length,
  };

  /// The average of all the scale questions' averages.
  double? get scaleAverage {
    final averages = [
      for (final question in questions)
        if (question.kind == SurveyQuestionKind.scale)
          if (average(question) case final double value) value,
    ];
    return averages.isEmpty
        ? null
        : averages.reduce((a, b) => a + b) / averages.length;
  }

  /// The answers as a table (one row per person, one column per question),
  /// with tabs between the columns, as a spreadsheet takes a paste.
  String toTable({bool swedish = true}) {
    String cell(String value) =>
        value.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
    String time(DateTime at) =>
        at.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
    final rows = [
      [
        swedish ? 'Namn' : 'Name',
        swedish ? 'Svarade' : 'Answered',
        for (final question in questions) question.label,
      ],
      for (final response in responses)
        [
          response.name,
          time(response.updatedAt),
          for (final question in questions)
            question.describe(response.answers[question.id], swedish: swedish),
        ],
    ];
    return rows.map((row) => row.map(cell).join('\t')).join('\n');
  }
}

/// A player's answer in one of the team's surveys, for the player's page.
class PlayerSurveyAnswer {
  const PlayerSurveyAnswer({
    required this.surveyId,
    required this.title,
    required this.questions,
    required this.answers,
    required this.updatedAt,
    this.responseCount = 0,
    this.averages = const {},
  });
  factory PlayerSurveyAnswer.fromJson(Map<String, dynamic> json) =>
      PlayerSurveyAnswer(
        surveyId: json['survey_id'] as String,
        title: json['title'] as String? ?? '',
        questions: [
          for (final item in json['questions'] as List? ?? const [])
            SurveyQuestion.fromJson(item as Map<String, dynamic>),
        ],
        answers: Map<String, dynamic>.from(json['answers'] as Map? ?? const {}),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        responseCount: (json['response_count'] as num?)?.toInt() ?? 0,
        averages: {
          for (final MapEntry(:key, :value)
              in (json['averages'] as Map? ?? const {}).entries)
            if (value is num) '$key': value.toDouble(),
        },
      );
  final String surveyId, title;
  final List<SurveyQuestion> questions;
  final Map<String, dynamic> answers;
  final DateTime updatedAt;

  /// How many answered the survey, and the team's average per scale
  /// question.
  final int responseCount;
  final Map<String, double> averages;
}

/// A change the server refused, with what to tell the leader.
class TeamSurveyException implements Exception {
  const TeamSurveyException(this.code);
  final String code;

  static const codes = [
    'survey_has_answers',
    'survey_without_questions',
    'invalid_title',
    'invalid_questions',
    'invalid_options',
    'invite_answered',
    'invite_needs_player_role',
    'link_needs_player_role',
    'too_many_surveys',
    'survey_not_open',
    'read_only',
    'not_found',
  ];

  String message(bool swedish) => switch (code) {
    'survey_has_answers' =>
      swedish
          ? 'Enkäten har svar, så frågorna kan inte ändras. Rubriken och texten går att ändra.'
          : 'The survey has answers, so the questions cannot change.',
    'survey_without_questions' =>
      swedish
          ? 'Lägg till minst en fråga innan du öppnar enkäten.'
          : 'Add a question before opening the survey.',
    'invalid_title' => swedish ? 'Skriv en rubrik.' : 'Write a title.',
    'invalid_questions' =>
      swedish ? 'Varje fråga behöver en text.' : 'Every question needs a text.',
    'invalid_options' =>
      swedish
          ? 'Ett flervalsalternativ behöver 2–12 olika alternativ.'
          : 'A choice question needs 2–12 different options.',
    'invite_answered' =>
      swedish
          ? 'Spelaren har svarat. Ta bort svaret först.'
          : 'The player has answered. Delete the answer first.',
    'invite_needs_player_role' || 'link_needs_player_role' =>
      swedish
          ? 'Bara lagets spelare kan få en länk.'
          : 'Only the team\'s players can get a link.',
    'survey_not_open' =>
      swedish
          ? 'Öppna enkäten först, så att länkarna tar emot svar.'
          : 'Open the survey first.',
    'too_many_surveys' =>
      swedish ? 'Laget har för många enkäter.' : 'Too many surveys.',
    'read_only' =>
      swedish
          ? 'Säsongsplanering är bara läsbar för klubben just nu.'
          : 'Season planning is read-only for the club.',
    _ =>
      swedish
          ? 'Enkäten finns inte, eller så saknar du behörighet.'
          : 'The survey is not available.',
  };
}

abstract interface class TeamSurveyServices {
  Future<TeamSurveys> list(String teamId);
  Future<TeamSurvey> get(String surveyId);

  /// A new survey when [surveyId] is null.
  Future<TeamSurvey> save({
    required String teamId,
    String? surveyId,
    required String title,
    required String intro,
    required List<SurveyQuestion> questions,
  });
  Future<TeamSurvey> setState(String surveyId, String state);
  Future<TeamSurvey> setOpenLink(String surveyId, bool enabled);
  Future<TeamSurvey> invite(String surveyId, List<String> personIds);
  Future<TeamSurvey> removeInvite(String inviteId);
  Future<TeamSurvey> linkResponse(String responseId, String? personId);
  Future<TeamSurvey> deleteResponse(String responseId);
  Future<void> delete(String surveyId);
  Future<List<PlayerSurveyAnswer>> playerAnswers(
    String teamId,
    String personId,
  );

  /// A notification to the players with an account who have not answered.
  Future<TeamSurvey> remind(String surveyId);

  /// The signed-in person's own links to open surveys.
  Future<List<MySurvey>> mine();
}

class UnconfiguredTeamSurveyServices implements TeamSurveyServices {
  const UnconfiguredTeamSurveyServices();
  StateError get _error => StateError('Supabase is not configured.');
  @override
  Future<TeamSurveys> list(String teamId) => Future.error(_error);
  @override
  Future<TeamSurvey> get(String surveyId) => Future.error(_error);
  @override
  Future<TeamSurvey> save({
    required String teamId,
    String? surveyId,
    required String title,
    required String intro,
    required List<SurveyQuestion> questions,
  }) => Future.error(_error);
  @override
  Future<TeamSurvey> setState(String surveyId, String state) =>
      Future.error(_error);
  @override
  Future<TeamSurvey> setOpenLink(String surveyId, bool enabled) =>
      Future.error(_error);
  @override
  Future<TeamSurvey> invite(String surveyId, List<String> personIds) =>
      Future.error(_error);
  @override
  Future<TeamSurvey> removeInvite(String inviteId) => Future.error(_error);
  @override
  Future<TeamSurvey> linkResponse(String responseId, String? personId) =>
      Future.error(_error);
  @override
  Future<TeamSurvey> deleteResponse(String responseId) => Future.error(_error);
  @override
  Future<void> delete(String surveyId) => Future.error(_error);
  @override
  Future<List<PlayerSurveyAnswer>> playerAnswers(
    String teamId,
    String personId,
  ) => Future.error(_error);
  @override
  Future<TeamSurvey> remind(String surveyId) => Future.error(_error);
  @override
  Future<List<MySurvey>> mine() async => const [];
}

class SupabaseTeamSurveyServices implements TeamSurveyServices {
  SupabaseTeamSurveyServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    try {
      return await _client
          .schema('api')
          .rpc<Object?>(name, params: params)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (error) {
      final code = TeamSurveyException.codes
          .where(error.message.contains)
          .firstOrNull;
      if (code != null) throw TeamSurveyException(code);
      rethrow;
    }
  }

  Future<TeamSurvey> _survey(String name, Map<String, Object?> params) async {
    final value = await _rpc(name, params);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid survey response.');
    }
    return TeamSurvey.fromJson(value);
  }

  @override
  Future<TeamSurveys> list(String teamId) async {
    final value = await _rpc('list_team_surveys', {'target_team_id': teamId});
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid survey list.');
    }
    return TeamSurveys.fromJson(value);
  }

  @override
  Future<TeamSurvey> get(String surveyId) =>
      _survey('get_team_survey', {'target_survey_id': surveyId});

  @override
  Future<TeamSurvey> save({
    required String teamId,
    String? surveyId,
    required String title,
    required String intro,
    required List<SurveyQuestion> questions,
  }) => _survey('save_team_survey', {
    'target_team_id': teamId,
    'target_survey_id': surveyId,
    'new_title': title,
    'new_intro': intro,
    'new_questions': [for (final question in questions) question.toJson()],
  });

  @override
  Future<TeamSurvey> setState(String surveyId, String state) => _survey(
    'set_team_survey_state',
    {'target_survey_id': surveyId, 'new_state': state},
  );

  @override
  Future<TeamSurvey> setOpenLink(String surveyId, bool enabled) => _survey(
    'set_team_survey_open_link',
    {'target_survey_id': surveyId, 'enabled': enabled},
  );

  @override
  Future<TeamSurvey> invite(String surveyId, List<String> personIds) => _survey(
    'invite_team_survey_players',
    {'target_survey_id': surveyId, 'person_ids': personIds},
  );

  @override
  Future<TeamSurvey> removeInvite(String inviteId) =>
      _survey('remove_team_survey_invite', {'target_invite_id': inviteId});

  @override
  Future<TeamSurvey> linkResponse(String responseId, String? personId) =>
      _survey('link_team_survey_response', {
        'target_response_id': responseId,
        'target_person_id': personId,
      });

  @override
  Future<TeamSurvey> deleteResponse(String responseId) => _survey(
    'delete_team_survey_response',
    {'target_response_id': responseId},
  );

  @override
  Future<void> delete(String surveyId) async =>
      _rpc('delete_team_survey', {'target_survey_id': surveyId});

  @override
  Future<List<PlayerSurveyAnswer>> playerAnswers(
    String teamId,
    String personId,
  ) async {
    final value = await _rpc('get_player_survey_answers', {
      'target_team_id': teamId,
      'target_person_id': personId,
    });
    return [
      for (final item in value as List? ?? const [])
        PlayerSurveyAnswer.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<TeamSurvey> remind(String surveyId) =>
      _survey('remind_team_survey', {'target_survey_id': surveyId});

  @override
  Future<List<MySurvey>> mine() async {
    final value = await _rpc('list_my_team_surveys', const {});
    return [
      for (final item in value as List? ?? const [])
        MySurvey.fromJson(item as Map<String, dynamic>),
    ];
  }
}

/// The services the surveys use, set when Supabase starts.
abstract final class TeamSurveysFeature {
  static TeamSurveyServices services = const UnconfiguredTeamSurveyServices();

  static void configure(SupabaseClient client) =>
      services = SupabaseTeamSurveyServices(client);
}

List<String> _strings(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is String) item,
];

DateTime? _time(Object? value) =>
    value is String ? DateTime.parse(value).toLocal() : null;
