part of 'team_development_models.dart';

/// What a key figure can count from the matches (step 6, decision 15), as
/// (key, Swedish, English, higher is better). Besides these, `button:<id>`
/// counts one of the team's own Live buttons.
const kpiSources = [
  ('goals_for', 'Gjorda mål', 'Goals scored', true),
  ('goals_against', 'Insläppta mål', 'Goals conceded', false),
  ('points', 'Poäng', 'Points', true),
  ('clean_sheet', 'Hållen nolla', 'Clean sheet', true),
  ('shots', 'Avslut', 'Shots', true),
  ('shots_on_target', 'Avslut på mål', 'Shots on target', true),
  ('shots_against', 'Motståndarens avslut', 'Shots against', false),
  ('corners', 'Hörnor', 'Corners', true),
  ('saves', 'Räddningar', 'Saves', true),
  ('yellow_cards', 'Gula kort', 'Yellow cards', false),
];

/// What the score gives for every played match; the rest needs the
/// match's events.
const _scoreSources = {'goals_for', 'goals_against', 'points', 'clean_sheet'};

/// A played match of the season and what it adds up to.
class PlanMatch {
  const PlanMatch({
    required this.eventId,
    required this.playedOn,
    required this.title,
    this.registered = false,
    this.metrics = const {},
    this.buttons = const {},
  });
  factory PlanMatch.fromJson(Map<String, dynamic> json) => PlanMatch(
    eventId: json['event_id'] as String,
    playedOn: _date(json['played_on']),
    title: json['title'] as String? ?? '',
    registered: json['registered'] == true,
    metrics: {
      for (final MapEntry(:key, :value)
          in (json['metrics'] as Map? ?? const {}).entries)
        if (value is num) '$key': value,
    },
    buttons: {
      for (final MapEntry(:key, :value)
          in (json['buttons'] as Map? ?? const {}).entries)
        if (value is num) '$key': value.toInt(),
    },
  );
  final String eventId, title;
  final DateTime playedOn;

  /// Whether its events were registered (in Live, or filled in afterwards).
  final bool registered;
  final Map<String, num> metrics;

  /// Taps per own button.
  final Map<String, int> buttons;

  /// What it counts for [source]; null when the match does not tell (its
  /// events were not registered).
  double? valueOf(String source) {
    if (source.startsWith('button:')) {
      return registered ? (buttons[source.substring(7)] ?? 0).toDouble() : null;
    }
    if (!registered && !_scoreSources.contains(source)) return null;
    return metrics[source]?.toDouble();
  }
}

/// One value of a key figure: from a match (counted, or set by hand for
/// it) or added by hand.
class KpiValue {
  const KpiValue({
    required this.on,
    required this.value,
    this.match,
    this.checkin,
    this.counted = false,
  });
  factory KpiValue.of(TeamCheckin checkin, {PlanMatch? match}) => KpiValue(
    on: checkin.checkedOn,
    value: checkin.value ?? 0,
    match: match,
    checkin: checkin,
  );
  final DateTime on;
  final double value;
  final PlanMatch? match;

  /// The check-in behind a value set or added by hand.
  final TeamCheckin? checkin;

  /// Counted from the match's events or score.
  final bool counted;
}
