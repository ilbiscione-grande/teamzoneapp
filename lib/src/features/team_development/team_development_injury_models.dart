part of 'team_development_models.dart';

/// An injury (step 9, PAR-METHOD-02): what, from when, and the day the
/// player was back in training. The leaders' [note] never reaches the
/// player or their guardians.
class PlayerInjury {
  const PlayerInjury({
    required this.id,
    required this.startedOn,
    required this.what,
    this.note,
    this.backOn,
  });
  factory PlayerInjury.fromJson(Map<String, dynamic> json) => PlayerInjury(
    id: json['id'] as String? ?? '',
    startedOn: _date(json['started_on']),
    what: json['what'] as String? ?? '',
    note: json['note'] as String?,
    backOn: json['back_on'] == null ? null : _date(json['back_on']),
  );
  final String id, what;
  final String? note;
  final DateTime startedOn;
  final DateTime? backOn;

  /// Not yet back in training on [day].
  bool currentOn(DateTime day) => backOn == null || backOn!.isAfter(day);
}

/// A player's injury registration and injuries: on from 15, under 15 with
/// the club's, the player's and a guardian's consent, unless the leaders or
/// the club turned it off.
class InjuryPlayer {
  const InjuryPlayer({
    required this.personId,
    required this.name,
    this.self = false,
    this.adult = false,
    this.turnedOff = false,
    this.clubConsent = false,
    this.playerConsent = false,
    this.guardianConsent = false,
    this.allowed = false,
    this.injuries = const [],
  });
  factory InjuryPlayer.fromJson(Map<String, dynamic> json) {
    final consents = json['consents'] is Map ? json['consents'] as Map : {};
    return InjuryPlayer(
      personId: json['person_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      self: json['self'] == true,
      adult: json['adult'] == true,
      turnedOff: json['turned_off'] == true,
      clubConsent: consents['club'] == true,
      playerConsent: consents['player'] == true,
      guardianConsent: consents['guardian'] == true,
      allowed: json['allowed'] == true,
      injuries: [
        for (final row
            in (json['injuries'] as List? ?? const []).whereType<Map>())
          PlayerInjury.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }
  final String personId, name;

  /// The actor themselves (for a player's own view), else a child.
  final bool self;

  /// 15 or older.
  final bool adult;
  final bool turnedOff, clubConsent, playerConsent, guardianConsent, allowed;
  final List<PlayerInjury> injuries;

  /// The injury not yet back from on [day], if any.
  PlayerInjury? currentOn(DateTime day) =>
      injuries.where((injury) => injury.currentOn(day)).firstOrNull;
}

/// The players with their injury registration, for the leaders or for a
/// player and their guardians.
class TeamInjuries {
  const TeamInjuries({this.players = const []});
  factory TeamInjuries.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return TeamInjuries(
      players: [
        for (final row
            in ((map['players'] ?? map['people']) as List? ?? const [])
                .whereType<Map>())
          InjuryPlayer.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }
  final List<InjuryPlayer> players;

  InjuryPlayer? of(String personId) =>
      players.where((player) => player.personId == personId).firstOrNull;
}
