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
    this.answeredAt,
  });
  factory SurveyInvite.fromJson(Map<String, dynamic> json) => SurveyInvite(
    id: json['id'] as String,
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    token: json['token'] as String,
    hasAccount: json['has_account'] == true,
    notifiedAt: _time(json['notified_at']),
    answeredAt: _time(json['answered_at']),
  );
  final String id, personId, name, token;
  final bool hasAccount;
  final DateTime? notifiedAt, answeredAt;
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
  );
  final String id, teamId, title, intro, state;
  final List<SurveyQuestion> questions;
  final bool canEdit;
  final String? openToken;
  final List<SurveyInvite> invites;
  final List<SurveyResponse> responses;
  final List<SurveyPlayer> players;

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
}

/// A player's answer in one of the team's surveys, for the player's page.
class PlayerSurveyAnswer {
  const PlayerSurveyAnswer({
    required this.surveyId,
    required this.title,
    required this.questions,
    required this.answers,
    required this.updatedAt,
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
      );
  final String surveyId, title;
  final List<SurveyQuestion> questions;
  final Map<String, dynamic> answers;
  final DateTime updatedAt;
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
