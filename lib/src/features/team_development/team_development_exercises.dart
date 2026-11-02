part of 'team_development_models.dart';

/// An exercise (or a whole pass) for a block (step 7, decision 18), kept in
/// the form a session takes it in: Tacticsboard's library item as a pass,
/// with its exercises.
class BlockExercise {
  const BlockExercise({required this.pass, this.id});
  factory BlockExercise.fromJson(Map<String, dynamic> json, {String? id}) =>
      BlockExercise(pass: json, id: id);

  /// The row when the leaders chose it for the block; null when the
  /// library suggests it.
  final String? id;

  /// As the library lists it: source, id, kind, title, theme, exercises.
  final Map<String, dynamic> pass;

  String get title => pass['title'] as String? ?? '';

  /// own, club or teamzone.
  String get source => pass['source'] as String? ?? '';

  /// The library item's id (a shared item) or the leaders' own row.
  String get itemId => pass['id'] as String? ?? '';

  /// A single exercise rather than a pass.
  bool get single => pass['kind'] == 'exercise';

  List<Map<String, dynamic>> get exercises => [
    for (final row in (pass['exercises'] as List? ?? const []).whereType<Map>())
      Map<String, dynamic>.from(row),
  ];

  int get minutes => exercises.fold(
    0,
    (sum, exercise) => sum + ((exercise['minutes'] as num?)?.toInt() ?? 0),
  );

  /// The phase of the game it trains, when it says.
  PrincipleArea? get phase => switch (exercises.firstOrNull?['phase']) {
    final String key => PrincipleArea.from(key),
    _ => null,
  };

  /// What it says about itself: the pass's theme, or the exercise's
  /// organisation.
  String get detail {
    final theme = (pass['theme'] as String? ?? '').trim();
    if (theme.isNotEmpty) return theme;
    return (exercises.firstOrNull?['organisation'] as String? ?? '').trim();
  }
}

/// A block's exercises: those the leaders chose, then the library's that
/// train its principles.
class BlockExercises {
  const BlockExercises({this.chosen = const [], this.matched = const []});
  factory BlockExercises.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return BlockExercises(
      chosen: [
        for (final row in (map['chosen'] as List? ?? const []).whereType<Map>())
          if (row['pass'] is Map)
            BlockExercise.fromJson(
              Map<String, dynamic>.from(row['pass'] as Map),
              id: row['id'] as String?,
            ),
      ],
      matched: [
        for (final row
            in (map['matched'] as List? ?? const []).whereType<Map>())
          BlockExercise.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }
  final List<BlockExercise> chosen, matched;

  bool get isEmpty => chosen.isEmpty && matched.isEmpty;
  List<BlockExercise> get all => [...chosen, ...matched];
}
