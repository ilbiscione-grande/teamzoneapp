part of '../../app/teamzone_app.dart';

/// The activities in the block now (or the period without blocks), as a
/// list (2026-11-02): those ahead first, then those done, the latest first.
/// A row shows the day and time, the kind, the title and the place, and a
/// match's result; a tap opens the day in the year calendar.
class _TdpBlockActivities extends StatefulWidget {
  const _TdpBlockActivities({
    required this.controller,
    required this.plan,
    required this.from,
    required this.to,
    required this.title,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final DateTime from, to;
  final String title;

  @override
  State<_TdpBlockActivities> createState() => _TdpBlockActivitiesState();
}

class _TdpBlockActivitiesState extends State<_TdpBlockActivities> {
  /// Those done beyond the latest few show on request.
  static const _doneShown = 5;
  bool _allDone = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Card(
      key: const Key('tdp-block-activities'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: FutureBuilder<List<CalendarEventSummary>>(
          future: widget.controller.activities(
            widget.plan.startsOn,
            widget.plan.endsOn,
          ),
          builder: (context, snapshot) {
            final events = [
              for (final event in snapshot.data ?? const [])
                if (!_tdpDayOf(event).isBefore(widget.from) &&
                    !_tdpDayOf(event).isAfter(widget.to))
                  event,
            ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
            final ahead = [
              for (final event in events)
                if (!event.endsAt.isBefore(now)) event,
            ];
            final done = [
              for (final event in events.reversed)
                if (event.endsAt.isBefore(now)) event,
            ];
            final shownDone = _allDone ? done : done.take(_doneShown).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title, style: theme.textTheme.titleMedium),
                Text(
                  snapshot.hasError
                      ? _tdpText(
                          context,
                          'Aktiviteterna kunde inte hämtas.',
                          'The activities could not be loaded.',
                        )
                      : snapshot.data == null
                      ? ''
                      : _tdpText(
                          context,
                          '${done.length} av ${events.length} genomförda · ${_tdpRange(context, widget.from, widget.to)}',
                          '${done.length} of ${events.length} done · ${_tdpRange(context, widget.from, widget.to)}',
                        ),
                  style: theme.textTheme.bodySmall,
                ),
                if (snapshot.data != null && events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _tdpText(
                        context,
                        'Inga aktiviteter i kalendern under den här tiden.',
                        'No activities in the calendar during this time.',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (ahead.isNotEmpty) ...[
                  _heading(
                    context,
                    _tdpText(context, 'Kommande', 'Coming up'),
                    ahead.length,
                  ),
                  for (final event in ahead) _row(context, event, done: false),
                ],
                if (done.isNotEmpty) ...[
                  _heading(
                    context,
                    _tdpText(context, 'Genomförda', 'Done'),
                    done.length,
                  ),
                  for (final event in shownDone)
                    _row(context, event, done: true),
                  if (done.length > _doneShown)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('tdp-block-activities-more'),
                        onPressed: () => setState(() => _allDone = !_allDone),
                        child: Text(
                          _allDone
                              ? _tdpText(context, 'Visa färre', 'Show fewer')
                              : _tdpText(
                                  context,
                                  'Visa alla ${done.length}',
                                  'Show all ${done.length}',
                                ),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text, int count) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        '$text ($count)',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    CalendarEventSummary event, {
    required bool done,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final day = _tdpDayOf(event);
    final color = _tdpActivityColor(context, event.type);
    final cancelled = event.state == 'cancelled';
    final result = event.type == 'match' && event.scoreUs != null
        ? '${event.scoreUs}–${event.scoreOpponent ?? 0}'
        : null;
    final muted = done || cancelled;
    return Column(
      children: [
        const Divider(height: 1),
        InkWell(
          key: Key('tdp-block-activity-${event.id}'),
          onTap: () => _TdpCalendar.open(
            context,
            controller: widget.controller,
            plan: widget.plan,
            day: event.startsAt.toLocal(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_tdpWeekdays(context)[day.weekday - 1]} ${_tdpDate(context, day)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: muted ? colors.onSurfaceVariant : null,
                        ),
                      ),
                      Text(
                        event.allDay
                            ? _tdpText(context, 'Heldag', 'All day')
                            : _tdpTime(context, event.startsAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withValues(alpha: muted ? 0.08 : 0.15),
                  child: Icon(
                    done && !cancelled
                        ? Icons.check
                        : _tdpActivityIcon(event.type),
                    size: 16,
                    color: muted ? colors.onSurfaceVariant : color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: cancelled
                              ? TextDecoration.lineThrough
                              : null,
                          color: muted ? colors.onSurfaceVariant : null,
                        ),
                      ),
                      if (event.locationName?.trim().isNotEmpty ?? false)
                        Text(
                          event.locationName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (cancelled)
                  Text(
                    _tdpText(context, 'Inställd', 'Cancelled'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.error,
                    ),
                  )
                else if (result != null)
                  Text(
                    result,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
