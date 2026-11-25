/// Spelarsamtal, the first part of the individual development plan (decided
/// by the product owner 2026-11-25): a team's leaders write down a talk with
/// a player. Only the team's leaders with Säsongsplanering see it, never the
/// player it is about. What was agreed is kept apart from the leaders'
/// notes, so it can be shared later without them.
library;

import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

class TalkLeader {
  const TalkLeader({
    required this.personId,
    required this.name,
    this.self = false,
  });
  factory TalkLeader.fromJson(Map<String, dynamic> json) => TalkLeader(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    self: json['self'] == true,
  );
  final String personId, name;

  /// The signed-in leader.
  final bool self;
}

class PlayerTalk {
  const PlayerTalk({
    required this.id,
    required this.talkedOn,
    required this.revision,
    this.leaders = const [],
    this.responseId,
    this.surveyTitle,
    this.leaderNotes = '',
    this.agreed = '',
  });
  factory PlayerTalk.fromJson(Map<String, dynamic> json) => PlayerTalk(
    id: json['id'] as String,
    talkedOn: DateTime.parse(json['talked_on'] as String),
    revision: (json['revision'] as num).toInt(),
    leaders: [
      for (final item in json['leaders'] as List? ?? const [])
        TalkLeader.fromJson(item as Map<String, dynamic>),
    ],
    responseId: json['response_id'] as String?,
    surveyTitle: json['survey_title'] as String?,
    leaderNotes: json['leader_notes'] as String? ?? '',
    agreed: json['agreed'] as String? ?? '',
  );
  final String id, leaderNotes, agreed;
  final DateTime talkedOn;
  final int revision;
  final List<TalkLeader> leaders;

  /// The survey answer the talk starts from, while it is there.
  final String? responseId, surveyTitle;
}

/// The talks with a player, newest first, and the team's leaders.
class PlayerTalks {
  const PlayerTalks({
    required this.name,
    required this.canEdit,
    required this.isPlayer,
    this.leaders = const [],
    this.talks = const [],
  });
  factory PlayerTalks.fromJson(Map<String, dynamic> json) => PlayerTalks(
    name: json['name'] as String? ?? '',
    canEdit: json['can_edit'] == true,
    isPlayer: json['is_player'] == true,
    leaders: [
      for (final item in json['leaders'] as List? ?? const [])
        TalkLeader.fromJson(item as Map<String, dynamic>),
    ],
    talks: [
      for (final item in json['talks'] as List? ?? const [])
        PlayerTalk.fromJson(item as Map<String, dynamic>),
    ],
  );
  final String name;
  final bool canEdit, isPlayer;
  final List<TalkLeader> leaders;
  final List<PlayerTalk> talks;
}

/// What is saved of a talk. The id is chosen here, so a save sent again
/// does not make a second talk.
class PlayerTalkDraft {
  const PlayerTalkDraft({
    required this.id,
    required this.talkedOn,
    required this.leaderIds,
    required this.leaderNotes,
    required this.agreed,
    this.responseId,
  });
  final String id, leaderNotes, agreed;
  final DateTime talkedOn;
  final Set<String> leaderIds;
  final String? responseId;

  /// The date as the server takes it.
  String get day =>
      '${talkedOn.year.toString().padLeft(4, '0')}-'
      '${talkedOn.month.toString().padLeft(2, '0')}-'
      '${talkedOn.day.toString().padLeft(2, '0')}';

  /// Whether [talk] already holds what this would save.
  bool matches(PlayerTalk talk) {
    final leaders = {for (final leader in talk.leaders) leader.personId};
    return talk.id == id &&
        talk.leaderNotes == leaderNotes &&
        talk.agreed == agreed &&
        talk.responseId == responseId &&
        talk.talkedOn.year == talkedOn.year &&
        talk.talkedOn.month == talkedOn.month &&
        talk.talkedOn.day == talkedOn.day &&
        leaders.length == leaderIds.length &&
        leaders.containsAll(leaderIds);
  }
}

class PlayerTalkException implements Exception {
  const PlayerTalkException(this.code);
  final String code;

  static const conflict = 'stale_revision';
  static const codes = [
    conflict,
    'talk_needs_player_role',
    'invalid_response',
    'invalid_leaders',
    'invalid_date',
    'text_too_long',
    'read_only',
    'not_found',
  ];

  String message(bool swedish) => switch (code) {
    conflict =>
      swedish
          ? 'Samtalet har ändrats eller tagits bort av någon annan medan du skrev. Kopiera din text, stäng och öppna samtalet igen.'
          : 'Someone else changed or deleted the talk while you wrote. Copy your text, close and open the talk again.',
    'talk_needs_player_role' =>
      swedish
          ? 'Samtal skrivs med lagets spelare.'
          : 'Talks are with the team\'s players.',
    'invalid_response' =>
      swedish
          ? 'Enkätsvaret hör inte längre till spelaren. Välj ett annat eller inget.'
          : 'The survey answer no longer belongs to the player.',
    'invalid_leaders' =>
      swedish
          ? 'En vald ledare finns inte längre i laget.'
          : 'A chosen leader is no longer in the team.',
    'invalid_date' => swedish ? 'Välj ett annat datum.' : 'Pick another date.',
    'text_too_long' =>
      swedish ? 'Texten är för lång.' : 'The text is too long.',
    'read_only' =>
      swedish
          ? 'Säsongsplanering är bara läsbar för klubben just nu.'
          : 'Season planning is read-only for the club.',
    _ =>
      swedish
          ? 'Samtal visas för lagets ledare med Säsongsplanering.'
          : 'Talks show for the team\'s leaders with Season planning.',
  };
}

abstract interface class PlayerTalkServices {
  Future<PlayerTalks> list(String teamId, String personId);

  /// Saves the talk; a new one when [expectedRevision] is null. Returns the
  /// saved revision.
  Future<int> save(
    String teamId,
    String personId,
    PlayerTalkDraft draft,
    int? expectedRevision,
  );
  Future<void> delete(String talkId, int expectedRevision);
}

class UnconfiguredPlayerTalkServices implements PlayerTalkServices {
  const UnconfiguredPlayerTalkServices();
  StateError get _error => StateError('Supabase is not configured.');
  @override
  Future<PlayerTalks> list(String teamId, String personId) =>
      Future.error(_error);
  @override
  Future<int> save(
    String teamId,
    String personId,
    PlayerTalkDraft draft,
    int? expectedRevision,
  ) => Future.error(_error);
  @override
  Future<void> delete(String talkId, int expectedRevision) =>
      Future.error(_error);
}

class SupabasePlayerTalkServices implements PlayerTalkServices {
  SupabasePlayerTalkServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    try {
      return await _client
          .schema('api')
          .rpc<Object?>(name, params: params)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (error) {
      final code = PlayerTalkException.codes
          .where(error.message.contains)
          .firstOrNull;
      if (code != null) throw PlayerTalkException(code);
      rethrow;
    }
  }

  @override
  Future<PlayerTalks> list(String teamId, String personId) async {
    final value = await _rpc('list_player_talks', {
      'target_team_id': teamId,
      'target_person_id': personId,
    });
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid talks.');
    }
    return PlayerTalks.fromJson(value);
  }

  @override
  Future<int> save(
    String teamId,
    String personId,
    PlayerTalkDraft draft,
    int? expectedRevision,
  ) async {
    final value = await _rpc('save_player_talk', {
      'target_team_id': teamId,
      'target_person_id': personId,
      'target_talk_id': draft.id,
      'expected_revision': expectedRevision,
      'new_talked_on': draft.day,
      'new_leader_ids': draft.leaderIds.toList(),
      'new_response_id': draft.responseId,
      'new_notes': draft.leaderNotes,
      'new_agreed': draft.agreed,
    });
    if (value is! Map<String, dynamic> || value['revision'] is! num) {
      throw const FormatException('Invalid talk.');
    }
    return (value['revision'] as num).toInt();
  }

  @override
  Future<void> delete(String talkId, int expectedRevision) async =>
      _rpc('delete_player_talk', {
        'target_talk_id': talkId,
        'expected_revision': expectedRevision,
      });
}

/// The services the talks use, set when Supabase starts.
abstract final class PlayerTalksFeature {
  static PlayerTalkServices services = const UnconfiguredPlayerTalkServices();

  static void configure(SupabaseClient client) =>
      services = SupabasePlayerTalkServices(client);
}

/// A new talk's id.
String newPlayerTalkId() {
  final random = Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
