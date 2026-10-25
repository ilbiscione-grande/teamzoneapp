part of '../../app/teamzone_app.dart';

/// The result and both teams' numbers side by side, ours to the left.
class _AnalysisSummary extends StatelessWidget {
  const _AnalysisSummary({
    required this.sides,
    required this.opponentName,
    required this.scoreUs,
    required this.scoreOpponent,
    required this.completed,
    required this.us,
    required this.them,
  });
  final _MatchSides sides;
  final String opponentName;
  final int scoreUs, scoreOpponent;
  final bool completed;
  final TeamTotals us, them;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rows = [
      ('Avslut', us.shots, them.shots),
      ('På mål', us.onTarget, them.onTarget),
      ('Hörnor', us.corners, them.corners),
      ('Frisparkar', us.freeKicks, them.freeKicks),
      ('Straffar', us.penalties, them.penalties),
      ('Fouls', us.fouls, them.fouls),
      ('Gula kort', us.yellow, them.yellow),
      ('Röda kort', us.red, them.red),
      ('Räddningar', us.saves, them.saves),
    ].where((row) => row.$2 + row.$3 > 0).toList();
    return Card(
      key: const Key('analysis-summary'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              AppStrings.of(
                context,
              ).feature(completed ? 'Slutresultat' : 'Ställning just nu'),
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    sides.team,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '$scoreUs – $scoreOpponent',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(opponentName, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            if (rows.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  AppStrings.of(
                    context,
                  ).feature('Inga händelser registrerade i Live.'),
                ),
              ),
            for (final (label, ours, theirs) in rows)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(width: 32, child: Text('$ours')),
                        Expanded(
                          child: Text(
                            AppStrings.of(context).feature(label),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text('$theirs', textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Our share of the two, from the left.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ours / (ours + theirs),
                        minHeight: 6,
                        color: colors.primary,
                        backgroundColor: const Color(0xFFD84343),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Every placed event on the pitch, filtered by team, period and kind; a
/// tap on one explains it and leads to it in the list.
class _AnalysisPitch extends StatelessWidget {
  const _AnalysisPitch({
    required this.facts,
    required this.periodMinutes,
    required this.opponentName,
    required this.side,
    required this.period,
    required this.types,
    required this.onSide,
    required this.onPeriod,
    required this.onTypes,
    required this.selectedId,
    required this.onTapMark,
    required this.tooltipFor,
  });
  final List<Map<String, dynamic>> facts;
  final List<int> periodMinutes;
  final String opponentName, side;

  /// 0 for the whole match.
  final int period;

  /// The kinds shown; null for all.
  final Set<String>? types;
  final ValueChanged<String> onSide;
  final ValueChanged<int> onPeriod;
  final ValueChanged<Set<String>?> onTypes;
  final String? selectedId;
  final ValueChanged<String?> onTapMark;
  final Widget? Function(String id) tooltipFor;

  static String _label(String type) =>
      type == 'goal' ? 'Mål' : liveEventKind(type)?.label ?? type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placed = [
      for (final fact in activeFacts(facts))
        if (factLocation(fact) case (final x, final y)) (fact, x, y),
    ];
    final kinds = {
      for (final (fact, _, _) in placed) fact['fact_type'] as String? ?? '',
    };
    final shown = placed.where((entry) {
      final fact = entry.$1;
      final minute = (fact['minute'] as num?)?.toInt() ?? 0;
      return (side == 'all' || (fact['side'] ?? 'us') == side) &&
          (period == 0 || periodOf(minute, periodMinutes) == period) &&
          (types == null || types!.contains(fact['fact_type']));
    }).toList();
    Color color(Map<String, dynamic> fact) => fact['fact_type'] == 'goal'
        ? const Color(0xFFF2B705)
        : fact['side'] == 'opponent'
        ? const Color(0xFFD84343)
        : theme.colorScheme.primary;
    bool filled(Map<String, dynamic> fact) {
      final result = (fact['detail'] as Map?)?['result'];
      return fact['fact_type'] != 'shot' || result == 'on_target';
    }

    return Card(
      key: const Key('analysis-pitch'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.of(context).feature('Händelser på planen'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ShotSideDropdown(
                  value: side,
                  opponentName: opponentName,
                  onChanged: onSide,
                ),
                if (periodMinutes.length > 1) ...[
                  DropdownButton<int>(
                    key: const Key('analysis-period'),
                    value: period,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(AppStrings.of(context).feature('Hela')),
                      ),
                      for (var i = 1; i <= periodMinutes.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            _LiveScoreboard._period(
                              i,
                              periodMinutes.length,
                              AppStrings.of(context),
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) => onPeriod(value ?? 0),
                  ),
                ],
              ],
            ),
            if (kinds.length > 1) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kind in kinds)
                    FilterChip(
                      key: Key('analysis-kind-$kind'),
                      avatar: Icon(_liveIcon(kind), size: 16),
                      label: Text(AppStrings.of(context).feature(_label(kind))),
                      selected: types == null || types!.contains(kind),
                      onSelected: (on) {
                        final next = {...(types ?? kinds)};
                        on ? next.add(kind) : next.remove(kind);
                        onTypes(next.length == kinds.length ? null : next);
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            _LocationPitch(
              marks: [
                for (final (fact, x, y) in shown)
                  (
                    x: x,
                    y: y,
                    color: color(fact),
                    filled: filled(fact),
                    id: fact['id'] as String?,
                  ),
              ],
              onTapMark: onTapMark,
              selectedId: selectedId,
              tooltip: selectedId == null ? null : tooltipFor(selectedId!),
            ),
            const SizedBox(height: 6),
            Text(
              placed.isEmpty
                  ? AppStrings.of(
                      context,
                    ).feature('Inga händelser markerades på planen.')
                  : AppStrings.of(context).formatFeature(
                      '{shown} av {total} händelser · tryck på en för att se den',
                      {'shown': shown.length, 'total': placed.length},
                    ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Minutes and numbers per player, most minutes first.
class _AnalysisPlayers extends StatelessWidget {
  const _AnalysisPlayers({
    required this.stats,
    required this.name,
    required this.number,
    required this.end,
  });
  final List<PlayerMatchStats> stats;
  final String Function(String?) name;
  final int? Function(String) number;
  final int end;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chip(IconData icon, int value, String tip, [Color? color]) =>
        Tooltip(
          message: tip,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color ?? theme.colorScheme.primary),
                const SizedBox(width: 2),
                Text('$value', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        );
    return Card(
      key: const Key('analysis-players'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.of(context).feature('Speltid och statistik'),
              style: theme.textTheme.titleSmall,
            ),
            if (stats.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  AppStrings.of(context).feature(
                    'Ingen speltid än. Den räknas fram ur startelvan och bytena i Live.',
                  ),
                ),
              ),
            for (final stat in stats)
              ListTile(
                key: Key('analysis-player-${stat.personId}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 15,
                  child: Text(
                    number(stat.personId)?.toString() ?? '–',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text(name(stat.personId)),
                subtitle: Text(
                  '${stat.minutes} av $end min${stat.started ? '' : ' · inbytt'}',
                ),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (stat.goals > 0)
                      chip(Icons.sports_soccer, stat.goals, 'Mål'),
                    if (stat.assists > 0)
                      chip(Icons.assistant_outlined, stat.assists, 'Assist'),
                    if (stat.shots > 0)
                      chip(
                        Icons.gps_fixed,
                        stat.shots,
                        'Avslut (${stat.onTarget} på mål)',
                      ),
                    if (stat.saves > 0)
                      chip(Icons.pan_tool_outlined, stat.saves, 'Räddningar'),
                    if (stat.fouls > 0)
                      chip(
                        Icons.style_outlined,
                        stat.fouls,
                        'Fouls',
                        theme.colorScheme.outline,
                      ),
                    if (stat.yellow > 0)
                      chip(
                        Icons.square_rounded,
                        stat.yellow,
                        'Gula kort',
                        Colors.amber.shade700,
                      ),
                    if (stat.red > 0)
                      chip(
                        Icons.square_rounded,
                        stat.red,
                        'Röda kort',
                        Colors.red,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The KPI goals from Förberedelse with their outcome, and the own
/// buttons' counts.
class _AnalysisKpis extends StatelessWidget {
  const _AnalysisKpis({
    required this.kpis,
    required this.buttons,
    required this.counts,
  });
  final List<EventKpi> kpis;
  final List<MatchButton> buttons;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final counted = buttons.where((b) => (counts[b.id] ?? 0) > 0).toList();
    if (kpis.isEmpty && counted.isEmpty) return const SizedBox.shrink();
    final achieved = kpis.where((k) => k.status == 'achieved').length;
    final judged = kpis
        .where((k) => const ['achieved', 'missed'].contains(k.status))
        .length;
    return Card(
      key: const Key('analysis-kpis'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kpis.isEmpty
                  ? 'Räknare'
                  : 'Matchmål · $achieved av $judged uppnådda',
              style: theme.textTheme.titleSmall,
            ),
            for (final kpi in kpis)
              ListTile(
                key: Key('analysis-kpi-${kpi.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: switch (kpi.status) {
                  'achieved' => Icon(
                    Icons.check_circle,
                    color: Colors.green.shade600,
                  ),
                  'missed' => Icon(Icons.cancel, color: colors.error),
                  _ => Icon(
                    Icons.radio_button_unchecked,
                    color: colors.outline,
                  ),
                },
                title: Text(_localizedKpiLabel(context, kpi.kpiKey, kpi.label)),
                subtitle: Text(
                  AppStrings.of(context).formatFeature('Mål: {value}', {
                    'value': _kpiGoalText(context, kpi),
                  }),
                ),
                trailing: Text(
                  kpi.actual == null
                      ? 'Ej ifyllt'
                      : _kpiValueText(context, kpi.valueType, kpi.actual),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            if (counted.isNotEmpty && kpis.isNotEmpty) const Divider(),
            for (final button in counted)
              ListTile(
                key: Key('analysis-button-${button.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.exposure_plus_1, color: colors.primary),
                title: Text(button.label),
                trailing: Text(
                  '${counts[button.id]}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The event's written match report: read here, written by those who may,
/// by hand or from the registered events (a draft to read and change).
class _AnalysisReport extends StatelessWidget {
  const _AnalysisReport({required this.report, this.onWrite, this.onGenerate});
  final WrittenMatchReport? report;
  final VoidCallback? onWrite, onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = report;
    if (value == null) return const SizedBox.shrink();
    final empty = value.body.trim().isEmpty;
    if (empty && onWrite == null) return const SizedBox.shrink();
    return Card(
      key: const Key('analysis-report'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.of(context).feature('Matchrapport'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (!empty)
                  Text(
                    value.published ? 'Publicerad' : 'Utkast',
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              empty ? 'Ingen rapport skriven än.' : value.body,
              style: empty ? theme.textTheme.bodySmall : null,
            ),
            if (onWrite != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('analysis-report-write'),
                    onPressed: onWrite,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(empty ? 'Skriv själv' : 'Redigera'),
                  ),
                  if (onGenerate != null)
                    FilledButton.tonalIcon(
                      key: const Key('analysis-report-generate'),
                      onPressed: onGenerate,
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text(
                        AppStrings.of(
                          context,
                        ).feature('Skapa från händelserna'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
