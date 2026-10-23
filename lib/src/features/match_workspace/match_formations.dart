/// Formations for the team's match format, as the old app's match module
/// had for 11v11, here for every format. A formation such as 2-3-1 is its
/// outfield lines from the own goal; 3v3 plays without a goalkeeper.
library;

/// One place in a formation: a code stored with the player, a short label
/// and where it sits (x from the own goal line to the opponent's, y from
/// the left touchline to the right).
class FormationSlot {
  const FormationSlot({
    required this.code,
    required this.label,
    required this.group,
    required this.x,
    required this.y,
  });
  final String code, label;

  /// goalkeeper, defender, midfielder or forward: the general position the
  /// slot asks for.
  final String group;
  final double x, y;
}

/// The formations offered per match format, the first the default.
const formationsByFormat = <String, List<String>>{
  '3v3': ['1-1-1', '2-1', '1-2'],
  '5v5': ['2-2', '1-2-1', '2-1-1'],
  '7v7': ['2-3-1', '3-2-1', '2-1-2-1', '3-1-2'],
  '9v9': ['3-3-2', '3-2-3', '3-4-1', '2-3-2-1'],
  '11v11': ['4-3-3', '4-4-2', '4-2-3-1', '3-5-2', '5-3-2'],
};

List<String> formationsFor(String? format) =>
    formationsByFormat[format] ?? formationsByFormat['11v11']!;

/// Players on the pitch per format, the goalkeeper included.
int playersOnPitch(String? format) => switch (format) {
  '3v3' => 3,
  '5v5' => 5,
  '7v7' => 7,
  '9v9' => 9,
  _ => 11,
};

bool _hasKeeper(String? format) => format != '3v3';

/// The slots of [formation] for [format]: the goalkeeper, then each line
/// from the own goal, left to right. An unknown formation gives none.
List<FormationSlot> formationSlots(String formation, String? format) {
  final lines = formation.split('-').map(int.tryParse).toList();
  if (lines.isEmpty || lines.any((count) => count == null || count < 1)) {
    return const [];
  }
  final counts = lines.cast<int>();
  final keeper = _hasKeeper(format);
  final slots = <FormationSlot>[
    if (keeper)
      const FormationSlot(
        code: 'GK',
        label: 'MV',
        group: 'goalkeeper',
        x: 0.06,
        y: 0.5,
      ),
  ];
  final first = keeper ? 0.24 : 0.18, last = 0.84;
  for (var line = 0; line < counts.length; line++) {
    final count = counts[line];
    final x = counts.length == 1
        ? 0.5
        : first + (last - first) * line / (counts.length - 1);
    for (var i = 0; i < count; i++) {
      // Wide lines reach further out than narrow ones.
      final spread = count == 1 ? 0.0 : (count >= 4 ? 0.76 : 0.6);
      final y = count == 1 ? 0.5 : 0.5 - spread / 2 + spread * i / (count - 1);
      slots.add(
        FormationSlot(
          code: '${line + 1}${String.fromCharCode(65 + i)}',
          label: _label(line, counts.length, count, i),
          group: _group(line, counts.length),
          x: x,
          y: y,
        ),
      );
    }
  }
  return slots;
}

String _group(int line, int lines) => line == 0 && lines > 1
    ? 'defender'
    : line == lines - 1
    ? 'forward'
    : 'midfielder';

String _label(int line, int lines, int count, int i) {
  final edge = count >= 3 && (i == 0 || i == count - 1);
  final left = i == 0;
  if (line == 0 && lines > 1) {
    return edge ? (left ? 'VB' : 'HB') : 'MB';
  }
  if (line == lines - 1) {
    return count == 3 && edge ? (left ? 'VY' : 'HY') : 'ANF';
  }
  if (lines == 4) {
    return line == 1 ? 'DM' : (edge ? (left ? 'VY' : 'HY') : 'OM');
  }
  return edge ? (left ? 'VM' : 'HM') : 'CM';
}

/// The general position of a position key from the team's details.
String? positionGroup(String? key) => switch (key) {
  'goalkeeper' => 'goalkeeper',
  'defender' ||
  'centre_back' ||
  'left_back' ||
  'right_back' ||
  'wing_back' => 'defender',
  'midfielder' ||
  'defensive_midfielder' ||
  'central_midfielder' ||
  'attacking_midfielder' => 'midfielder',
  'forward' || 'left_winger' || 'right_winger' || 'striker' => 'forward',
  _ => null,
};

/// Fills the empty slots from [available] (in the order to prefer):
/// first a player whose main position fits the slot, then one whose other
/// positions do, then anyone left. [filled] maps slot codes to players.
Map<String, String> autoFill(
  List<FormationSlot> slots,
  Map<String, String> filled,
  List<({String personId, String? main, List<String> positions})> available,
) {
  final result = Map.of(filled);
  final left = available
      .where((player) => !result.containsValue(player.personId))
      .toList();
  for (final pass in [0, 1, 2]) {
    for (final slot in slots) {
      if (result.containsKey(slot.code) || left.isEmpty) continue;
      final fit = left
          .where(
            (player) => switch (pass) {
              0 => positionGroup(player.main) == slot.group,
              1 => player.positions.any((p) => positionGroup(p) == slot.group),
              _ => true,
            },
          )
          .firstOrNull;
      if (fit == null) continue;
      result[slot.code] = fit.personId;
      left.remove(fit);
    }
  }
  return result;
}
