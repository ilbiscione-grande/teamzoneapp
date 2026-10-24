/// Efteranalys in the Match module (step 4): what the match's facts add up
/// to, the old app's analysis on Match Space v2. Everything is derived from
/// the facts, the line-up and the clock; nothing is kept twice.
library;

import 'package:teamzone_app/src/features/match_workspace/match_live_models.dart';

/// The minute the match ended (or has reached): the full-time fact's
/// minute, else the periods' length once completed, else [current].
int matchEndMinute({
  required String state,
  required List<Map<String, dynamic>> facts,
  required List<int> periodMinutes,
  required int current,
}) {
  final fullTime = activeFacts(facts)
      .where((fact) => fact['fact_type'] == 'full_time')
      .map((fact) => (fact['minute'] as num?)?.toInt() ?? 0)
      .fold<int?>(null, (a, b) => a == null || b > a ? b : a);
  if (fullTime != null && fullTime > 0) return fullTime;
  if (state == 'completed') return periodMinutes.fold(0, (a, b) => a + b);
  return state == 'planning' ? 0 : current;
}

/// The period (1, 2 …) a minute falls in, by the periods' lengths; past
/// the last it is the last.
int periodOf(int minute, List<int> periodMinutes) {
  var end = 0;
  for (var i = 0; i < periodMinutes.length; i++) {
    end += periodMinutes[i];
    if (minute <= end) return i + 1;
  }
  return periodMinutes.isEmpty ? 1 : periodMinutes.length;
}

/// Minutes on the pitch per player: the starters from 0, each of our
/// substitutions ending one spell and starting another, up to [end].
Map<String, int> playingMinutes(
  List<String> starters,
  List<Map<String, dynamic>> facts,
  int end,
) {
  final since = <String, int>{for (final id in starters) id: 0};
  final minutes = <String, int>{};
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
    final at = ((sub['minute'] as num?)?.toInt() ?? 0).clamp(0, end);
    final off = sub['club_person_id'] as String?;
    final on = sub['secondary_club_person_id'] as String?;
    if (off != null && since.containsKey(off)) {
      minutes[off] = (minutes[off] ?? 0) + at - since.remove(off)!;
    }
    if (on != null && !since.containsKey(on)) since[on] = at;
  }
  for (final MapEntry(key: id, value: from) in since.entries) {
    minutes[id] = (minutes[id] ?? 0) + (end - from).clamp(0, end);
  }
  return minutes;
}

/// One player's match: minutes and what they did.
class PlayerMatchStats {
  PlayerMatchStats(this.personId);
  final String personId;
  int minutes = 0,
      goals = 0,
      assists = 0,
      shots = 0,
      onTarget = 0,
      fouls = 0,
      yellow = 0,
      red = 0,
      saves = 0;

  bool get started => _started;
  bool _started = false;
}

/// Our players' matches, most minutes first: everyone who started, came on
/// or did something.
List<PlayerMatchStats> playerStats({
  required List<String> starters,
  required List<Map<String, dynamic>> facts,
  required int end,
}) {
  final stats = <String, PlayerMatchStats>{};
  PlayerMatchStats of(String id) =>
      stats.putIfAbsent(id, () => PlayerMatchStats(id));
  for (final id in starters) {
    of(id)._started = true;
  }
  playingMinutes(
    starters,
    facts,
    end,
  ).forEach((id, value) => of(id).minutes = value);
  for (final fact in activeFacts(facts)) {
    if (fact['side'] == 'opponent') continue;
    final player = fact['club_person_id'] as String?;
    final second = fact['secondary_club_person_id'] as String?;
    final detail = (fact['detail'] as Map?) ?? const {};
    switch (fact['fact_type']) {
      case 'goal':
        if (player != null) {
          of(player)
            ..goals += 1
            ..shots += 1
            ..onTarget += 1;
        }
        if (second != null) of(second).assists += 1;
      case 'shot':
        if (player != null) {
          final stat = of(player)..shots += 1;
          if (detail['result'] == 'on_target') stat.onTarget += 1;
        }
      case 'card':
        if (player != null) {
          final stat = of(player)..fouls += 1;
          if (detail['color'] == 'yellow') stat.yellow += 1;
          if (detail['color'] == 'red') stat.red += 1;
        }
      case 'save':
        if (player != null) of(player).saves += 1;
    }
  }
  return stats.values.toList()..sort((a, b) {
    final byMinutes = b.minutes.compareTo(a.minutes);
    return byMinutes != 0 ? byMinutes : b.goals.compareTo(a.goals);
  });
}

/// One side's numbers for the summary.
typedef TeamTotals = ({
  int goals,
  int shots,
  int onTarget,
  int corners,
  int freeKicks,
  int penalties,
  int fouls,
  int yellow,
  int red,
  int saves,
});

TeamTotals teamTotals(List<Map<String, dynamic>> facts, String side) {
  var goals = 0, shots = 0, onTarget = 0, corners = 0, freeKicks = 0;
  var penalties = 0, fouls = 0, yellow = 0, red = 0, saves = 0;
  for (final fact in activeFacts(facts)) {
    if ((fact['side'] ?? 'us') != side) continue;
    final detail = (fact['detail'] as Map?) ?? const {};
    switch (fact['fact_type']) {
      case 'goal':
        goals += 1;
        shots += 1;
        onTarget += 1;
      case 'shot':
        shots += 1;
        if (detail['result'] == 'on_target') onTarget += 1;
      case 'corner':
        corners += 1;
      case 'free_kick':
        freeKicks += 1;
      case 'penalty':
        penalties += 1;
      case 'card':
        fouls += 1;
        if (detail['color'] == 'yellow') yellow += 1;
        if (detail['color'] == 'red') red += 1;
      case 'save':
        saves += 1;
    }
  }
  return (
    goals: goals,
    shots: shots,
    onTarget: onTarget,
    corners: corners,
    freeKicks: freeKicks,
    penalties: penalties,
    fouls: fouls,
    yellow: yellow,
    red: red,
    saves: saves,
  );
}
