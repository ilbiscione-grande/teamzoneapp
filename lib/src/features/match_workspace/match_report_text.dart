/// A match report written from the registered events (Efteranalys): the
/// result, the match told event by event as a reporter would, both teams'
/// numbers, the scorers and the KPI goals. Notes stay out; they are the
/// leaders' own. Plain templates (match_report_wordings.dart), several for
/// each kind of event; [variant] picks among them, so the same events and
/// variant give the same text and another variant words it anew. The
/// leader reads and changes it before it is saved.
library;

import 'package:teamzone_app/src/features/match_workspace/match_analysis_models.dart';
import 'package:teamzone_app/src/features/match_workspace/match_live_models.dart';
import 'package:teamzone_app/src/features/match_workspace/match_report_wordings.dart';

/// A KPI goal as the report states it.
typedef ReportKpi = ({String label, String value, String goal, bool? achieved});

/// "12:e", "21:a": the minute as Swedish says it.
String _ordinal(int minute) {
  final last = minute % 10, lastTwo = minute % 100;
  return '$minute:${(last == 1 || last == 2) && lastTwo != 11 && lastTwo != 12 ? 'a' : 'e'}';
}

/// "Lindström" → "Lindströms", "Aneby SK" → "Aneby SK:s", "Lukas" stays.
String _owner(String name) {
  if (name.isEmpty) return name;
  final last = name[name.length - 1];
  if ('sxzSXZ'.contains(last)) return name;
  if (RegExp(r'[A-ZÅÄÖ0-9]').hasMatch(last)) return '$name:s';
  return '${name}s';
}

String _capitalised(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

String generatedMatchReport({
  required String team,
  required String opponent,
  required String? homeAway,
  required int scoreUs,
  required int scoreOpponent,
  required bool completed,
  required List<Map<String, dynamic>> facts,
  required List<int> periodMinutes,
  required String Function(String?) name,
  List<ReportKpi> kpis = const [],
  int variant = 0,
}) {
  final standing = activeFacts(facts).toList()
    ..sort(
      (a, b) =>
          ((a['minute'] as num?) ?? 0).compareTo((b['minute'] as num?) ?? 0),
    );
  int minuteOf(Map<String, dynamic> fact) =>
      (fact['minute'] as num?)?.toInt() ?? 0;
  bool ours(Map<String, dynamic> fact) => fact['side'] != 'opponent';
  Iterable<Map<String, dynamic>> ofType(String type) =>
      standing.where((fact) => fact['fact_type'] == type);

  // Who is who, by where the match was played.
  final (ourOwner, theirSide, theirOwner, venue) = switch (homeAway) {
    'home' => ('hemmalagets', 'gästerna', 'gästernas', ' på hemmaplan'),
    'away' => ('bortalagets', 'hemmalaget', 'hemmalagets', ' på bortaplan'),
    _ => (_owner(team), opponent, _owner(opponent), ''),
  };

  // Each kind of sentence takes its wordings in turn, from [variant].
  final used = <String, int>{};
  String pick(String group, List<String> wordings, {bool named = true}) {
    // Without a player, a wording naming both the player and the team
    // would name the team twice.
    final fitting = named
        ? wordings
        : wordings
              .where((w) => !(w.contains('{p}') && w.contains('{t}')))
              .toList();
    final choices = fitting.isEmpty ? wordings : fitting;
    final turn = used[group] = (used[group] ?? -1) + 1;
    return choices[(variant + turn) % choices.length];
  }

  String fill(
    String template, {
    required int minute,
    String? player,
    String? keeper,
    String? assist,
    String? on,
    String? off,
    String? score,
  }) {
    var text = template;
    if (keeper != null || template.contains('målvakt {p}')) {
      // A save: the keeper by name, or "the keeper" when not chosen.
      text = keeper == null
          ? text
                .replaceAll('{tg} målvakt {p}', '{tg} målvakt')
                .replaceAll('{p} i målet', 'målvakten')
                .replaceAll('{p}', 'målvakten')
          : text.replaceAll('{p}', keeper);
    } else if (player == null) {
      // Ours without a player: the team itself.
      text = text.replaceAll('{tg} {p}', '{t}').replaceAll('{p}', '{t}');
    }
    return _capitalised(
      text
          .replaceAll('{a}', assist ?? '')
          .replaceAll('{p}', player ?? team)
          .replaceAll('{tg}', ourOwner)
          .replaceAll('{t}', team)
          .replaceAll('{og}', theirOwner)
          .replaceAll('{od}', theirSide)
          .replaceAll('{o}', opponent)
          .replaceAll('{in}', on ?? '')
          .replaceAll('{out}', off ?? '')
          .replaceAll('{s}', score ?? '')
          .replaceAll('{home}', venue)
          .replaceAll('{min}', _ordinal(minute))
          .replaceAll('{n}', '$minute'),
    );
  }

  final out = StringBuffer();
  // The result.
  final score = '$scoreUs–$scoreOpponent';
  if (completed) {
    final outcome = switch (scoreUs.compareTo(scoreOpponent)) {
      > 0 => 'win',
      < 0 => 'loss',
      _ => 'draw',
    };
    out.writeln(
      fill(pick('intro', reportIntros[outcome]!), minute: 0, score: score),
    );
  } else {
    out.writeln(switch (scoreUs.compareTo(scoreOpponent)) {
      > 0 => '$team leder$venue mot $opponent med $score.',
      < 0 => '$team ligger under$venue mot $opponent med $score.',
      _ => 'Det står $score$venue mot $opponent.',
    });
  }
  final goals = ofType('goal').toList();
  if (periodMinutes.length == 2 && goals.isNotEmpty) {
    final first = goals.where((g) => minuteOf(g) <= periodMinutes.first);
    final us = first.where(ours).length, them = first.length - us;
    out.writeln('I halvtid stod det $us–$them.');
  }

  // The match, event by event.
  final story = <String>[];
  var us = 0, them = 0;
  for (final fact in standing) {
    final minute = minuteOf(fact);
    final mine = ours(fact);
    final player = fact['club_person_id'] as String?;
    final second = fact['secondary_club_person_id'] as String?;
    final detail = (fact['detail'] as Map?) ?? const {};
    final who = player == null ? null : name(player);
    switch (fact['fact_type']) {
      case 'goal':
        final lead = mine ? us - them : them - us;
        mine ? us++ : them++;
        final context = switch (lead) {
          0 => 'lead',
          > 0 => 'extend',
          -1 => 'equalise',
          _ => 'reduce',
        };
        story.add(
          mine
              ? fill(
                  pick(
                    'goal-$context',
                    reportGoalsUs[context]!,
                    named: who != null,
                  ),
                  minute: minute,
                  player: who,
                  score: '$us–$them',
                  assist: second == null
                      ? null
                      : pick(
                          'assist',
                          reportAssists,
                        ).replaceAll('{a}', name(second)),
                )
              : fill(
                  pick('goal-them-$context', reportGoalsThem[context]!),
                  minute: minute,
                  score: '$us–$them',
                ),
        );
      case 'shot':
        final result = detail['result'] as String? ?? 'missed';
        final wordings = mine ? reportShotsUs : reportShotsThem;
        story.add(
          fill(
            pick(
              'shot-$mine-$result',
              wordings[result] ?? wordings['missed']!,
              named: !mine || who != null,
            ),
            minute: minute,
            player: who,
          ),
        );
      case 'save' when mine:
        story.add(fill(pick('save', reportSaves), minute: minute, keeper: who));
      case 'penalty':
        final result = detail['result'] as String? ?? 'scored';
        final wordings = (mine
            ? reportPenaltiesUs
            : reportPenaltiesThem)[result];
        if (wordings != null) {
          story.add(
            fill(
              pick(
                'penalty-$mine-$result',
                wordings,
                named: !mine || who != null,
              ),
              minute: minute,
              player: who,
            ),
          );
        }
      case 'card':
        final colour = detail['color'] as String?;
        final wordings = (mine ? reportCardsUs : reportCardsThem)[colour];
        if (wordings != null) {
          story.add(
            fill(
              pick('card-$mine-$colour', wordings, named: !mine || who != null),
              minute: minute,
              player: who,
            ),
          );
        }
      case 'substitution' when mine:
        story.add(
          fill(
            pick('substitution', reportSubstitutions),
            minute: minute,
            player: who,
            on: name(second),
            off: name(player),
          ),
        );
      case 'injury' when mine:
        story.add(
          fill(
            pick('injury', reportInjuries, named: who != null),
            minute: minute,
            player: who,
          ),
        );
    }
  }
  if (story.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Matchens gång');
    story.forEach(out.writeln);
  }

  // Both teams' numbers.
  final mine = teamTotals(facts, 'us'), theirs = teamTotals(facts, 'opponent');
  final numbers = [
    if (mine.shots + theirs.shots > 0)
      'avslut ${mine.shots}–${theirs.shots} (på mål ${mine.onTarget}–${theirs.onTarget})',
    if (mine.corners + theirs.corners > 0)
      'hörnor ${mine.corners}–${theirs.corners}',
    if (mine.freeKicks + theirs.freeKicks > 0)
      'frisparkar ${mine.freeKicks}–${theirs.freeKicks}',
    if (mine.penalties + theirs.penalties > 0)
      'straffar ${mine.penalties}–${theirs.penalties}',
    if (mine.fouls + theirs.fouls > 0) 'fouls ${mine.fouls}–${theirs.fouls}',
    if (mine.saves + theirs.saves > 0)
      'räddningar ${mine.saves}–${theirs.saves}',
  ];
  if (numbers.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Statistik ($team–$opponent)')
      ..writeln('${_capitalised(numbers.join(', '))}.');
  }

  // The scorers.
  final scorers = <String, int>{};
  for (final goal in goals.where(ours)) {
    final scorer = goal['club_person_id'] as String?;
    if (scorer != null) scorers[scorer] = (scorers[scorer] ?? 0) + 1;
  }
  if (scorers.isNotEmpty) {
    final list = scorers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    out
      ..writeln()
      ..writeln(
        'Målskyttar: ${list.map((e) => e.value > 1 ? '${name(e.key)} ${e.value}' : name(e.key)).join(', ')}.',
      );
  }

  // The KPI goals.
  if (kpis.isNotEmpty) {
    final judged = kpis.where((k) => k.achieved != null).toList();
    final achieved = judged.where((k) => k.achieved == true).length;
    out
      ..writeln()
      ..writeln(
        judged.isEmpty
            ? 'Matchmål'
            : 'Matchmål: $achieved av ${judged.length} uppnådda',
      );
    for (final kpi in kpis) {
      final mark = switch (kpi.achieved) {
        true => ' ✓',
        false => ' ✗',
        null => '',
      };
      out.writeln('${kpi.label}: ${kpi.value} (mål ${kpi.goal})$mark');
    }
  }
  return out.toString().trimRight();
}
