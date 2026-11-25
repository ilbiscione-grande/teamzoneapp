/// Player attributes (decided 2026-11-21): the team's leaders tick, per
/// player, which attributes are strengths and which are areas to develop.
/// Only the team's leaders see them; they are deleted when the player
/// leaves the team. Later used to suggest players for a formation's
/// positions (docs/implementation/player-attributes.md).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// The two ways an attribute can be ticked.
enum AttributeAssessment { strength, development }

/// One attribute the team can tick: from the sport's list ([area] set) or
/// one of the team's own ([custom], keyed by its id).
class PlayerAttributeOption {
  const PlayerAttributeOption({
    required this.key,
    this.area,
    this.customLabel,
    this.aboutSv = '',
    this.aboutEn = '',
    this.positions = const [],
  });
  final String key;
  final String? area, customLabel;

  /// What the attribute means, and the positions it matters most for
  /// (position keys); empty for the team's own.
  final String aboutSv, aboutEn;
  final List<String> positions;
  bool get custom => customLabel != null;
  String about(bool swedish) => swedish ? aboutSv : aboutEn;
}

class PlayerAttributeEntry {
  const PlayerAttributeEntry({
    required this.personId,
    required this.name,
    this.strengths = const [],
    this.development = const [],
    this.foot,
  });
  factory PlayerAttributeEntry.fromJson(Map<String, dynamic> json) =>
      PlayerAttributeEntry(
        personId: json['person_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        strengths: _strings(json['strengths']),
        development: _strings(json['development']),
        foot: json['foot'] as String?,
      );
  final String personId, name;
  final List<String> strengths, development;

  /// The preferred foot: left, right, both_equal, both_left (both, better
  /// with the left) or both_right; null when not set.
  final String? foot;

  AttributeAssessment? assessmentOf(String key) => strengths.contains(key)
      ? AttributeAssessment.strength
      : development.contains(key)
      ? AttributeAssessment.development
      : null;

  /// As this entry with [key] ticked as [assessment], or unticked.
  PlayerAttributeEntry withAssessment(
    String key,
    AttributeAssessment? assessment,
  ) => PlayerAttributeEntry(
    personId: personId,
    name: name,
    strengths: [
      ...strengths.where((k) => k != key),
      if (assessment == AttributeAssessment.strength) key,
    ],
    development: [
      ...development.where((k) => k != key),
      if (assessment == AttributeAssessment.development) key,
    ],
    foot: foot,
  );

  /// As this entry with [foot] as the preferred foot.
  PlayerAttributeEntry withFoot(String? foot) => PlayerAttributeEntry(
    personId: personId,
    name: name,
    strengths: strengths,
    development: development,
    foot: foot,
  );
}

/// The preferred foot in words: "Vänster", "Båda, bättre med höger" …
String? footLabel(String? foot, bool swedish) => switch (foot) {
  'left' => swedish ? 'Vänster' : 'Left',
  'right' => swedish ? 'Höger' : 'Right',
  'both_equal' => swedish ? 'Båda, lika bra' : 'Both, equally good',
  'both_left' =>
    swedish ? 'Båda, bättre med vänster' : 'Both, better with the left',
  'both_right' =>
    swedish ? 'Båda, bättre med höger' : 'Both, better with the right',
  _ => null,
};

/// The squad's attributes: the lists and each active player's ticks.
class TeamPlayerAttributes {
  const TeamPlayerAttributes({
    this.sport = 'football',
    this.options = const [],
    this.players = const [],
  });
  factory TeamPlayerAttributes.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    List<Map<String, dynamic>> rows(Object? value) => [
      for (final row in (value as List? ?? const []).whereType<Map>())
        Map<String, dynamic>.from(row),
    ];
    return TeamPlayerAttributes(
      sport: map['sport'] as String? ?? 'football',
      options: [
        for (final row in rows(map['catalog']))
          PlayerAttributeOption(
            key: row['key'] as String? ?? '',
            area: row['area'] as String? ?? 'technical',
            aboutSv: row['about_sv'] as String? ?? '',
            aboutEn: row['about_en'] as String? ?? '',
            positions: _strings(row['positions']),
          ),
        for (final row in rows(map['custom']))
          PlayerAttributeOption(
            key: row['id'] as String? ?? '',
            customLabel: row['label'] as String? ?? '',
          ),
      ],
      players: [
        for (final row in rows(map['players']))
          PlayerAttributeEntry.fromJson(row),
      ],
    );
  }
  final String sport;
  final List<PlayerAttributeOption> options;
  final List<PlayerAttributeEntry> players;

  PlayerAttributeOption? option(String key) =>
      options.where((o) => o.key == key).firstOrNull;
  PlayerAttributeEntry? player(String personId) =>
      players.where((p) => p.personId == personId).firstOrNull;
  List<PlayerAttributeOption> get customOptions =>
      options.where((o) => o.custom).toList();
}

List<String> _strings(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is String) item,
];

abstract interface class PlayerAttributesServices {
  Future<TeamPlayerAttributes> get({
    required String clubId,
    required String teamId,
  });

  /// Replaces what is ticked for one player.
  Future<TeamPlayerAttributes> set({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> strengths,
    required List<String> development,
  });

  /// Adds one of the team's own attributes (no [attributeId]) or renames it.
  Future<TeamPlayerAttributes> saveCustom({
    required String clubId,
    required String teamId,
    String? attributeId,
    required String label,
  });

  /// Removes one of the team's own attributes and every tick on it.
  Future<TeamPlayerAttributes> deleteCustom({
    required String clubId,
    required String teamId,
    required String attributeId,
  });

  /// Sets the player's preferred foot; null takes it away.
  Future<TeamPlayerAttributes> setFoot({
    required String clubId,
    required String teamId,
    required String personId,
    required String? foot,
  });
}

class UnconfiguredPlayerAttributesServices implements PlayerAttributesServices {
  const UnconfiguredPlayerAttributesServices();
  Never _missing() => throw StateError('Player attributes not configured');
  @override
  Future<TeamPlayerAttributes> get({
    required String clubId,
    required String teamId,
  }) async => _missing();
  @override
  Future<TeamPlayerAttributes> set({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> strengths,
    required List<String> development,
  }) async => _missing();
  @override
  Future<TeamPlayerAttributes> saveCustom({
    required String clubId,
    required String teamId,
    String? attributeId,
    required String label,
  }) async => _missing();
  @override
  Future<TeamPlayerAttributes> deleteCustom({
    required String clubId,
    required String teamId,
    required String attributeId,
  }) async => _missing();
  @override
  Future<TeamPlayerAttributes> setFoot({
    required String clubId,
    required String teamId,
    required String personId,
    required String? foot,
  }) async => _missing();
}

class SupabasePlayerAttributesServices implements PlayerAttributesServices {
  SupabasePlayerAttributesServices(this._client);
  final SupabaseClient _client;

  Future<TeamPlayerAttributes> _rpc(
    String name,
    Map<String, Object?> params,
  ) async => TeamPlayerAttributes.fromJson(
    await _client
        .schema('api')
        .rpc<Object?>(name, params: params)
        .timeout(const Duration(seconds: 15)),
  );

  @override
  Future<TeamPlayerAttributes> get({
    required String clubId,
    required String teamId,
  }) => _rpc('get_team_player_attributes', {
    'target_club_id': clubId,
    'target_team_id': teamId,
  });

  @override
  Future<TeamPlayerAttributes> set({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> strengths,
    required List<String> development,
  }) => _rpc('set_player_attributes', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'target_person_id': personId,
    'new_strengths': strengths,
    'new_development': development,
  });

  @override
  Future<TeamPlayerAttributes> saveCustom({
    required String clubId,
    required String teamId,
    String? attributeId,
    required String label,
  }) => _rpc('save_team_attribute', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'attribute_id': attributeId,
    'new_label': label,
  });

  @override
  Future<TeamPlayerAttributes> deleteCustom({
    required String clubId,
    required String teamId,
    required String attributeId,
  }) => _rpc('delete_team_attribute', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'attribute_id': attributeId,
  });

  @override
  Future<TeamPlayerAttributes> setFoot({
    required String clubId,
    required String teamId,
    required String personId,
    required String? foot,
  }) => _rpc('set_player_foot', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'target_person_id': personId,
    'new_foot': foot,
  });
}

/// Where the player profile finds the services, configured at start.
abstract final class PlayerAttributesFeature {
  static PlayerAttributesServices services =
      const UnconfiguredPlayerAttributesServices();

  static void configure(SupabaseClient client) =>
      services = SupabasePlayerAttributesServices(client);
}

/// Swedish and English names of the sports' attributes and areas.
const playerAttributeLabels = <String, (String, String)>{
  'acceleration': ('Acceleration', 'Acceleration'),
  'speed': ('Snabbhet', 'Speed'),
  'strength': ('Fysisk styrka', 'Physical strength'),
  'endurance': ('Uthållighet', 'Endurance'),
  'agility': ('Rörlighet', 'Agility'),
  'jumping': ('Spänst', 'Jumping'),
  'heading': ('Huvudspel', 'Heading'),
  'shooting': ('Skott', 'Shooting'),
  'long_shots': ('Distansskott', 'Long shots'),
  'crossing': ('Inlägg', 'Crossing'),
  'passing': ('Passningar', 'Passing'),
  'long_passing': ('Långa passningar', 'Long passing'),
  'first_touch': ('Mottagning', 'First touch'),
  'dribbling': ('Dribbling', 'Dribbling'),
  'ball_carrying': ('Driva boll framåt', 'Carrying the ball forward'),
  'feints': ('Finter', 'Feints'),
  'weak_foot': ('Svagare foten', 'Weaker foot'),
  'tackling': ('Tacklingar', 'Tackling'),
  'back_to_goal': ('Spela felvänd', 'Playing with the back to goal'),
  'finishing': ('Avslut', 'Finishing'),
  'set_pieces': ('Fasta situationer', 'Set pieces'),
  'goalkeeping': ('Målvaktsspel', 'Goalkeeping'),
  'goalkeeping_hands': ('Målvakt – räddningar', 'Goalkeeper – saves'),
  'goalkeeping_feet': (
    'Målvakt – kort passningsspel',
    'Goalkeeper – short passing',
  ),
  'defending_1v1': ('1 mot 1 i försvar', '1v1 defending'),
  'interceptions': ('Brytningar', 'Interceptions'),
  'marking': ('Markering', 'Marking'),
  'blocking': ('Blockeringar', 'Blocking'),
  'attacking_1v1': ('1 mot 1 i anfall', '1v1 attacking'),
  'positioning': ('Positionsspel', 'Positioning'),
  'game_reading': ('Spelförståelse', 'Reading the game'),
  'pressing': ('Press', 'Pressing'),
  'duels': ('Närkamper', 'Duels'),
  'runs_in_behind': ('Djupledslöpningar', 'Runs in behind'),
  'recovery_runs': ('Hemlöpningar', 'Recovery runs'),
  'fast_breaks': ('Kontringar', 'Fast breaks'),
  'leadership': ('Ledarskap', 'Leadership'),
  'communication': ('Kommunikation', 'Communication'),
  'work_rate': ('Arbetsvilja', 'Work rate'),
  'composure': ('Lugn under press', 'Composure'),
  'goalkeeping_reflexes': ('Målvakt – reflexer', 'Goalkeeper – reflexes'),
  'goalkeeping_aerial': ('Målvakt – luftrum', 'Goalkeeper – aerial play'),
  'goalkeeping_1v1': ('Målvakt – 1 mot 1', 'Goalkeeper – one against one'),
  'goalkeeping_sweeping': ('Målvakt – utrusningar', 'Goalkeeper – sweeping'),
  'goalkeeping_kicking': ('Målvakt – utsparkar', 'Goalkeeper – kicking'),
  'goalkeeping_throwing': ('Målvakt – utkast', 'Goalkeeper – throwing'),
  'long_throws': ('Långa inkast', 'Long throw-ins'),
  'balance': ('Balans', 'Balance'),
  'scanning': ('Scanning', 'Scanning'),
  'creativity': ('Kreativitet', 'Creativity'),
  'off_the_ball': ('Spelbarhet', 'Getting free'),
  'concentration': ('Koncentration', 'Concentration'),
  'determination': ('Vinnarskalle', 'Will to win'),
  'bravery': ('Mod', 'Courage'),
  'coachability': ('Coachbarhet', 'Coachability'),
};

const playerAttributeAreas = <String, (String, String)>{
  'physical': ('Fysik', 'Physical'),
  'technical': ('Teknik', 'Technical'),
  'tactical': ('Spelförståelse', 'Tactical'),
  'mental': ('Mentalt', 'Mental'),
};

/// The attribute's name; a key without a name shows as itself.
String playerAttributeLabel(PlayerAttributeOption option, bool swedish) {
  if (option.customLabel != null) return option.customLabel!;
  final label = playerAttributeLabels[option.key];
  return label == null ? option.key : (swedish ? label.$1 : label.$2);
}
