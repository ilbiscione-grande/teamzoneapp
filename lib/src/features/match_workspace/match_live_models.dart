/// Live in the Match module: the kinds of match events, as the old app's
/// match workspace had them, and what follows from the facts (who is on the
/// pitch, which planned substitutions are done). Facts are Match Space v2's
/// core.match_facts as the snapshot sends them.
library;

/// A kind of event the live view registers, with its result choices.
class LiveEventKind {
  const LiveEventKind({
    required this.type,
    required this.label,
    this.results = const [],
    this.defaultResult,
    this.needsPlayer = true,
    this.secondaryLabel,
    this.locatable = false,
  });
  final String type, label;

  /// The result choices (value, label) kept in detail.result; for a card
  /// its colour in detail.color.
  final List<(String, String)> results;
  final String? defaultResult;
  final bool needsPlayer;

  /// The second player's role, when the kind has one (the one coming on,
  /// the one fouled, who took it).
  final String? secondaryLabel;

  /// Marked where on the pitch it happened (detail.location).
  final bool locatable;

  String get resultKey => type == 'card' ? 'color' : 'result';
}

const liveEventKinds = <LiveEventKind>[
  LiveEventKind(type: 'substitution', label: 'Byte', secondaryLabel: 'In'),
  LiveEventKind(
    type: 'shot',
    label: 'Avslut',
    results: [
      ('on_target', 'På mål'),
      ('missed', 'Utanför'),
      ('blocked', 'Blockerat'),
      ('woodwork', 'Ribba/stolpe'),
    ],
    defaultResult: 'missed',
    locatable: true,
  ),
  LiveEventKind(
    type: 'card',
    label: 'Foul',
    results: [('none', 'Inget kort'), ('yellow', 'Gult'), ('red', 'Rött')],
    defaultResult: 'none',
    secondaryLabel: 'Fällde',
    locatable: true,
  ),
  LiveEventKind(
    type: 'corner',
    label: 'Hörna',
    results: [
      ('delivery', 'Inlägg'),
      ('shot', 'Avslut'),
      ('cleared', 'Rensad'),
      ('short', 'Kort'),
    ],
    defaultResult: 'delivery',
    needsPlayer: false,
  ),
  LiveEventKind(
    type: 'free_kick',
    label: 'Frispark',
    results: [('delivery', 'Inlägg'), ('shot', 'Avslut'), ('short', 'Kort')],
    defaultResult: 'delivery',
    needsPlayer: false,
    locatable: true,
  ),
  LiveEventKind(
    type: 'penalty',
    label: 'Straff',
    results: [('scored', 'Mål'), ('saved', 'Räddad'), ('missed', 'Miss')],
    defaultResult: 'scored',
    needsPlayer: false,
  ),
  LiveEventKind(type: 'save', label: 'Räddning', needsPlayer: false),
  LiveEventKind(type: 'injury', label: 'Skada', locatable: true),
];

LiveEventKind? liveEventKind(String? type) =>
    liveEventKinds.where((kind) => kind.type == type).firstOrNull;

/// The facts still standing (not voided), by minute as the snapshot sends.
Iterable<Map<String, dynamic>> activeFacts(List<Map<String, dynamic>> facts) =>
    facts.where((fact) => fact['state'] != 'voided');

/// Who is on the pitch now: the starters, then each substitution in order
/// (player_id off, secondary player on).
List<String> onPitch(List<String> starters, List<Map<String, dynamic>> facts) {
  final pitch = [...starters];
  final subs =
      activeFacts(facts)
          .where(
            (fact) =>
                fact['fact_type'] == 'substitution' &&
                fact['side'] != 'opponent',
          )
          .toList()
        ..sort(
          (a, b) => ((a['minute'] as num?) ?? 0).compareTo(
            (b['minute'] as num?) ?? 0,
          ),
        );
  for (final sub in subs) {
    final off = sub['club_person_id'] as String?;
    final on = sub['secondary_club_person_id'] as String?;
    final at = off == null ? -1 : pitch.indexOf(off);
    if (on != null && pitch.contains(on)) continue;
    if (at >= 0) {
      if (on == null) {
        pitch.removeAt(at);
      } else {
        pitch[at] = on;
      }
    } else if (on != null) {
      pitch.add(on);
    }
  }
  return pitch;
}

/// The planned substitutions already made: a substitution fact carries the
/// plan's id in detail.plan_id.
Set<String> donePlannedSubstitutions(List<Map<String, dynamic>> facts) => {
  for (final fact in activeFacts(facts))
    if (fact['fact_type'] == 'substitution')
      if ((fact['detail'] as Map?)?['plan_id'] case final String id) id,
};

/// Counts per kind and side, for the small tally beside each button.
Map<String, int> eventTally(List<Map<String, dynamic>> facts, String side) {
  final tally = <String, int>{};
  for (final fact in activeFacts(facts)) {
    if ((fact['side'] ?? 'us') != side) continue;
    final type = fact['fact_type'] as String? ?? '';
    tally[type] = (tally[type] ?? 0) + 1;
  }
  return tally;
}

/// Where on the pitch a fact happened, seen from our attack (x from our
/// goal line to theirs, y from the left touchline), or null.
(double, double)? factLocation(Map<String, dynamic> fact) {
  final location = (fact['detail'] as Map?)?['location'];
  if (location is! Map) return null;
  final x = (location['x'] as num?)?.toDouble();
  final y = (location['y'] as num?)?.toDouble();
  if (x == null || y == null) return null;
  return (x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
}

/// The location as stored, to three decimals.
Map<String, double> locationDetail(double x, double y) => {
  'x': (x.clamp(0.0, 1.0) * 1000).roundToDouble() / 1000,
  'y': (y.clamp(0.0, 1.0) * 1000).roundToDouble() / 1000,
};

/// A shot on the shot map: where, whose, and how it ended.
typedef ShotPoint = ({double x, double y, String side, String outcome});

/// Every located shot and goal, for the shot map: outcome is goal,
/// on_target, missed, blocked or woodwork.
List<ShotPoint> shotPoints(List<Map<String, dynamic>> facts) => [
  for (final fact in activeFacts(facts))
    if (const ['shot', 'goal'].contains(fact['fact_type']))
      if (factLocation(fact) case (final x, final y))
        (
          x: x,
          y: y,
          side: fact['side'] as String? ?? 'us',
          outcome: fact['fact_type'] == 'goal'
              ? 'goal'
              : (fact['detail'] as Map?)?['result'] as String? ?? 'missed',
        ),
];
