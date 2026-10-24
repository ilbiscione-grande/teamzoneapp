part of '../../app/teamzone_app.dart';

/// A phase's color on the timeline and on its chip.
Color _tdpPhaseColor(PeriodPhase phase) => switch (phase) {
  PeriodPhase.preseason => const Color(0xFF2E7D5B),
  PeriodPhase.competition => const Color(0xFF6A4C93),
  PeriodPhase.breakTime => const Color(0xFF8D99AE),
  PeriodPhase.other => const Color(0xFFB8562B),
};

class _TdpPhaseChip extends StatelessWidget {
  const _TdpPhaseChip({required this.phase});
  final PeriodPhase phase;

  @override
  Widget build(BuildContext context) {
    final color = _tdpPhaseColor(phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        phase.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Säsongen: the season's dates and vision, its periods on a timeline with
/// today marked, and each period with its focus and goals.
class _TdpSeason extends StatelessWidget {
  const _TdpSeason({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) => _TdpFrame(
    controller: controller,
    action: (plan) => FilledButton.tonalIcon(
      key: const Key('tdp-new-period'),
      onPressed: () => _TdpPeriodDialog.edit(context, controller, plan),
      icon: const Icon(Icons.add),
      label: const Text('Ny period'),
    ),
    builder: (plan) {
      final theme = Theme.of(context);
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.title,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    if (controller.canEdit)
                      IconButton(
                        key: const Key('tdp-edit-season'),
                        tooltip: 'Ändra säsongen',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editSeason(context, plan),
                      ),
                  ],
                ),
                Text(_tdpRange(context, plan.startsOn, plan.endsOn)),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _TdpTimeline(plan: plan),
                ),
                if (plan.vision.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Inriktning', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(plan.vision),
                  ),
                ],
                if (plan.updatedBy != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Senast ändrad av ${plan.updatedBy}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _TdpSharingCard(controller: controller, plan: plan),
        const SizedBox(height: 16),
        if (plan.periods.isEmpty)
          const _TdpHint(
            icon: Icons.view_timeline_outlined,
            text:
                'Lägg till perioder, till exempel försäsong, tävling del 1, '
                'uppehåll och tävling del 2.',
          ),
        for (final period in plan.periods)
          _TdpPeriodCard(controller: controller, plan: plan, period: period),
      ];
    },
  );

  Future<void> _editSeason(BuildContext context, SeasonPlan plan) async {
    final draft = await _SeasonDialog.show(context, plan: plan);
    if (draft == null || !context.mounted) return;
    await controller.change(
      context,
      () => controller.services.savePlan(
        plan,
        title: draft.title,
        startsOn: draft.startsOn,
        endsOn: draft.endsOn,
        vision: draft.vision,
        checkinEveryDays: draft.checkinEveryDays,
      ),
      done: 'Säsongen är sparad.',
    );
  }
}

/// The season as a bar: each period in its phase's color, the gaps between
/// them empty, and a line where today is.
class _TdpTimeline extends StatelessWidget {
  const _TdpTimeline({required this.plan});
  final SeasonPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = plan.endsOn.difference(plan.startsOn).inDays + 1;
    final parts = <(int, DevelopmentPeriod?)>[];
    var cursor = plan.startsOn;
    for (final period in plan.periods) {
      final gap = period.startsOn.difference(cursor).inDays;
      if (gap > 0) parts.add((gap, null));
      parts.add((period.endsOn.difference(period.startsOn).inDays + 1, period));
      cursor = period.endsOn.add(const Duration(days: 1));
    }
    final rest = plan.endsOn.difference(cursor).inDays + 1;
    if (rest > 0) parts.add((rest, null));
    final today = DateUtils.dateOnly(DateTime.now());
    final todayAt = today.isBefore(plan.startsOn) || today.isAfter(plan.endsOn)
        ? null
        : (today.difference(plan.startsOn).inDays + 0.5) / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: 6,
                  bottom: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        for (final (days, period) in parts)
                          Expanded(
                            flex: days,
                            child: Tooltip(
                              message: period == null
                                  ? 'Ingen period'
                                  : '${period.name} · ${_tdpRange(context, period.startsOn, period.endsOn)}',
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                color: period == null
                                    ? colors.surfaceContainerHighest
                                    : _tdpPhaseColor(period.phase),
                                alignment: Alignment.center,
                                child: period == null
                                    ? null
                                    : Text(
                                        period.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (todayAt != null)
                  Positioned(
                    left: constraints.maxWidth * todayAt - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: colors.onSurface),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              _tdpDate(context, plan.startsOn),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            if (todayAt != null)
              Text('Idag', style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Text(
              _tdpDate(context, plan.endsOn),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _TdpPeriodCard extends StatelessWidget {
  const _TdpPeriodCard({
    required this.controller,
    required this.plan,
    required this.period,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final DevelopmentPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goals = plan.goalsOf(GoalHorizon.period, periodId: period.id);
    final achieved = goals.where((g) => g.state == GoalState.achieved).length;
    final now = period.contains(DateTime.now());
    return Card(
      key: ValueKey('tdp-period-${period.id}'),
      shape: now
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: controller.canEdit
            ? () => _TdpPeriodDialog.edit(
                context,
                controller,
                plan,
                period: period,
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _TdpPhaseChip(phase: period.phase),
                  if (now) ...[
                    const SizedBox(width: 8),
                    Text('Nu', style: theme.textTheme.labelMedium),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tdpRange(context, period.startsOn, period.endsOn),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(period.name, style: theme.textTheme.titleMedium),
              if (period.focus.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(period.focus),
              ],
              const SizedBox(height: 8),
              Text(
                goals.isEmpty
                    ? 'Inga mål'
                    : '$achieved av ${goals.length} mål uppnådda',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
