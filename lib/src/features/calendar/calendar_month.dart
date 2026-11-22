part of '../../app/teamzone_app.dart';

/// The Month view on a phone: the month grid on top, the selected day's
/// events under it and the events after that day last, all in one scroll.
class _CalendarMonthView extends StatelessWidget {
  const _CalendarMonthView({
    required this.projection,
    required this.onDate,
    required this.onEvent,
    required this.showWeekNumbers,
  });

  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<CalendarEventSummary> onEvent;
  final bool showWeekNumbers;

  @override
  Widget build(BuildContext context) {
    final day = projection.dayStart;
    final upcoming = CalendarProjection(
      events: projection.events,
      mode: CalendarViewMode.agenda,
      selectedDate: calendarAddDays(day, 1),
      teamId: projection.teamId,
      eventType: projection.eventType,
    ).visibleEvents;
    return ListView(
      key: const Key('calendarMonthView'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _CalendarMonthGrid(
          projection: projection,
          onDate: onDate,
          showWeekNumbers: showWeekNumbers,
        ),
        const Divider(height: 24),
        _CalendarDayAndUpcoming(
          day: day,
          dayEvents: projection.eventsOn(day),
          upcoming: upcoming,
          onEvent: onEvent,
        ),
      ],
    );
  }
}

/// Width of the week-number column left of the month grid.
const double _calendarWeekNumberWidth = 28;

/// The ISO week number in front of a row of the month grid.
class _CalendarMonthWeekNumber extends StatelessWidget {
  const _CalendarMonthWeekNumber({required this.weekStart});
  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final week = calendarIsoWeek(weekStart);
    return SizedBox(
      width: _calendarWeekNumberWidth,
      child: Tooltip(
        message: '${AppStrings.of(context).feature('Vecka')} $week',
        child: Text(
          '$week',
          key: ValueKey(
            'calendarMonthWeek-${weekStart.year}-${weekStart.month}-${weekStart.day}',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppPalette.of(context).muted),
        ),
      ),
    );
  }
}

/// Mån–Sön over the month grid.
class _CalendarWeekdayHeader extends StatelessWidget {
  const _CalendarWeekdayHeader({
    required this.weekStart,
    this.showWeekNumbers = false,
  });
  final DateTime weekStart;
  final bool showWeekNumbers;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: AppPalette.of(context).muted,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (showWeekNumbers) const SizedBox(width: _calendarWeekNumberWidth),
          for (var offset = 0; offset < 7; offset++)
            Expanded(
              child: Text(
                _capitalized(
                  _homeShortWeekday(
                    material,
                    calendarAddDays(weekStart, offset),
                  ).toLowerCase(),
                ),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

/// Blue for event types other than training and match; the palette has no
/// blue of its own.
Color _calendarOtherEventColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF60A5FA)
    : const Color(0xFF2563EB);

/// One day in the month grid: the number, a filled pill when selected,
/// today in the accent color, and up to three dots colored by event type
/// (green training, red match, blue other).
class _CalendarMonthDayCell extends StatelessWidget {
  const _CalendarMonthDayCell({
    required this.day,
    required this.events,
    required this.dimmed,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final List<CalendarEventSummary> events;
  final bool dimmed, isSelected;
  final VoidCallback onTap;
  static const _maxDots = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final isToday = _isSameDay(day, DateTime.now());
    final foreground = isSelected
        ? theme.colorScheme.onPrimary
        : dimmed
        ? palette.muted.withValues(alpha: .5)
        : isToday
        ? palette.accent
        : theme.colorScheme.onSurface;
    Color dot(CalendarEventSummary event) => isSelected
        ? foreground
        : _calendarTypeColors(context, event.type).strong;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: Semantics(
        selected: isSelected,
        button: true,
        label: MaterialLocalizations.of(context).formatFullDate(day),
        excludeSemantics: true,
        child: Material(
          key: ValueKey('calendarMonthDay-${day.year}-${day.month}-${day.day}'),
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: isSelected || isToday
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final event in events.take(_maxDots))
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dot(event),
                          ),
                        ),
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
