part of '../../app/teamzone_app.dart';

/// Whether the active context may see Laget → Statistik.
bool _canSeeTeamStatistics(TeamZoneContext value) =>
    value.teamId != null &&
    (value.can('event.attendance.manage') ||
        value.can('event.manage') ||
        value.can('team.roster.manage'));

String _percent(double? value) =>
    value == null ? '–' : '${value.toStringAsFixed(0)} %';

const _monthNames = [
  'jan', 'feb', 'mar', 'apr', 'maj', 'jun', //
  'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
];

const _monthNamesEnglish = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _monthLabel(String yyyyMm, {bool swedish = true}) {
  final month = (int.tryParse(yyyyMm.split('-').last) ?? 1) - 1;
  return (swedish ? _monthNames : _monthNamesEnglish)[month.clamp(0, 11)];
}

/// Laget → Statistik: how the team is doing over time, for the people who
/// manage it. Personal figures live on each member's profile.
class _TeamStatisticsView extends StatefulWidget {
  const _TeamStatisticsView({required this.contextValue, required this.roster});
  final TeamZoneContext contextValue;
  final RosterServices roster;

  @override
  State<_TeamStatisticsView> createState() => _TeamStatisticsViewState();
}

class _TeamStatisticsViewState extends State<_TeamStatisticsView> {
  var _period = TeamStatisticsPeriod.last90Days;
  late Future<TeamStatistics> _load = _fetch();

  Future<TeamStatistics> _fetch() {
    final range = _period.range(DateTime.now());
    return widget.roster
        .getTeamStatistics(
          teamId: widget.contextValue.teamId!,
          from: range.from,
          to: range.to,
        )
        .timeout(const Duration(seconds: 20));
  }

  @override
  void didUpdateWidget(covariant _TeamStatisticsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) _reload();
  }

  void _reload() => setState(() {
    _load = _fetch();
  });

  void _openPerson(String personId) =>
      GoRouter.of(context).push(ProductRouteContract.teamMember(personId));

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<TeamStatistics>(
      future: _load,
      builder: (context, snapshot) {
        final children = <Widget>[
          SegmentedButton<TeamStatisticsPeriod>(
            key: const Key('team-statistics-period'),
            segments: [
              ButtonSegment(
                value: TeamStatisticsPeriod.last30Days,
                label: Text(strings.feature('30 dagar')),
              ),
              ButtonSegment(
                value: TeamStatisticsPeriod.last90Days,
                label: Text(strings.feature('90 dagar')),
              ),
              ButtonSegment(
                value: TeamStatisticsPeriod.thisYear,
                label: Text(strings.feature('I år')),
              ),
            ],
            selected: {_period},
            onSelectionChanged: (value) {
              _period = value.first;
              _reload();
            },
          ),
          const SizedBox(height: 16),
        ];
        if (snapshot.connectionState != ConnectionState.done) {
          children.add(AppLoadingIndicator(label: strings.loading));
        } else if (snapshot.hasError || snapshot.data == null) {
          children.add(
            _StateCard(
              icon: Icons.sync_problem,
              title: strings.feature('Statistiken kunde inte laddas'),
              message: strings.safeError,
              action: FilledButton(
                onPressed: _reload,
                child: Text(strings.retry),
              ),
            ),
          );
        } else {
          children.addAll(_content(context, snapshot.data!));
        }
        return ListView(
          key: const Key('team-statistics'),
          padding: const EdgeInsets.all(16),
          children: children,
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, TeamStatistics stats) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    if (stats.events == 0) {
      return [
        _StateCard(
          icon: Icons.query_stats,
          title: strings.feature('Inga aktiviteter under perioden'),
          message: strings.feature(
            'Statistiken visas när laget har genomfört aktiviteter.',
          ),
        ),
      ];
    }
    final lowest = stats.lowestAttendance();
    return [
      Text(
        strings.isSwedish
            ? '${stats.events} aktiviteter: ${stats.trainings} träningar, '
                  '${stats.matches} matcher'
                  '${stats.otherEvents > 0 ? ', ${stats.otherEvents} övriga' : ''}.'
            : '${stats.events} activities: ${stats.trainings} trainings, '
                  '${stats.matches} matches'
                  '${stats.otherEvents > 0 ? ', ${stats.otherEvents} other' : ''}.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _TeamStatTile(
            label: strings.feature('Närvaro'),
            value: _percent(stats.attendanceRate),
          ),
          _TeamStatTile(
            label: strings.feature('Träningar'),
            value: _percent(stats.trainingRate),
          ),
          _TeamStatTile(
            label: strings.feature('Matcher'),
            value: _percent(stats.matchRate),
          ),
          _TeamStatTile(
            label: strings.feature('Svar på kallelser'),
            value: _percent(stats.responseRate),
          ),
          _TeamStatTile(
            label: strings.feature('Sena ankomster'),
            value: '${stats.late}',
          ),
        ],
      ),
      if (stats.months.length >= 2) ...[
        const SizedBox(height: 24),
        Text(
          strings.feature('Närvaro per månad'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _MonthlyAttendanceChart(months: stats.months),
      ],
      if (lowest.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text(
          strings.feature('Lägst närvaro'),
          style: theme.textTheme.titleMedium,
        ),
        Text(
          strings.feature('Spelare med minst tre räknade aktiviteter.'),
          style: theme.textTheme.bodySmall,
        ),
        for (final person in lowest)
          _PersonStatisticsRow(
            key: ValueKey('team-statistics-lowest-${person.personId}'),
            person: person,
            onTap: () => _openPerson(person.personId),
          ),
      ],
      const SizedBox(height: 24),
      Text(
        '${strings.feature('Spelare')} (${stats.players.length})',
        style: theme.textTheme.titleMedium,
      ),
      for (final person in stats.players)
        _PersonStatisticsRow(
          key: ValueKey('team-statistics-person-${person.personId}'),
          person: person,
          detailed: true,
          onTap: () => _openPerson(person.personId),
        ),
      if (stats.leaders.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text(
          '${strings.feature('Ledare')} (${stats.leaders.length})',
          style: theme.textTheme.titleMedium,
        ),
        for (final person in stats.leaders)
          _PersonStatisticsRow(
            person: person,
            onTap: () => _openPerson(person.personId),
          ),
      ],
      const SizedBox(height: 16),
      Text(
        strings.feature(
          'Närvarande, sen och delvis räknas som närvaro. Frånvaro räknas '
          'bara för den som var kallad (eller när aktiviteten saknade '
          'kallelser). Oregistrerad närvaro räknas inte. Lagets andelar '
          'gäller spelarna. Tryck på en person för hens egen statistik.',
        ),
        style: theme.textTheme.bodySmall,
      ),
    ];
  }
}

/// A headline number (not a chart).
class _TeamStatTile extends StatelessWidget {
  const _TeamStatTile({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: theme.textTheme.headlineSmall),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// One series (the players' attendance rate) per month: thin bars on a
/// shared 0–100 % baseline, rounded data ends, 2 px gaps, the latest value
/// labelled, every bar with a tooltip and a screen-reader label.
class _MonthlyAttendanceChart extends StatelessWidget {
  const _MonthlyAttendanceChart({required this.months});
  final List<TeamStatisticsMonth> months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sv = AppStrings.of(context).isSwedish;
    final color = theme.colorScheme.primary;
    final muted = theme.colorScheme.outlineVariant;
    const height = 120.0;
    return SizedBox(
      height: height + 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (index, month) in months.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Semantics(
                  label:
                      '${_monthLabel(month.month, swedish: sv)} ${month.month.split('-').first}: '
                      '${_percent(month.attendanceRate)} ${sv ? 'närvaro' : 'attendance'}',
                  excludeSemantics: true,
                  child: Tooltip(
                    message:
                        '${_monthLabel(month.month, swedish: sv)}: ${_percent(month.attendanceRate)}'
                        '${month.trainingRate == null ? '' : ' · ${sv ? 'träningar' : 'trainings'} ${_percent(month.trainingRate)}'}'
                        '${month.matchRate == null ? '' : ' · ${sv ? 'matcher' : 'matches'} ${_percent(month.matchRate)}'}',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 16,
                          child: index == months.length - 1
                              ? Text(
                                  _percent(month.attendanceRate),
                                  style: theme.textTheme.labelSmall,
                                )
                              : null,
                        ),
                        Container(
                          height: height,
                          alignment: Alignment.bottomCenter,
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: muted)),
                          ),
                          child: FractionallySizedBox(
                            heightFactor: ((month.attendanceRate ?? 0) / 100)
                                .clamp(0, 1),
                            widthFactor: 0.6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _monthLabel(month.month, swedish: sv),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonStatisticsRow extends StatelessWidget {
  const _PersonStatisticsRow({
    required this.person,
    required this.onTap,
    this.detailed = false,
    super.key,
  });
  final TeamStatisticsPerson person;
  final VoidCallback onTap;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final sv = AppStrings.of(context).isSwedish;
    final parts = [
      '${person.attended} ${sv ? 'av' : 'of'} ${person.counted}',
      if (detailed && person.trainingsCounted > 0)
        '${sv ? 'träningar' : 'trainings'} ${person.trainingsAttended}/${person.trainingsCounted}',
      if (detailed && person.matchesCounted > 0)
        '${sv ? 'matcher' : 'matches'} ${person.matchesAttended}/${person.matchesCounted}',
      if (detailed && person.late > 0) '${person.late} ${sv ? 'sen' : 'late'}',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(person.name),
      subtitle: Text(parts.join(' · ')),
      trailing: Text(
        _percent(person.rate),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: onTap,
    );
  }
}
