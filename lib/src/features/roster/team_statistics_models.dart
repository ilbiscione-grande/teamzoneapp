// Laget → Statistik (api.get_team_statistics). Rates are percentages with
// one decimal, null when nothing counted. Attended = present, late or
// partial; an absence only counts when the person was expected.

double? _rate(Object? value) => value is num ? value.toDouble() : null;
int _int(Object? value) => value is num ? value.toInt() : 0;

/// The periods offered in the view.
enum TeamStatisticsPeriod {
  last30Days,
  last90Days,
  thisYear;

  ({DateTime from, DateTime to}) range(DateTime now) => switch (this) {
    last30Days => (from: now.subtract(const Duration(days: 30)), to: now),
    last90Days => (from: now.subtract(const Duration(days: 90)), to: now),
    thisYear => (from: DateTime(now.year), to: now),
  };
}

class TeamStatisticsMonth {
  const TeamStatisticsMonth({
    required this.month,
    this.attendanceRate,
    this.trainingRate,
    this.matchRate,
  });

  /// YYYY-MM in the club's time zone.
  final String month;
  final double? attendanceRate, trainingRate, matchRate;
}

class TeamStatisticsPerson {
  const TeamStatisticsPerson({
    required this.personId,
    required this.name,
    required this.role,
    required this.attended,
    required this.counted,
    required this.trainingsAttended,
    required this.trainingsCounted,
    required this.matchesAttended,
    required this.matchesCounted,
    required this.late,
    required this.callups,
    required this.answered,
  });
  final String personId, name, role;
  final int attended, counted;
  final int trainingsAttended, trainingsCounted;
  final int matchesAttended, matchesCounted;
  final int late, callups, answered;

  bool get isPlayer => role == 'player';

  /// Null until at least one event counted.
  double? get rate => counted == 0 ? null : 100 * attended / counted;

  factory TeamStatisticsPerson.fromJson(Map<String, dynamic> json) =>
      TeamStatisticsPerson(
        personId: json['person_id'] as String,
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? 'player',
        attended: _int(json['attended']),
        counted: _int(json['counted']),
        trainingsAttended: _int(json['trainings_attended']),
        trainingsCounted: _int(json['trainings_counted']),
        matchesAttended: _int(json['matches_attended']),
        matchesCounted: _int(json['matches_counted']),
        late: _int(json['late']),
        callups: _int(json['callups']),
        answered: _int(json['answered']),
      );
}

class TeamStatistics {
  const TeamStatistics({
    required this.events,
    required this.trainings,
    required this.matches,
    required this.otherEvents,
    required this.late,
    required this.months,
    required this.people,
    this.attendanceRate,
    this.trainingRate,
    this.matchRate,
    this.responseRate,
  });
  final int events, trainings, matches, otherEvents, late;
  final double? attendanceRate, trainingRate, matchRate, responseRate;
  final List<TeamStatisticsMonth> months;
  final List<TeamStatisticsPerson> people;

  List<TeamStatisticsPerson> get players =>
      people.where((person) => person.isPlayer).toList(growable: false);
  List<TeamStatisticsPerson> get leaders =>
      people.where((person) => !person.isPlayer).toList(growable: false);

  /// Players with the lowest attendance, among those with at least
  /// [minimumCounted] counted events (so one missed training is not a trend).
  List<TeamStatisticsPerson> lowestAttendance({
    int minimumCounted = 3,
    int limit = 5,
  }) {
    final candidates =
        players.where((person) => person.counted >= minimumCounted).toList()
          ..sort((a, b) {
            final byRate = a.rate!.compareTo(b.rate!);
            return byRate != 0 ? byRate : a.name.compareTo(b.name);
          });
    return candidates.take(limit).toList(growable: false);
  }

  factory TeamStatistics.fromJson(Map<String, dynamic> json) {
    final events = Map<String, dynamic>.from(json['events'] as Map? ?? {});
    return TeamStatistics(
      events: _int(events['total']),
      trainings: _int(events['training']),
      matches: _int(events['match']),
      otherEvents: _int(events['other']),
      attendanceRate: _rate(json['attendance_rate']),
      trainingRate: _rate(json['training_rate']),
      matchRate: _rate(json['match_rate']),
      responseRate: _rate(json['response_rate']),
      late: _int(json['late']),
      months: [
        for (final row in json['months'] as List? ?? const [])
          if (row is Map)
            TeamStatisticsMonth(
              month: row['month'] as String,
              attendanceRate: _rate(row['attendance_rate']),
              trainingRate: _rate(row['training_rate']),
              matchRate: _rate(row['match_rate']),
            ),
      ],
      people: [
        for (final row in json['people'] as List? ?? const [])
          if (row is Map)
            TeamStatisticsPerson.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }
}
