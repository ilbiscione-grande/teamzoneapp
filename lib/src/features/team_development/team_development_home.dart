part of '../../app/teamzone_app.dart';

/// Text in the leader's language, for the new design's copy.
String _tdpText(BuildContext context, String swedish, String english) =>
    AppStrings.of(context).isSwedish ? swedish : english;

/// The ISO week number of [day].
int _tdpWeek(DateTime day) {
  final date = DateTime.utc(day.year, day.month, day.day);
  final thursday = _tdpShift(date, 4 - date.weekday);
  final first = DateTime.utc(thursday.year);
  return _tdpDaysBetween(first, thursday) ~/ 7 + 1;
}

/// The plan's principles by id, in the order given.
List<TeamPrinciple> _tdpPrinciples(SeasonPlan plan, List<String> ids) => [
  for (final id in ids)
    ?plan.principles.where((principle) => principle.id == id).firstOrNull,
];

/// Översikt (the new design, 2026-11-01): the team's development page. The
/// season's periods and blocks across the whole width on top (2026-11-02),
/// then two columns on a wide screen. The plan on the left: the block now,
/// its activities and goals. The team on the right: the players a load
/// signal points at and every player's load (step 8), the goals due for a
/// check-in, the season's goals and the dated ones.
class _TdpHome extends StatelessWidget {
  const _TdpHome({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) => _TdpFrame(
    controller: controller,
    maxWidth: 1400,
    top: (plan) => _TdpSeasonStrip(
      plan: plan,
      onOpen: () => _ModuleShell.select(context, 1),
      onCalendar: () =>
          _TdpCalendar.open(context, controller: controller, plan: plan),
    ),
    builder: (plan) => [_TdpHomeBody(controller: controller, plan: plan)],
  );
}

class _TdpHomeBody extends StatelessWidget {
  const _TdpHomeBody({required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final period = plan.currentOrNext(today);
    final block =
        plan.blockOn(today) ??
        plan.blocks.where((block) => block.startsOn.isAfter(today)).firstOrNull;
    final dated = [
      for (final goal in plan.goalsOf(GoalHorizon.short))
        if (goal.state == GoalState.open && !goal.targetOn!.isBefore(today))
          goal,
    ]..sort((a, b) => a.targetOn!.compareTo(b.targetOn!));
    final left = [
      _TdpNowCard(plan: plan, period: period, block: block),
      if (block != null || period != null) ...[
        const SizedBox(height: 12),
        _TdpBlockActivities(
          controller: controller,
          plan: plan,
          from: block?.startsOn ?? period!.startsOn,
          to: block?.endsOn ?? period!.endsOn,
          title: block == null
              ? _tdpText(
                  context,
                  'Aktiviteter i perioden',
                  'Activities in the period',
                )
              : _tdpText(
                  context,
                  'Aktiviteter i blocket',
                  'Activities in the block',
                ),
        ),
      ],
      if (block != null) ...[
        const SizedBox(height: 12),
        _TdpGoalGroup(
          controller: controller,
          plan: plan,
          title: _tdpText(context, 'Blockets mål', 'Block goals'),
          subtitle: block.name,
          goals: plan.goalsOf(GoalHorizon.block, blockId: block.id),
          empty: _tdpText(
            context,
            'Inga mål för blocket än.',
            'No goals for the block yet.',
          ),
          newGoal: (
            horizon: GoalHorizon.block,
            periodId: null,
            blockId: block.id,
          ),
        ),
      ],
      if (period != null) ...[
        const SizedBox(height: 12),
        _TdpGoalGroup(
          controller: controller,
          plan: plan,
          title: AppStrings.of(context).feature('Periodens mål'),
          subtitle: period.name,
          goals: plan.goalsOf(GoalHorizon.period, periodId: period.id),
          empty: AppStrings.of(context).feature('Inga mål för perioden än.'),
          newGoal: (
            horizon: GoalHorizon.period,
            periodId: period.id,
            blockId: null,
          ),
        ),
      ],
    ];
    final right = [
      _TdpTeamLoad(
        key: ValueKey('tdp-team-load-${plan.id}'),
        controller: controller,
        plan: plan,
      ),
      const SizedBox(height: 12),
      _TdpDue(controller: controller, plan: plan),
      _TdpGoalGroup(
        controller: controller,
        plan: plan,
        title: AppStrings.of(context).feature('Säsongsmål'),
        subtitle: _tdpText(context, 'Långsiktiga', 'Long-term'),
        goals: plan.goalsOf(GoalHorizon.season),
        empty: AppStrings.of(context).feature('Inga säsongsmål än.'),
        newGoal: (horizon: GoalHorizon.season, periodId: null, blockId: null),
      ),
      if (dated.isNotEmpty) ...[
        const SizedBox(height: 12),
        _TdpGoalGroup(
          controller: controller,
          plan: plan,
          title: AppStrings.of(context).feature('Kommande kortsiktiga mål'),
          goals: dated,
          empty: '',
          newGoal: (horizon: GoalHorizon.short, periodId: null, blockId: null),
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TdpHomeHeader(controller: controller, plan: plan),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 960
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: left,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: right,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...left, const SizedBox(height: 12), ...right],
                ),
        ),
      ],
    );
  }
}

/// The season's name and dates, how far it has come, the other seasons,
/// and the way to plan it.
class _TdpHomeHeader extends StatelessWidget {
  const _TdpHomeHeader({required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final total = _tdpDaysBetween(plan.startsOn, plan.endsOn) + 1;
    final gone = (_tdpDaysBetween(plan.startsOn, today) + 1).clamp(0, total);
    final progress = today.isBefore(plan.startsOn)
        ? AppStrings.of(context).formatFeature('Börjar om {days} dagar', {
            'days': _tdpDaysBetween(today, plan.startsOn),
          })
        : today.isAfter(plan.endsOn)
        ? AppStrings.of(context).feature('Säsongen är slut')
        : AppStrings.of(context).formatFeature('Dag {day} av {total}', {
            'day': gone,
            'total': total,
          });
    return Column(
      key: const Key('tdp-season-card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tdpText(
                            context,
                            'Lagets utveckling',
                            'Team development',
                          ),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${plan.title} · '
                          '${_tdpRange(context, plan.startsOn, plan.endsOn)} · '
                          '$progress',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              key: const Key('tdp-open-planner'),
              onPressed: () => _ModuleShell.select(context, 1),
              icon: const Icon(Icons.view_timeline_outlined),
              label: Text(
                MediaQuery.sizeOf(context).width < 600
                    ? AppStrings.of(context).feature('Planera')
                    : AppStrings.of(context).feature('Planera säsongen'),
              ),
            ),
          ],
        ),
        if (plan.vision.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _TdpRichText(
            plan.vision,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

/// Just nu: the block now (or next) in its period, with its principles and
/// focus, and the block after it. Without blocks, the period; without
/// periods, the way to plan them.
class _TdpNowCard extends StatelessWidget {
  const _TdpNowCard({required this.plan, this.period, this.block});
  final SeasonPlan plan;
  final DevelopmentPeriod? period;
  final DevelopmentBlock? block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final block = this.block;
    final period = block == null
        ? this.period
        : plan.periods.where((p) => p.id == block.periodId).firstOrNull;
    if (period == null) {
      return _TdpHint(
        icon: Icons.view_timeline_outlined,
        text: plan.periods.isEmpty
            ? 'Planera säsongen'
            : 'Säsongens perioder är avslutade.',
      );
    }
    final siblings = plan.blocksOf(period.id);
    final now = (block?.contains(today) ?? false) || period.contains(today);
    final next = block == null
        ? null
        : plan.blocks
              .where((other) => other.startsOn.isAfter(block.endsOn))
              .firstOrNull;
    final principles = block == null
        ? const <TeamPrinciple>[]
        : _tdpPrinciples(plan, block.principleIds);
    final focus = (block?.focus.trim().isNotEmpty ?? false)
        ? block!.focus
        : period.focus;
    return Card(
      key: const Key('tdp-now'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.primary, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              now
                  ? _tdpText(
                      context,
                      'Just nu · vecka ${_tdpWeek(today)}',
                      'Right now · week ${_tdpWeek(today)}',
                    )
                  : _tdpText(
                      context,
                      'Nästa · börjar ${_tdpDate(context, block?.startsOn ?? period.startsOn)}',
                      'Next · starts ${_tdpDate(context, block?.startsOn ?? period.startsOn)}',
                    ),
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _TdpPhaseChip(phase: period.phase),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    block == null
                        ? period.name
                        : _tdpText(
                            context,
                            '${period.name} · block ${siblings.indexOf(block) + 1} av ${siblings.length}',
                            '${period.name} · block ${siblings.indexOf(block) + 1} of ${siblings.length}',
                          ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (block != null) ...[
              const SizedBox(height: 4),
              Text(
                block.name,
                key: const Key('tdp-now-block'),
                style: theme.textTheme.headlineSmall,
              ),
            ],
            if (principles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final principle in principles)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        principle.area.withBall
                            ? Icons.sports_soccer
                            : Icons.shield_outlined,
                        size: 16,
                      ),
                      label: Text(principle.title),
                    ),
                ],
              ),
            ],
            if (focus.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _TdpRichText(focus),
            ],
            const SizedBox(height: 8),
            Text(
              [
                _tdpRange(
                  context,
                  block?.startsOn ?? period.startsOn,
                  block?.endsOn ?? period.endsOn,
                ),
                if (next != null)
                  _tdpText(
                    context,
                    'nästa block: ${next.name}',
                    'next block: ${next.name}',
                  )
                else if (block == null)
                  _tdpText(
                    context,
                    'Dela upp perioden i block under Planera.',
                    'Split the period into blocks under Plan.',
                  ),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The season at a glance: the periods as bands in their phase's color, the
/// blocks as strips under them (those passed paler), and a line at today.
/// A tap opens the planning.
class _TdpSeasonStrip extends StatelessWidget {
  const _TdpSeasonStrip({
    required this.plan,
    required this.onOpen,
    required this.onCalendar,
  });
  final SeasonPlan plan;
  final VoidCallback onOpen, onCalendar;

  /// A block in its period's phase color.
  Color _blockColor(DevelopmentBlock block) => _tdpPhaseColor(
    plan.periods.where((p) => p.id == block.periodId).firstOrNull?.phase ??
        PeriodPhase.other,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final total = _tdpDaysBetween(plan.startsOn, plan.endsOn) + 1;
    double at(DateTime day) =>
        (_tdpDaysBetween(plan.startsOn, day) / total).clamp(0.0, 1.0);
    double span(DateTime from, DateTime to) =>
        ((_tdpDaysBetween(from, to) + 1) / total).clamp(0.0, 1.0);
    return Card(
      key: const Key('tdp-season-strip'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _tdpText(context, 'Säsongen', 'The season'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  // A phone has room for the icon only.
                  if (MediaQuery.sizeOf(context).width < 600)
                    IconButton(
                      key: const Key('tdp-open-calendar'),
                      tooltip: _tdpText(
                        context,
                        'Årskalender',
                        'Year calendar',
                      ),
                      onPressed: onCalendar,
                      icon: const Icon(Icons.calendar_month_outlined),
                    )
                  else
                    TextButton.icon(
                      key: const Key('tdp-open-calendar'),
                      onPressed: onCalendar,
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text(
                        _tdpText(context, 'Årskalender', 'Year calendar'),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.of(context).feature('Planera säsongen'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final months = [
                    for (
                      var month = DateTime(
                        plan.startsOn.year,
                        plan.startsOn.month,
                      );
                      !month.isAfter(plan.endsOn);
                      month = DateTime(month.year, month.month + 1)
                    )
                      month,
                  ];
                  final monthNames = MaterialLocalizations.of(context);
                  return SizedBox(
                    height: 82,
                    child: Stack(
                      children: [
                        for (final month in months)
                          Positioned(
                            left:
                                at(
                                  month.isBefore(plan.startsOn)
                                      ? plan.startsOn
                                      : month,
                                ) *
                                width,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                              child: Text(
                                monthNames
                                    .formatMonthYear(month)
                                    .split(' ')
                                    .first,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        for (final period in plan.periods)
                          Positioned(
                            left: at(period.startsOn) * width,
                            width: span(period.startsOn, period.endsOn) * width,
                            top: 20,
                            height: 30,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: _tdpPhaseColor(
                                  period.phase,
                                ).withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                period.name,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: _tdpPhaseColor(period.phase),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        for (final block in plan.blocks)
                          Positioned(
                            left: at(block.startsOn) * width + 1,
                            width:
                                (span(block.startsOn, block.endsOn) * width - 2)
                                    .clamp(1.0, width),
                            top: 54,
                            height: 24,
                            child: Tooltip(
                              message: block.name,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: _blockColor(block).withValues(
                                    alpha: block.endsOn.isBefore(today)
                                        ? 0.25
                                        : 0.9,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  block.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    // Passed blocks are pale, so dark text.
                                    color: block.endsOn.isBefore(today)
                                        ? _blockColor(block)
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!today.isBefore(plan.startsOn) &&
                            !today.isAfter(plan.endsOn))
                          Positioned(
                            left: at(today) * width,
                            top: 16,
                            bottom: 0,
                            width: 2,
                            child: ColoredBox(color: theme.colorScheme.error),
                          ),
                      ],
                    ),
                  );
                },
              ),
              if (plan.periods.isEmpty)
                Text(
                  _tdpText(
                    context,
                    'Inga perioder än. Lägg ut dem i Planera.',
                    'No periods yet. Lay them out under Plan.',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
