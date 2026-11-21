/// Föreslå in the match line-up (step 6 of
/// docs/implementation/player-attributes.md): the team's saved formations,
/// with what each place asks for, and the suggestion of who plays where.
/// The same database function suggests in Tacticsboard. Only the team's
/// leaders get them.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// A formation the team saved, or a ready-made one ([template]) with what
/// each place asks for, by name, with its lines ("4-3-3").
class TeamFormationChoice {
  const TeamFormationChoice({
    required this.id,
    required this.name,
    required this.lines,
    required this.matchFormat,
    this.template = false,
  });
  final String id, name, lines, matchFormat;
  final bool template;
}

class TeamFormationList {
  const TeamFormationList({
    this.formations = const [],
    this.customLabels = const {},
  });
  factory TeamFormationList.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    List<TeamFormationChoice> read(String key, {bool template = false}) => [
      for (final row in (map[key] as List? ?? const []))
        if (row is Map)
          TeamFormationChoice(
            id: row['id'] as String? ?? '',
            name: row['name'] as String? ?? '',
            lines: row['lines'] as String? ?? '',
            matchFormat: row['match_format'] as String? ?? '11v11',
            template: template,
          ),
    ];
    return TeamFormationList(
      // The team's own first, then the templates.
      formations: [...read('formations'), ...read('templates', template: true)],
      customLabels: {
        for (final row in (map['custom'] as List? ?? const []))
          if (row is Map)
            row['id'] as String? ?? '': row['label'] as String? ?? '',
      },
    );
  }
  final List<TeamFormationChoice> formations;

  /// The team's own attributes' names, by id.
  final Map<String, String> customLabels;
}

/// One place in the suggestion: who, and why.
class SuggestedPlace {
  const SuggestedPlace({
    required this.code,
    this.personId,
    this.score,
    this.positionFit,
    this.foot,
    this.footFit,
    this.strengths = const [],
    this.development = const [],
  });
  factory SuggestedPlace.fromJson(Map<String, dynamic> json) => SuggestedPlace(
    code: json['code'] as String? ?? '',
    personId: json['person_id'] as String?,
    score: (json['score'] as num?)?.toInt(),
    positionFit: json['position_fit'] as String?,
    foot: json['foot'] as String?,
    footFit: json['foot_fit'] as String?,
    strengths: [
      for (final key in json['strengths'] as List? ?? const [])
        if (key is String) key,
    ],
    development: [
      for (final key in json['development'] as List? ?? const [])
        if (key is String) key,
    ],
  );
  final String code;
  final String? personId, positionFit;

  /// The foot the place asks for (left, right) and how the player's fits:
  /// good, both, weaker or wrong.
  final String? foot, footFit;
  final int? score;
  final List<String> strengths, development;
}

List<SuggestedPlace> suggestedPlacesFromJson(Object? json) {
  final map = json is Map ? json : const {};
  return [
    for (final row in map['slots'] as List? ?? const [])
      if (row is Map) SuggestedPlace.fromJson(Map<String, dynamic>.from(row)),
  ];
}

abstract interface class LineupSuggestionServices {
  /// The team's formations; throws for those who are not its leaders.
  Future<TeamFormationList> formations(String eventId);

  /// Who plays where: a saved formation, or only [lines] in [matchFormat];
  /// [candidates] the players to choose from.
  Future<List<SuggestedPlace>> suggest({
    required String eventId,
    String? formationId,
    required String lines,
    required String matchFormat,
    required List<String> candidates,
  });
}

class UnconfiguredLineupSuggestionServices implements LineupSuggestionServices {
  const UnconfiguredLineupSuggestionServices();
  @override
  Future<TeamFormationList> formations(String eventId) =>
      Future.error(StateError('Line-up suggestions not configured'));
  @override
  Future<List<SuggestedPlace>> suggest({
    required String eventId,
    String? formationId,
    required String lines,
    required String matchFormat,
    required List<String> candidates,
  }) => Future.error(StateError('Line-up suggestions not configured'));
}

class SupabaseLineupSuggestionServices implements LineupSuggestionServices {
  SupabaseLineupSuggestionServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, Map<String, Object?> params) => _client
      .schema('api')
      .rpc<Object?>(name, params: params)
      .timeout(const Duration(seconds: 15));

  @override
  Future<TeamFormationList> formations(String eventId) async =>
      TeamFormationList.fromJson(
        await _rpc('list_event_team_formations', {'target_event_id': eventId}),
      );

  @override
  Future<List<SuggestedPlace>> suggest({
    required String eventId,
    String? formationId,
    required String lines,
    required String matchFormat,
    required List<String> candidates,
  }) async => suggestedPlacesFromJson(
    await _rpc('suggest_event_lineup', {
      'target_event_id': eventId,
      'formation_id': formationId,
      'new_lines': formationId == null ? lines : null,
      'new_match_format': formationId == null ? matchFormat : null,
      'candidate_ids': candidates,
      'locked': <String, Object?>{},
    }),
  );
}

/// Where the line-up finds the services, configured at start.
abstract final class LineupSuggestionFeature {
  static LineupSuggestionServices services =
      const UnconfiguredLineupSuggestionServices();

  static void configure(SupabaseClient client) =>
      services = SupabaseLineupSuggestionServices(client);
}
