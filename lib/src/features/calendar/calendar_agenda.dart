part of '../../app/teamzone_app.dart';

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// The Agenda view: a row with the selected week's days on top, the
/// selected day's events under it and every later event after that.
class _CalendarAgendaView extends StatelessWidget {
  const _CalendarAgendaView({
    required this.projection,
    required this.onDate,
    required this.onEvent,
  });

  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<CalendarEventSummary> onEvent;

  @override
  Widget build(BuildContext context) {
    final day = projection.dayStart;
    final dayEvents = projection.eventsOn(day);
    final shown = {for (final event in dayEvents) event.id};
    final upcoming = projection.visibleEvents
        .where((event) => !shown.contains(event.id))
        .toList(growable: false);
    return ListView(
      key: const Key('calendarAgendaView'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _CalendarWeekStrip(projection: projection, onDate: onDate),
        const SizedBox(height: 20),
        _CalendarDayAndUpcoming(
          day: day,
          dayEvents: dayEvents,
          upcoming: upcoming,
          onEvent: onEvent,
        ),
      ],
    );
  }
}

/// The selected day's title and event cards, then the later events: shared
/// by the agenda and the month view.
class _CalendarDayAndUpcoming extends StatelessWidget {
  const _CalendarDayAndUpcoming({
    required this.day,
    required this.dayEvents,
    required this.upcoming,
    required this.onEvent,
  });

  final DateTime day;
  final List<CalendarEventSummary> dayEvents;
  final List<CalendarEventSummary> upcoming;
  final ValueChanged<CalendarEventSummary> onEvent;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _capitalized(MaterialLocalizations.of(context).formatFullDate(day)),
          key: const Key('calendarAgendaDayTitle'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (dayEvents.isEmpty)
          const _CalendarAgendaEmptyDay()
        else
          for (final event in dayEvents)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CalendarAgendaRow(
                event: event,
                onTap: () => onEvent(event),
              ),
            ),
        const SizedBox(height: 14),
        _HomeEventList(
          title: strings.upcomingEvents,
          children: [
            if (upcoming.isEmpty)
              Text(
                strings.feature('Inga kommande event'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppPalette.of(context).muted,
                ),
              ),
            for (final event in upcoming)
              _CalendarAgendaRow(event: event, onTap: () => onEvent(event)),
          ],
        ),
      ],
    );
  }
}

/// Seven day buttons, Monday to Sunday: the selected day on a filled accent
/// pill, today in the accent color and a dot under days with events (red
/// when one of them is a match).
class _CalendarWeekStrip extends StatelessWidget {
  const _CalendarWeekStrip({required this.projection, required this.onDate});
  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final material = MaterialLocalizations.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = projection.dayStart;
    return Row(
      key: const Key('calendarWeekStrip'),
      children: [
        for (var offset = 0; offset < 7; offset++)
          Expanded(
            child: Builder(
              builder: (context) {
                final day = calendarAddDays(projection.weekStart, offset);
                final isSelected = _isSameDay(day, selected);
                final isToday = _isSameDay(day, today);
                final events = projection.eventsOn(day);
                final foreground = isSelected
                    ? theme.colorScheme.onPrimary
                    : isToday
                    ? palette.accent
                    : theme.colorScheme.onSurface;
                final weekday = _homeShortWeekday(material, day);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Semantics(
                    selected: isSelected,
                    button: true,
                    label: material.formatFullDate(day),
                    excludeSemantics: true,
                    child: Material(
                      key: ValueKey('calendarWeekStripDay-$offset'),
                      color: isSelected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.tile),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.tile),
                        onTap: () => onDate(day),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(
                                _capitalized(weekday.toLowerCase()),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: isSelected
                                      ? foreground
                                      : isToday
                                      ? palette.accent
                                      : palette.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${day.day}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: foreground,
                                  fontWeight: isSelected || isToday
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: events.isEmpty
                                      ? Colors.transparent
                                      : isSelected
                                      ? foreground
                                      : events.any(
                                          (event) => event.type == 'match',
                                        )
                                      ? palette.danger
                                      : palette.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The selected day without events: a soft card with a calendar icon.
class _CalendarAgendaEmptyDay extends StatelessWidget {
  const _CalendarAgendaEmptyDay();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: palette.accentSoft.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Icon(Icons.event_available_outlined, size: 32, color: palette.muted),
          const SizedBox(height: 8),
          Text(
            strings.feature('Inga aktiviteter denna dag.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// One event card in the agenda: the date tile, the type's icon, title,
/// time and place, and the team; cancelled events are struck through.
class _CalendarAgendaRow extends StatelessWidget {
  const _CalendarAgendaRow({required this.event, required this.onTap});
  final CalendarEventSummary event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    final match = event.type == 'match';
    final cancelled = event.state == 'cancelled';
    final time = event.allDay
        ? strings.feature('Heldag')
        : _eventTimeRange(context, start, end);
    final details = [
      time,
      if (event.locationName?.trim().isNotEmpty ?? false) event.locationName!,
    ].join(' · ');
    return Opacity(
      opacity: cancelled ? .68 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _HomeDateTile(day: DateUtils.dateOnly(start), match: match),
                const SizedBox(width: 12),
                Icon(
                  cancelled ? Icons.event_busy : _homeEventIcon(event.type),
                  color: match ? palette.danger : palette.accent,
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
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: cancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.muted,
                        ),
                      ),
                      Text(
                        event.teamName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (event.isShared) ...[
                  const SizedBox(width: 6),
                  _sharedEventMarker(context, 18),
                ],
                if (cancelled)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      strings.domainValue(event.state),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (event.state == 'draft') ...[
                  const SizedBox(width: 6),
                  _draftEventMarker(context, 18),
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
