part of '../../app/teamzone_app.dart';

/// The plan for a stretch of days: the period's phase and name, the block
/// with its focus and principles. Nothing outside the periods.
class _TdpPlanNote extends StatelessWidget {
  const _TdpPlanNote({required this.plan, required this.day});
  final SeasonPlan plan;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = plan.periodOn(day);
    final block = plan.blockOn(day);
    if (period == null) {
      return Text(
        _tdpText(
          context,
          'Utanför säsongens perioder.',
          "Outside the season's periods.",
        ),
        style: theme.textTheme.bodySmall,
      );
    }
    final focus = (block?.focus.trim().isNotEmpty ?? false)
        ? block!.focus.trim()
        : period.focus.trim();
    final principles = block == null
        ? const <TeamPrinciple>[]
        : _tdpPrinciples(plan, block.principleIds);
    return Column(
      key: const Key('tdp-cal-plan'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TdpPhaseChip(phase: period.phase),
            Text(period.name, style: theme.textTheme.titleSmall),
            if (block != null)
              Text(
                '· ${block.name}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        if (focus.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(focus, style: theme.textTheme.bodyMedium),
        ],
        if (principles.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final principle in principles)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(principle.title),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A week: the plan for it on top, then the seven days side by side (one
/// under another on a narrow screen) with their activities. A tap on a day
/// opens it.
class _TdpWeekView extends StatelessWidget {
  const _TdpWeekView({
    required this.plan,
    required this.monday,
    required this.events,
    required this.onDay,
  });
  final SeasonPlan plan;
  final DateTime monday;
  final List<CalendarEventSummary> events;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final days = [for (var i = 0; i < 7; i++) _tdpShift(monday, i)];
    List<CalendarEventSummary> on(DateTime day) => [
      for (final event in events)
        if (DateUtils.isSameDay(_tdpDayOf(event), day)) event,
    ];
    Widget column(DateTime day) => _TdpWeekDay(
      day: day,
      today: today,
      events: on(day),
      onTap: () => onDay(day),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TdpPlanNote(plan: plan, day: _tdpShift(monday, 3)),
            const SizedBox(height: 12),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final day in days) Expanded(child: column(day)),
                      ],
                    )
                  : ListView(
                      children: [
                        for (final day in days)
                          SizedBox(height: 132, child: column(day)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TdpWeekDay extends StatelessWidget {
  const _TdpWeekDay({
    required this.day,
    required this.today,
    required this.events,
    required this.onTap,
  });
  final DateTime day, today;
  final List<CalendarEventSummary> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('tdp-cal-weekday-${day.year}-${day.month}-${day.day}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: DateUtils.isSameDay(day, today)
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.primary, width: 1.5),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_tdpWeekdays(context)[day.weekday - 1]} ${day.day}',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    children: [
                      for (final event in events)
                        _TdpActivityCard(event: event),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An activity in the week: its kind's color on the side, the time, the
/// title and the place.
class _TdpActivityCard extends StatelessWidget {
  const _TdpActivityCard({required this.event});
  final CalendarEventSummary event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _tdpActivityColor(context, event.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!event.allDay)
            Text(_tdpTimes(context, event), style: theme.textTheme.labelSmall),
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (event.locationName?.trim().isNotEmpty ?? false)
            Text(
              event.locationName!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}

/// A day: its activities, each opened on its own page to prepare or follow
/// it up, beside the plan for the day.
class _TdpDayView extends StatelessWidget {
  const _TdpDayView({
    required this.plan,
    required this.day,
    required this.events,
    required this.onOpen,
  });
  final SeasonPlan plan;
  final DateTime day;
  final List<CalendarEventSummary> events;
  final ValueChanged<CalendarEventSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final here = [
      for (final event in events)
        if (DateUtils.isSameDay(_tdpDayOf(event), day)) event,
    ];
    final list = here.isEmpty
        ? Text(
            _tdpText(
              context,
              'Inga aktiviteter den här dagen.',
              'No activities this day.',
            ),
            style: theme.textTheme.bodyMedium,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final event in here)
                Card(
                  key: Key('tdp-cal-activity-${event.id}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      _tdpActivityIcon(event.type),
                      color: _tdpActivityColor(context, event.type),
                    ),
                    title: Text(event.title),
                    subtitle: Text(
                      [
                        if (!event.allDay) _tdpTimes(context, event),
                        if (event.locationName?.trim().isNotEmpty ?? false)
                          event.locationName!.trim(),
                      ].join(' · '),
                    ),
                    trailing: FilledButton.tonal(
                      key: Key('tdp-cal-open-${event.id}'),
                      onPressed: () => onOpen(event),
                      child: Text(_tdpText(context, 'Öppna', 'Open')),
                    ),
                  ),
                ),
            ],
          );
    final note = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tdpText(context, 'Planen den här dagen', 'The plan this day'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _TdpPlanNote(plan: plan, day: day),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 860
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: SingleChildScrollView(child: list)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: note),
              ],
            )
          : ListView(children: [note, const SizedBox(height: 12), list]),
    );
  }
}
