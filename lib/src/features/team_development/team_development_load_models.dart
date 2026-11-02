part of 'team_development_models.dart';

/// A signal the team's values raise on a player's facts (step 8,
/// PAR-METHOD-01): a rule, never a medical conclusion.
enum LoadSignal {
  loadIncrease('load_increase'),
  lowAttendance('low_attendance'),
  matchMinutes('match_minutes');

  const LoadSignal(this.key);
  final String key;

  static LoadSignal? from(Object? key) =>
      values.where((signal) => signal.key == key).firstOrNull;
}

/// The team's values for the signals; null turns a signal off.
class LoadSettings {
  const LoadSettings({
    this.loadIncreasePercent = 130,
    this.attendanceMinPercent = 50,
    this.matchMinutesMax = 180,
  });
  factory LoadSettings.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return LoadSettings(
      loadIncreasePercent: (map['load_increase_percent'] as num?)?.toInt(),
      attendanceMinPercent: (map['attendance_min_percent'] as num?)?.toInt(),
      matchMinutesMax: (map['match_minutes_max'] as num?)?.toInt(),
    );
  }

  /// The last 7 days' minutes as a share of the 4 weeks' weekly average.
  final int? loadIncreasePercent;

  /// The share of the team's trainings (with attendance taken) in 4 weeks.
  final int? attendanceMinPercent;

  /// Match minutes in the last 7 days.
  final int? matchMinutesMax;
}

/// One player's load: the last 7 days and the last 4 weeks.
class PlayerLoad {
  const PlayerLoad({
    required this.personId,
    required this.name,
    this.sessions7 = 0,
    this.sessions28 = 0,
    this.trainingMinutes7 = 0,
    this.trainingMinutes28 = 0,
    this.matchMinutes7 = 0,
    this.matchMinutes28 = 0,
    this.trainings28 = 0,
    this.attendancePercent,
    this.loadPercent,
    this.effort7,
    this.efforts7 = 0,
    this.signals = const [],
  });
  factory PlayerLoad.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return PlayerLoad(
      personId: json['person_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sessions7: count('sessions_7'),
      sessions28: count('sessions_28'),
      trainingMinutes7: count('training_minutes_7'),
      trainingMinutes28: count('training_minutes_28'),
      matchMinutes7: count('match_minutes_7'),
      matchMinutes28: count('match_minutes_28'),
      trainings28: count('trainings_28'),
      attendancePercent: (json['attendance_percent'] as num?)?.toInt(),
      loadPercent: (json['load_percent'] as num?)?.toInt(),
      effort7: (json['effort_7'] as num?)?.toDouble(),
      efforts7: count('efforts_7'),
      signals: [
        for (final key in json['signals'] as List? ?? const [])
          ?LoadSignal.from(key),
      ],
    );
  }
  final String personId, name;

  /// Trainings attended.
  final int sessions7, sessions28;
  final int trainingMinutes7, trainingMinutes28;
  final int matchMinutes7, matchMinutes28;

  /// The team's trainings with attendance taken in the 4 weeks.
  final int trainings28;

  /// Of [trainings28], the share attended; null without any.
  final int? attendancePercent;

  /// The last 7 days' minutes as a share of the 4 weeks' weekly average;
  /// null without any minutes.
  final int? loadPercent;

  /// The player's rated effort (1–10, PAR-PRIV-04) over the last 7 days:
  /// the average, null without answers, and how many answers.
  final double? effort7;
  final int efforts7;
  final List<LoadSignal> signals;

  int get minutes7 => trainingMinutes7 + matchMinutes7;
}

/// The team's load up to [day], with the values the signals use.
class TeamLoad {
  const TeamLoad({
    required this.day,
    this.settings = const LoadSettings(),
    this.players = const [],
  });
  factory TeamLoad.fromJson(Map<String, dynamic> json) => TeamLoad(
    day: _date(json['day']),
    settings: LoadSettings.fromJson(json['settings']),
    players: [
      for (final row in (json['players'] as List? ?? const []).whereType<Map>())
        PlayerLoad.fromJson(Map<String, dynamic>.from(row)),
    ],
  );
  final DateTime day;
  final LoadSettings settings;
  final List<PlayerLoad> players;

  /// The players with a signal, the most signals first.
  List<PlayerLoad> get flagged =>
      [
        for (final player in players)
          if (player.signals.isNotEmpty) player,
      ]..sort((a, b) {
        final bySignals = b.signals.length.compareTo(a.signals.length);
        return bySignals != 0 ? bySignals : a.name.compareTo(b.name);
      });
}
