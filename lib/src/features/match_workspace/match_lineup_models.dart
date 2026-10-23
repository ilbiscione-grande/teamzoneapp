/// A starter in the line-up: the formation slot and the place on the pitch
/// (x from the own goal line to the opponent's, y from the left touchline
/// to the right, both 0..1); a starter saved under Förberedelser has none.
class LineupStarter {
  const LineupStarter({
    required this.personId,
    required this.name,
    this.number,
    this.slot,
    this.position,
    this.x,
    this.y,
  });
  factory LineupStarter.fromJson(Map<String, dynamic> json) => LineupStarter(
    personId: json['person_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    number: (json['number'] as num?)?.toInt(),
    slot: json['slot'] as String?,
    position: json['position'] as String?,
    x: (json['x'] as num?)?.toDouble(),
    y: (json['y'] as num?)?.toDouble(),
  );
  final String personId, name;
  final int? number;
  final String? slot, position;
  final double? x, y;
}

/// A player of the team to choose from, with number and positions.
class LineupPlayer {
  const LineupPlayer({
    required this.personId,
    required this.name,
    this.number,
    this.mainPosition,
    this.positions = const [],
  });
  factory LineupPlayer.fromJson(Map<String, dynamic> json) => LineupPlayer(
    personId: json['person_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    number: (json['number'] as num?)?.toInt(),
    mainPosition: json['main_position'] as String?,
    positions: (json['positions'] as List? ?? const [])
        .whereType<String>()
        .toList(),
  );
  final String personId, name;
  final int? number;
  final String? mainPosition;
  final List<String> positions;
}

/// A planned substitution: who goes off, who comes on, when, and why.
class PlannedSubstitution {
  const PlannedSubstitution({
    required this.id,
    required this.outId,
    required this.inId,
    this.minute,
    this.note = '',
    this.outName = '',
    this.inName = '',
  });
  factory PlannedSubstitution.fromJson(Map<String, dynamic> json) =>
      PlannedSubstitution(
        id: json['id'] as String? ?? '',
        outId: json['out_id'] as String? ?? '',
        inId: json['in_id'] as String? ?? '',
        minute: (json['minute'] as num?)?.toInt(),
        note: json['note'] as String? ?? '',
        outName: json['out_name'] as String? ?? '',
        inName: json['in_name'] as String? ?? '',
      );
  final String id, outId, inId, note, outName, inName;
  final int? minute;

  Map<String, Object?> toJson() => {
    'id': id,
    'out_id': outId,
    'in_id': inId,
    'minute': minute,
    'note': note,
  };
}

/// The event's line-up as the Match module reads it: the same line-up as
/// under Förberedelser, with places, the substitution plan, the team's
/// match format and, for those who edit it, the team's players.
class MatchLineup {
  const MatchLineup({
    required this.canEdit,
    required this.published,
    required this.revision,
    this.formation,
    this.matchFormat,
    this.starters = const [],
    this.substitutes = const [],
    this.plan = const [],
    this.players = const [],
  });
  factory MatchLineup.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) => [
      for (final row in (json[key] as List? ?? const []).whereType<Map>())
        Map<String, dynamic>.from(row),
    ];
    return MatchLineup(
      canEdit: json['can_edit'] == true,
      published: json['published'] == true,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      formation: json['formation'] as String?,
      matchFormat: json['match_format'] as String?,
      starters: rows('starters').map(LineupStarter.fromJson).toList(),
      substitutes: rows('substitutes').map(LineupPlayer.fromJson).toList(),
      plan: rows(
        'substitution_plan',
      ).map(PlannedSubstitution.fromJson).toList(),
      players: rows('players').map(LineupPlayer.fromJson).toList(),
    );
  }
  final bool canEdit, published;
  final int revision;
  final String? formation, matchFormat;
  final List<LineupStarter> starters;
  final List<LineupPlayer> substitutes, players;
  final List<PlannedSubstitution> plan;

  bool get isEmpty => starters.isEmpty && substitutes.isEmpty;
}
