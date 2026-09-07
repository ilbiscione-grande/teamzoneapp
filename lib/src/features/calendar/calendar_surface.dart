part of '../../app/teamzone_app.dart';

class _CalendarSurface extends StatefulWidget {
  const _CalendarSurface({
    required this.contextValue,
    required this.contexts,
    required this.calendar,
    required this.match,
    required this.onNavigate,
    required this.matchSpaceV2,
    this.initialAction,
  });

  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final CalendarServices calendar;
  final MatchServices match;
  final ValueChanged<String> onNavigate;
  final bool matchSpaceV2;
  // Set by the swipe-up quick actions sheet's "Skapa nytt event" shortcut
  // (ProductRouteContract.calendarCreateEvent) to open the create-event
  // dialog immediately on arrival — see _openInitialAction.
  final String? initialAction;

  @override
  State<_CalendarSurface> createState() => _CalendarSurfaceState();
}

class _CalendarWorkspace extends StatelessWidget {
  const _CalendarWorkspace({
    required this.events,
    required this.mode,
    required this.selectedDate,
    required this.stale,
    required this.reconnecting,
    required this.onModeChanged,
    required this.onDateChanged,
    required this.onTeamChanged,
    required this.onTypeChanged,
    required this.onEvent,
    required this.showWeekNumbers,
    required this.onShowWeekNumbersChanged,
    required this.showQuarterHourMarks,
    required this.onShowQuarterHourMarksChanged,
    required this.onDismissStale,
    this.teamFilter,
    this.eventTypeFilter,
    this.lastUpdated,
  });
  final List<CalendarEventSummary> events;
  final CalendarViewMode mode;
  final DateTime selectedDate;
  final String? teamFilter, eventTypeFilter;
  final bool stale, reconnecting, showWeekNumbers, showQuarterHourMarks;
  final DateTime? lastUpdated;
  final ValueChanged<CalendarViewMode> onModeChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String?> onTeamChanged, onTypeChanged;
  final ValueChanged<CalendarEventSummary> onEvent;
  final ValueChanged<bool> onShowWeekNumbersChanged,
      onShowQuarterHourMarksChanged;
  final VoidCallback onDismissStale;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final projection = CalendarProjection(
      events: events,
      mode: mode,
      selectedDate: selectedDate,
      teamId: teamFilter,
      eventType: eventTypeFilter,
    );
    final teams = <String, String>{
      for (final event in events) event.owningTeamId: event.teamName,
    };
    final types = events.map((event) => event.type).toSet().toList()..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stale)
                ListTile(
                  leading: Icon(reconnecting ? Icons.sync : Icons.cloud_off),
                  title: Text(
                    strings.feature(
                      reconnecting
                          ? 'Återansluter kalendern'
                          : 'Kalendern visar sparad data',
                    ),
                  ),
                  subtitle: lastUpdated == null
                      ? null
                      : Text(strings.lastUpdated(lastUpdated!)),
                  trailing: IconButton(
                    tooltip: strings.feature('Stäng'),
                    onPressed: onDismissStale,
                    icon: const Icon(Icons.close),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in CalendarViewMode.values)
                    ChoiceChip(
                      label: Text(
                        strings.feature(switch (value) {
                          CalendarViewMode.agenda => 'Agenda',
                          CalendarViewMode.month => 'Månad',
                          CalendarViewMode.week => 'Vecka',
                          CalendarViewMode.day => 'Dag',
                        }),
                      ),
                      selected: mode == value,
                      onSelected: (_) => onModeChanged(value),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _CalendarDateNavigation(
                mode: mode,
                selectedDate: selectedDate,
                onChanged: onDateChanged,
                showWeekNumber: showWeekNumbers,
                leading: IconButton(
                  tooltip: strings.feature('Filtrera kalendern'),
                  onPressed: () => _showCalendarFilterSheet(
                    context: context,
                    teams: teams,
                    types: types,
                    teamFilter: teamFilter,
                    eventTypeFilter: eventTypeFilter,
                    onTeamChanged: onTeamChanged,
                    onTypeChanged: onTypeChanged,
                    showWeekNumbers: showWeekNumbers,
                    onShowWeekNumbersChanged: onShowWeekNumbersChanged,
                    showQuarterHourMarks: showQuarterHourMarks,
                    onShowQuarterHourMarksChanged:
                        onShowQuarterHourMarksChanged,
                  ),
                  icon: Badge(
                    isLabelVisible:
                        teamFilter != null || eventTypeFilter != null,
                    smallSize: 8,
                    child: const Icon(Icons.filter_list),
                  ),
                ),
              ),
              const Divider(height: 1),
              if (mode == CalendarViewMode.month)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _CalendarMonthGrid(
                    projection: projection,
                    onDate: onDateChanged,
                  ),
                ),
            ],
          ),
        ),
        // The week grid gets its own half of the remaining space (instead
        // of sizing itself and leaving the rest to the day panel, like the
        // month grid does) so its 4x2 boxes can be large and full-width.
        if (mode == CalendarViewMode.week)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _CalendarWeekGrid(
                projection: projection,
                onDate: onDateChanged,
              ),
            ),
          ),
        Expanded(
          child: switch (mode) {
            CalendarViewMode.month ||
            CalendarViewMode.week => _CalendarSelectedDayPanel(
              projection: projection,
              onEvent: onEvent,
            ),
            // The day timeline always shows the full 24h grid, event or
            // not, so it never swaps for the "no events" state card.
            CalendarViewMode.day => _CalendarDayTimeline(
              date: projection.dayStart,
              events: projection.visibleEvents,
              onEvent: onEvent,
              showQuarterHours: showQuarterHourMarks,
            ),
            CalendarViewMode.agenda => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: projection.visibleEvents.isEmpty
                  ? _StateCard(
                      icon: Icons.event_busy,
                      title: strings.feature('Inga event i vald vy'),
                      message: strings.feature(
                        'Byt datum eller justera filtren.',
                      ),
                    )
                  : _CalendarAgenda(projection: projection, onEvent: onEvent),
            ),
          },
        ),
      ],
    );
  }
}

class _CalendarDateNavigation extends StatelessWidget {
  const _CalendarDateNavigation({
    required this.mode,
    required this.selectedDate,
    required this.onChanged,
    required this.showWeekNumber,
    this.leading,
  });
  final CalendarViewMode mode;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;
  final bool showWeekNumber;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final localizations = MaterialLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final start = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final weekStart = start.subtract(Duration(days: start.weekday - 1));
    final title = switch (mode) {
      CalendarViewMode.month =>
        compact
            ? _compactMonthYear(localizations.formatMonthYear(selectedDate))
            : localizations.formatMonthYear(selectedDate),
      CalendarViewMode.week =>
        '${localizations.formatMediumDate(weekStart)} – ${localizations.formatMediumDate(weekStart.add(const Duration(days: 6)))}',
      CalendarViewMode.agenda ||
      CalendarViewMode.day => localizations.formatFullDate(selectedDate),
    };
    DateTime move(int direction) => switch (mode) {
      CalendarViewMode.month => DateTime(
        selectedDate.year,
        selectedDate.month + direction,
        1,
      ),
      CalendarViewMode.week => selectedDate.add(Duration(days: 7 * direction)),
      CalendarViewMode.agenda ||
      CalendarViewMode.day => selectedDate.add(Duration(days: direction)),
    };
    return Row(
      children: [
        if (showWeekNumber)
          Tooltip(
            message: strings.feature('Veckonummer'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_isoWeekNumber(selectedDate)}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        IconButton(
          tooltip: AppStrings.of(context).feature('Föregående period'),
          onPressed: () => onChanged(move(-1)),
          icon: const Icon(Icons.chevron_left),
        ),
        ?leading,
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: AppStrings.of(context).feature('Idag'),
          onPressed: () => onChanged(DateTime.now()),
          icon: const Icon(Icons.today_outlined),
        ),
        IconButton(
          tooltip: AppStrings.of(context).feature('Nästa period'),
          onPressed: () => onChanged(move(1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// ISO-8601 week number (weeks start on Monday, week 1 contains the year's
/// first Thursday).
int _isoWeekNumber(DateTime date) {
  final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
  final firstDayOfYear = DateTime(thursday.year);
  return (thursday.difference(firstDayOfYear).inDays / 7).floor() + 1;
}

/// Shortens a localized "month year" string (e.g. "augusti 2026") to its
/// first three letters (e.g. "aug 2026") to save horizontal space on phones.
String _compactMonthYear(String monthYear) {
  final spaceIndex = monthYear.indexOf(' ');
  if (spaceIndex < 3) return monthYear;
  return '${monthYear.substring(0, 3)}${monthYear.substring(spaceIndex)}';
}

Future<void> _showCalendarFilterSheet({
  required BuildContext context,
  required Map<String, String> teams,
  required List<String> types,
  required String? teamFilter,
  required String? eventTypeFilter,
  required ValueChanged<String?> onTeamChanged,
  required ValueChanged<String?> onTypeChanged,
  required bool showWeekNumbers,
  required ValueChanged<bool> onShowWeekNumbersChanged,
  required bool showQuarterHourMarks,
  required ValueChanged<bool> onShowQuarterHourMarksChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      var localTeam = teamFilter;
      var localType = eventTypeFilter;
      var localShowWeekNumbers = showWeekNumbers;
      var localShowQuarterHourMarks = showQuarterHourMarks;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.of(sheetContext).feature('Filtrera kalendern'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: localTeam,
                decoration: InputDecoration(
                  labelText: AppStrings.of(sheetContext).feature('Lag'),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      AppStrings.of(sheetContext).feature('Alla lag'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final entry in teams.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  setSheetState(() => localTeam = value);
                  onTeamChanged(value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: localType,
                decoration: InputDecoration(
                  labelText: AppStrings.of(sheetContext).feature('Eventtyp'),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      AppStrings.of(sheetContext).feature('Alla eventtyper'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final type in types)
                    DropdownMenuItem(
                      value: type,
                      child: Text(
                        AppStrings.of(sheetContext).domainValue(type),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setSheetState(() => localType = value);
                  onTypeChanged(value);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  AppStrings.of(sheetContext).feature('Visa veckonummer'),
                ),
                value: localShowWeekNumbers,
                onChanged: (value) {
                  setSheetState(() => localShowWeekNumbers = value);
                  onShowWeekNumbersChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  AppStrings.of(sheetContext).feature('Visa kvartsmarkeringar'),
                ),
                subtitle: Text(
                  AppStrings.of(
                    sheetContext,
                  ).feature('Extra tunna linjer var 15:e minut i dagsvyn.'),
                ),
                value: localShowQuarterHourMarks,
                onChanged: (value) {
                  setSheetState(() => localShowQuarterHourMarks = value);
                  onShowQuarterHourMarksChanged(value);
                },
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(AppStrings.of(sheetContext).feature('Klar')),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CalendarAgenda extends StatelessWidget {
  const _CalendarAgenda({required this.projection, required this.onEvent});
  final CalendarProjection projection;
  final ValueChanged<CalendarEventSummary> onEvent;
  @override
  Widget build(BuildContext context) {
    final days = <DateTime>{
      for (final event in projection.visibleEvents)
        event.startsAt.toLocal().isBefore(projection.dayStart)
            ? projection.dayStart
            : DateTime(
                event.startsAt.toLocal().year,
                event.startsAt.toLocal().month,
                event.startsAt.toLocal().day,
              ),
    }.toList()..sort();
    return Column(
      children: [
        for (final day in days)
          _CalendarDay(
            date: day,
            events: projection.eventsOn(day),
            onEvent: onEvent,
          ),
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.events,
    required this.onEvent,
  });
  final DateTime date;
  final List<CalendarEventSummary> events;
  final ValueChanged<CalendarEventSummary> onEvent;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          MaterialLocalizations.of(context).formatFullDate(date),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      for (final event in events)
        _CalendarEventTile(event: event, onTap: () => onEvent(event)),
    ],
  );
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// A vertical 24-hour timeline for Dag mode: hour gridlines with labels,
/// thinner half-hour lines, an optional even thinner quarter-hour line, and
/// events rendered as positioned, readable cards (side-by-side when they
/// overlap) instead of a plain list.
class _CalendarDayTimeline extends StatelessWidget {
  const _CalendarDayTimeline({
    required this.date,
    required this.events,
    required this.onEvent,
    required this.showQuarterHours,
  });
  final DateTime date;
  final List<CalendarEventSummary> events;
  final ValueChanged<CalendarEventSummary> onEvent;
  final bool showQuarterHours;

  static const double _hourHeight = 64;
  static const double _labelWidth = 44;
  static const double _minCardHeight = 34;

  @override
  Widget build(BuildContext context) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final allDayEvents = events.where((event) => event.allDay).toList();
    final positioned = _layoutDayEvents(events, dayStart);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allDayEvents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                for (final event in allDayEvents)
                  _CalendarEventTile(event: event, onTap: () => onEvent(event)),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final eventsWidth = constraints.maxWidth - _labelWidth;
                return SizedBox(
                  height: _hourHeight * 24,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DayGridPainter(
                            hourHeight: _hourHeight,
                            labelWidth: _labelWidth,
                            showQuarterHours: showQuarterHours,
                            hourColor: colorScheme.outlineVariant,
                            halfColor: colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                            quarterColor: colorScheme.outlineVariant.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                      ),
                      for (var hour = 0; hour <= 23; hour++)
                        Positioned(
                          top: hour * _hourHeight - 7,
                          left: 0,
                          width: _labelWidth - 6,
                          child: Text(
                            '${hour.toString().padLeft(2, '0')}:00',
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      for (final item in positioned)
                        Positioned(
                          top: item.startMinutes / 60 * _hourHeight + 1,
                          left:
                              _labelWidth +
                              item.column * (eventsWidth / item.columnCount) +
                              2,
                          width: eventsWidth / item.columnCount - 4,
                          height: max(
                            (item.endMinutes - item.startMinutes) /
                                    60 *
                                    _hourHeight -
                                2,
                            _minCardHeight,
                          ),
                          child: _DayTimelineEventCard(
                            event: item.event,
                            onTap: () => onEvent(item.event),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DayGridPainter extends CustomPainter {
  const _DayGridPainter({
    required this.hourHeight,
    required this.labelWidth,
    required this.showQuarterHours,
    required this.hourColor,
    required this.halfColor,
    required this.quarterColor,
  });
  final double hourHeight, labelWidth;
  final bool showQuarterHours;
  final Color hourColor, halfColor, quarterColor;

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = hourColor
      ..strokeWidth = 1;
    final halfPaint = Paint()
      ..color = halfColor
      ..strokeWidth = 1;
    final quarterPaint = Paint()
      ..color = quarterColor
      ..strokeWidth = 1;
    for (var hour = 0; hour <= 24; hour++) {
      final y = hour * hourHeight;
      canvas.drawLine(Offset(labelWidth, y), Offset(size.width, y), hourPaint);
      if (hour == 24) break;
      canvas.drawLine(
        Offset(labelWidth, y + hourHeight / 2),
        Offset(size.width, y + hourHeight / 2),
        halfPaint,
      );
      if (showQuarterHours) {
        canvas.drawLine(
          Offset(labelWidth, y + hourHeight / 4),
          Offset(size.width, y + hourHeight / 4),
          quarterPaint,
        );
        canvas.drawLine(
          Offset(labelWidth, y + hourHeight * 3 / 4),
          Offset(size.width, y + hourHeight * 3 / 4),
          quarterPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DayGridPainter oldDelegate) =>
      oldDelegate.showQuarterHours != showQuarterHours ||
      oldDelegate.hourHeight != hourHeight ||
      oldDelegate.labelWidth != labelWidth ||
      oldDelegate.hourColor != hourColor;
}

/// One event card on the day timeline: type icon + title on the first line,
/// start–end time on the second, sized/positioned by the caller.
class _DayTimelineEventCard extends StatelessWidget {
  const _DayTimelineEventCard({required this.event, required this.onTap});
  final CalendarEventSummary event;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    final time =
        '${TimeOfDay.fromDateTime(start).format(context)}–${TimeOfDay.fromDateTime(end).format(context)}';
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: event.state == 'cancelled'
          ? colorScheme.surfaceContainerHighest
          : colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(_eventTypeIcon(event.type), size: 13),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _abbreviateHomeAwaySuffix(event.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                time,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One event clipped and positioned on a single day's timeline.
class _PositionedDayEvent {
  const _PositionedDayEvent({
    required this.event,
    required this.startMinutes,
    required this.endMinutes,
    required this.column,
    required this.columnCount,
  });
  final CalendarEventSummary event;
  final double startMinutes, endMinutes;
  final int column, columnCount;
}

/// Lays out a day's timed events into columns so overlapping events sit
/// side by side instead of on top of each other: events are clustered by
/// transitive time overlap, then greedily assigned the first column whose
/// previous occupant has already ended (standard interval-graph coloring).
List<_PositionedDayEvent> _layoutDayEvents(
  List<CalendarEventSummary> events,
  DateTime dayStart,
) {
  final dayEnd = dayStart.add(const Duration(days: 1));
  final spans = <(CalendarEventSummary, double, double)>[];
  for (final event in events) {
    if (event.allDay) continue;
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    final clippedStart = start.isBefore(dayStart) ? dayStart : start;
    final clippedEnd = end.isAfter(dayEnd) ? dayEnd : end;
    if (!clippedEnd.isAfter(clippedStart)) continue;
    final startMinutes = clippedStart.difference(dayStart).inMinutes.toDouble();
    final endMinutes = clippedEnd.difference(dayStart).inMinutes.toDouble();
    spans.add((event, startMinutes, endMinutes));
  }
  spans.sort((a, b) => a.$2.compareTo(b.$2));

  final result = <_PositionedDayEvent>[];
  var clusterIndices = <int>[];
  var clusterEnd = double.negativeInfinity;

  void flushCluster() {
    if (clusterIndices.isEmpty) return;
    final columnEnds = <double>[];
    final assigned = <int, int>{};
    for (final index in clusterIndices) {
      final (_, start, end) = spans[index];
      var placed = false;
      for (var column = 0; column < columnEnds.length; column++) {
        if (columnEnds[column] <= start) {
          columnEnds[column] = end;
          assigned[index] = column;
          placed = true;
          break;
        }
      }
      if (!placed) {
        columnEnds.add(end);
        assigned[index] = columnEnds.length - 1;
      }
    }
    final columnCount = columnEnds.length;
    for (final index in clusterIndices) {
      final (event, start, end) = spans[index];
      result.add(
        _PositionedDayEvent(
          event: event,
          startMinutes: start,
          endMinutes: end,
          column: assigned[index]!,
          columnCount: columnCount,
        ),
      );
    }
    clusterIndices = [];
  }

  for (var i = 0; i < spans.length; i++) {
    final (_, start, end) = spans[i];
    if (clusterIndices.isEmpty || start < clusterEnd) {
      clusterIndices.add(i);
      if (end > clusterEnd) clusterEnd = end;
    } else {
      flushCluster();
      clusterIndices.add(i);
      clusterEnd = end;
    }
  }
  flushCluster();
  return result;
}

/// One square day cell shared by the month and week grids: a day number, an
/// optional event-count badge, and a highlighted border when selected.
class _CalendarGridDayCell extends StatelessWidget {
  const _CalendarGridDayCell({
    required this.day,
    required this.items,
    required this.dimmed,
    required this.isSelected,
    required this.onTap,
    this.detailed = false,
  });
  final DateTime day;
  final List<CalendarEventSummary> items;
  final bool dimmed, isSelected;
  final VoidCallback onTap;
  // Compact grids (month) only have room for a day number and an
  // event-count badge; roomier grids (week) can show a couple of small
  // two-line event previews instead.
  final bool detailed;
  static const _maxDetailedEvents = 2;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Card(
        color: dimmed ? colorScheme.surfaceContainerLow : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSelected
              ? BorderSide(color: colorScheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: detailed ? _buildDetailed(context) : _buildCompact(context),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Padding(padding: const EdgeInsets.all(6), child: Text('${day.day}')),
        if (items.isNotEmpty)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                items.length > 9 ? '9+' : '${items.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  height: 1,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailed(BuildContext context) {
    final shown = items.take(_maxDetailedEvents).toList();
    final overflow = items.length - shown.length;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${day.day}'),
          for (final event in shown) ...[
            const SizedBox(height: 4),
            _CalendarGridEventChip(event: event),
          ],
          if (overflow > 0) ...[
            const SizedBox(height: 2),
            Text('+$overflow', style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

IconData _eventTypeIcon(String type) => switch (type) {
  'match' => Icons.sports_soccer,
  'training' => Icons.fitness_center,
  'meeting' => Icons.groups,
  'activity' => Icons.local_activity,
  _ => Icons.event,
};

/// A small two-line preview shown inside a roomy grid day cell: an icon for
/// the event type plus its time on the first line, and the title (or
/// opponent, for a match) on the second.
class _CalendarGridEventChip extends StatelessWidget {
  const _CalendarGridEventChip({required this.event});
  final CalendarEventSummary event;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final start = event.startsAt.toLocal();
    final time = event.allDay
        ? strings.feature('Heldag')
        : TimeOfDay.fromDateTime(start).format(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_eventTypeIcon(event.type), size: 11),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontSize: 9, height: 1),
                ),
              ),
            ],
          ),
          Text(
            _abbreviateHomeAwaySuffix(event.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 9,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shortens a title's trailing " Borta"/" Hemma" (a common free-text
/// match-title convention, not a structured field) to " (B)"/" (H)" so it
/// fits the narrow grid chip. Only a literal trailing word is matched, so
/// unrelated titles are left untouched.
String _abbreviateHomeAwaySuffix(String title) {
  if (title.endsWith(' Borta')) {
    return '${title.substring(0, title.length - 6)} (B)';
  }
  if (title.endsWith(' Hemma')) {
    return '${title.substring(0, title.length - 6)} (H)';
  }
  return title;
}

class _CalendarMonthGrid extends StatelessWidget {
  const _CalendarMonthGrid({required this.projection, required this.onDate});
  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;
  @override
  Widget build(BuildContext context) {
    final first = projection.rangeStart;
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final selected = projection.selectedDate;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.3,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final day = gridStart.add(Duration(days: index));
        return _CalendarGridDayCell(
          day: day,
          items: projection.eventsOn(day),
          dimmed: day.month != projection.selectedDate.month,
          isSelected: _isSameDay(day, selected),
          onTap: () => onDate(day),
        );
      },
    );
  }
}

/// The week grid shows the 7 days of the selected week plus one extra "peek"
/// box for next week's first day, so a leader can see what's coming up
/// without leaving the current week.
class _CalendarWeekGrid extends StatelessWidget {
  const _CalendarWeekGrid({required this.projection, required this.onDate});
  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;
  @override
  Widget build(BuildContext context) {
    final selected = projection.selectedDate;
    final weekStart = projection.weekStart;
    // Sized by the parent Expanded to roughly half the available height, so
    // the aspect ratio is derived from the actual constraints instead of a
    // fixed value: 4 columns x 2 rows should fill the full width and height
    // given, not just shrink-wrap to a fixed-size square.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 4;
        final cellHeight = constraints.maxHeight / 2;
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: cellHeight <= 0 ? 1 : cellWidth / cellHeight,
          ),
          itemCount: 8,
          itemBuilder: (context, index) {
            final day = weekStart.add(Duration(days: index));
            // The peek day sits outside this week's range, so its events
            // are looked up with a one-off day-scoped projection instead
            // of projection.eventsOn, which is bounded to the selected
            // week.
            final items = index < 7
                ? projection.eventsOn(day)
                : CalendarProjection(
                    events: projection.events,
                    mode: CalendarViewMode.day,
                    selectedDate: day,
                    teamId: projection.teamId,
                    eventType: projection.eventType,
                  ).eventsOn(day);
            return _CalendarGridDayCell(
              day: day,
              items: items,
              dimmed: index == 7,
              isSelected: _isSameDay(day, selected),
              onTap: () => onDate(day),
              detailed: true,
            );
          },
        );
      },
    );
  }
}

class _CalendarSelectedDayPanel extends StatelessWidget {
  const _CalendarSelectedDayPanel({
    required this.projection,
    required this.onEvent,
  });
  final CalendarProjection projection;
  final ValueChanged<CalendarEventSummary> onEvent;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final selected = projection.selectedDate;
    final dayEvents = projection.eventsOn(selected);
    return ListView(
      key: const Key('calendarSelectedDayPanel'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Text(
          MaterialLocalizations.of(context).formatFullDate(selected),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Divider(),
        if (dayEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(strings.feature('Inga event den här dagen.')),
          )
        else
          for (final event in dayEvents)
            _CalendarEventTile(event: event, onTap: () => onEvent(event)),
      ],
    );
  }
}

class _CalendarEventTile extends StatelessWidget {
  const _CalendarEventTile({required this.event, required this.onTap});
  final CalendarEventSummary event;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    final time = event.allDay
        ? strings.feature('Heldag')
        : '${TimeOfDay.fromDateTime(start).format(context)}–${TimeOfDay.fromDateTime(end).format(context)}';
    return ListTile(
      leading: Icon(
        event.state == 'cancelled' ? Icons.event_busy : Icons.event,
      ),
      title: Text(event.title),
      subtitle: Text(
        '$time · ${event.teamName} · ${strings.domainValue(event.type)}${event.locationName == null ? '' : ' · ${event.locationName}'}',
      ),
      trailing: Text(strings.domainValue(event.state)),
      onTap: onTap,
    );
  }
}

class _EventEditorValue {
  const _EventEditorValue({
    required this.title,
    required this.type,
    required this.state,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.timezone,
    required this.audiences,
    required this.recurring,
    required this.frequency,
    required this.interval,
    required this.count,
    required this.scope,
    this.description,
    this.locationName,
  });
  final String title, type, state, timezone, frequency, scope;
  final String? description, locationName;
  final DateTime startsAt, endsAt;
  final bool allDay, recurring;
  final List<String> audiences;
  final int interval, count;
}

class _EventEditorDialog extends StatefulWidget {
  const _EventEditorDialog({
    required this.teamName,
    required this.locationSuggestions,
    this.initial,
  });
  final String teamName;
  final List<String> locationSuggestions;
  final EventDetails? initial;
  @override
  State<_EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<_EventEditorDialog> {
  final _draft = AppFormController();
  late final TextEditingController _title = TextEditingController(
    text: widget.initial?.title,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.initial?.locationName,
  );
  late final TextEditingController _timezone = TextEditingController(
    text: widget.initial?.timezone ?? 'Europe/Stockholm',
  );
  late final TextEditingController _interval = TextEditingController(text: '1');
  late final TextEditingController _count = TextEditingController(text: '4');
  late String _type = widget.initial?.type ?? 'training';
  late String _state = widget.initial?.state ?? 'scheduled';
  late DateTime _startsAt =
      widget.initial?.startsAt.toLocal() ?? _defaultStart();
  late DateTime _endsAt =
      widget.initial?.endsAt.toLocal() ??
      _defaultStart().add(const Duration(hours: 2));
  late bool _allDay = widget.initial?.allDay ?? false;
  late final Set<String> _audiences = widget.initial == null
      ? {'players', 'leaders'}
      : widget.initial!.audiences
            .map((item) => item['type'])
            .whereType<String>()
            .toSet();
  bool _recurring = false;
  String _frequency = 'weekly', _scope = 'one';
  String? _error;

  static DateTime _defaultStart() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18);
  }

  @override
  void initState() {
    super.initState();
    if (_audiences.isEmpty) _audiences.addAll({'players', 'leaders'});
    for (final controller in [
      _title,
      _description,
      _location,
      _timezone,
      _interval,
      _count,
    ]) {
      controller.addListener(_draft.markDirty);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _description,
      _location,
      _timezone,
      _interval,
      _count,
    ]) {
      controller.removeListener(_draft.markDirty);
      controller.dispose();
    }
    _draft.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return null;
    if (_allDay) return DateTime(date.year, date.month, date.day);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _save() {
    final interval = int.tryParse(_interval.text);
    final count = int.tryParse(_count.text);
    if (_title.text.trim().isEmpty ||
        _title.text.trim().length > 160 ||
        _timezone.text.trim().isEmpty ||
        !_endsAt.isAfter(_startsAt) ||
        _audiences.isEmpty ||
        (_recurring &&
            (interval == null ||
                interval < 1 ||
                interval > 52 ||
                count == null ||
                count < 2 ||
                count > 104))) {
      setState(() {
        _error = AppStrings.of(
          context,
        ).feature('Kontrollera titel, tid, audience och serieinställningar.');
      });
      return;
    }
    _draft.markClean();
    Navigator.pop(
      context,
      _EventEditorValue(
        title: _title.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        type: _type,
        state: _state,
        startsAt: _startsAt,
        endsAt: _endsAt,
        allDay: _allDay,
        timezone: _timezone.text.trim(),
        audiences: _audiences.toList(growable: false),
        locationName: _location.text.trim().isEmpty
            ? null
            : _location.text.trim(),
        recurring: _recurring,
        frequency: _frequency,
        interval: interval ?? 1,
        count: count ?? 4,
        scope: _scope,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AppUnsavedChangesScope(
      controller: _draft,
      title: strings.feature('Kasta ändringar?'),
      message: strings.feature('Dina osparade ändringar går förlorade.'),
      discardLabel: strings.feature('Kasta'),
      cancelLabel: strings.feature('Fortsätt redigera'),
      child: AlertDialog(
        title: Text(
          strings.feature(
            widget.initial == null ? 'Skapa event' : 'Redigera event',
          ),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _title,
                  autofocus: widget.initial == null,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: strings.feature('Titel'),
                  ),
                ),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: strings.feature('Beskrivning'),
                  ),
                ),
                TextFormField(
                  initialValue: widget.teamName,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: strings.feature('Lag'),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: strings.feature('Typ'),
                        ),
                        items: [
                          for (final value in [
                            'training',
                            'match',
                            'meeting',
                            'activity',
                          ])
                            DropdownMenuItem(
                              value: value,
                              child: Text(strings.domainValue(value)),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _type = value ?? _type;
                          _draft.markDirty();
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _state,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: strings.statusLabel,
                        ),
                        items: [
                          for (final value
                              in widget.initial == null
                                  ? ['draft', 'scheduled']
                                  : [
                                      'draft',
                                      'scheduled',
                                      'cancelled',
                                      'completed',
                                    ])
                            DropdownMenuItem(
                              value: value,
                              child: Text(strings.domainValue(value)),
                            ),
                        ],
                        onChanged: widget.initial == null
                            ? (value) => setState(() {
                                _state = value ?? _state;
                                _draft.markDirty();
                              })
                            : null,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.feature('Heldag')),
                  value: _allDay,
                  onChanged: (value) => setState(() {
                    _allDay = value;
                    if (value) {
                      _startsAt = DateTime(
                        _startsAt.year,
                        _startsAt.month,
                        _startsAt.day,
                      );
                      _endsAt = DateTime(
                        _endsAt.year,
                        _endsAt.month,
                        _endsAt.day,
                      );
                      if (!_endsAt.isAfter(_startsAt)) {
                        _endsAt = _startsAt.add(const Duration(days: 1));
                      }
                    }
                    _draft.markDirty();
                  }),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.feature('Start')),
                  subtitle: Text(_formatDateTime(context, _startsAt, _allDay)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final value = await _pickDateTime(_startsAt);
                    if (value != null) {
                      setState(() {
                        final duration = _endsAt.difference(_startsAt);
                        _startsAt = value;
                        _endsAt = value.add(duration);
                        _draft.markDirty();
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.feature('Slut')),
                  subtitle: Text(_formatDateTime(context, _endsAt, _allDay)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final value = await _pickDateTime(_endsAt);
                    if (value != null) {
                      setState(() {
                        _endsAt = value;
                        _draft.markDirty();
                      });
                    }
                  },
                ),
                TextFormField(
                  controller: _timezone,
                  decoration: InputDecoration(
                    labelText: strings.feature('Tidszon'),
                  ),
                ),
                TextFormField(
                  controller: _location,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: strings.feature('Plats'),
                  ),
                ),
                if (widget.locationSuggestions.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final suggestion in widget.locationSuggestions.take(
                        8,
                      ))
                        ActionChip(
                          label: Text(suggestion),
                          onPressed: () {
                            _location.text = suggestion;
                            _location.selection = TextSelection.collapsed(
                              offset: suggestion.length,
                            );
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  strings.feature('Audience'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in [
                      'players',
                      'leaders',
                      'guardians',
                      'club',
                    ])
                      FilterChip(
                        label: Text(strings.domainValue(value)),
                        selected: _audiences.contains(value),
                        onSelected: (selected) => setState(() {
                          selected
                              ? _audiences.add(value)
                              : _audiences.remove(value);
                          _draft.markDirty();
                        }),
                      ),
                  ],
                ),
                if (widget.initial == null) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.feature('Återkommande serie')),
                    value: _recurring,
                    onChanged: (value) => setState(() {
                      _recurring = value;
                      _draft.markDirty();
                    }),
                  ),
                  if (_recurring)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _frequency,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: strings.feature('Intervalltyp'),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'daily',
                                child: Text(strings.feature('Dagligen')),
                              ),
                              DropdownMenuItem(
                                value: 'weekly',
                                child: Text(strings.feature('Veckovis')),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              _frequency = value ?? _frequency;
                              _draft.markDirty();
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _interval,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: strings.feature('Varje'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _count,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: strings.feature('Antal'),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
                if (widget.initial?.recurrenceId != null)
                  DropdownButtonFormField<String>(
                    initialValue: _scope,
                    decoration: InputDecoration(
                      labelText: strings.feature('Ändra'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'one',
                        child: Text(strings.feature('Bara detta')),
                      ),
                      DropdownMenuItem(
                        value: 'forward',
                        child: Text(strings.feature('Detta och framåt')),
                      ),
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(strings.feature('Hela serien')),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _scope = value ?? _scope;
                      _draft.markDirty();
                    }),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            onPressed: _save,
            child: Text(
              strings.feature(widget.initial == null ? 'Skapa' : 'Spara'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(BuildContext context, DateTime value, bool allDay) {
  final date = MaterialLocalizations.of(context).formatMediumDate(value);
  if (allDay) return date;
  return '$date · ${TimeOfDay.fromDateTime(value).format(context)}';
}


class _CalendarSurfaceState extends State<_CalendarSurface>
    with WidgetsBindingObserver {
  late final AsyncDataController<List<CalendarEventSummary>> _data;
  StreamSubscription<CalendarSyncEvent>? _invalidationSubscription;
  Timer? _invalidationDebounce;
  CalendarViewMode _viewMode = CalendarViewMode.agenda;
  DateTime _selectedDate = DateTime.now();
  String? _teamFilter, _eventTypeFilter;
  static const _showWeekNumbersKey = 'calendar.showWeekNumbers';
  static const _showQuarterHourMarksKey = 'calendar.showQuarterHourMarks';
  bool _showWeekNumbers = true;
  bool _showQuarterHourMarks = false;
  // The stale banner can be dismissed manually; it reappears on the next
  // genuinely new staleness episode (tracked via _wasStale) rather than
  // staying hidden forever once dismissed.
  bool _staleBannerDismissed = false;
  bool _wasStale = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = AsyncDataController<List<CalendarEventSummary>>(
      scopeKey: _scopeKey,
      loader: _reload,
      isEmpty: (events) => events.isEmpty,
    );
    _data.addListener(_trackStaleness);
    unawaited(_data.load());
    _listenForInvalidations();
    _openInitialAction();
    unawaited(_loadShowWeekNumbers());
    unawaited(_loadShowQuarterHourMarks());
  }

  void _trackStaleness() {
    final isStale = _data.state.isStale;
    if (isStale && !_wasStale) {
      _staleBannerDismissed = false;
    }
    _wasStale = isStale;
  }

  Future<void> _loadShowWeekNumbers() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getBool(_showWeekNumbersKey) ?? true;
    if (mounted) setState(() => _showWeekNumbers = value);
  }

  Future<void> _setShowWeekNumbers(bool value) async {
    setState(() => _showWeekNumbers = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_showWeekNumbersKey, value);
  }

  Future<void> _loadShowQuarterHourMarks() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getBool(_showQuarterHourMarksKey) ?? false;
    if (mounted) setState(() => _showQuarterHourMarks = value);
  }

  Future<void> _setShowQuarterHourMarks(bool value) async {
    setState(() => _showQuarterHourMarks = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_showQuarterHourMarksKey, value);
  }

  bool _openedInitialAction = false;

  /// Handles ?action=create from the swipe-up quick actions sheet
  /// (ProductRouteContract.calendarCreateEvent): opens the create-event
  /// dialog immediately, same dialog as the page's own FAB. Re-checks the
  /// same condition that gates that FAB rather than trusting the shortcut
  /// having been gated correctly, since this can be reached via a direct
  /// deep link.
  void _openInitialAction() {
    if (widget.initialAction != 'create' || _openedInitialAction) return;
    final canCreate =
        widget.contextValue.teamId != null &&
        widget.contextValue.can('event.manage');
    if (!canCreate) return;
    _openedInitialAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_createEvent());
    });
  }

  String get _scopeKey {
    final ids = widget.contexts.map((item) => item.id).toList()..sort();
    return '${widget.contextValue.id}:${ids.join(',')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invalidationDebounce?.cancel();
    unawaited(_invalidationSubscription?.cancel());
    _data.dispose();
    super.dispose();
  }

  void _listenForInvalidations() {
    unawaited(_invalidationSubscription?.cancel());
    _invalidationSubscription = widget.calendar
        .watchInvalidations(
          clubIds: widget.contexts.map((item) => item.clubId).toSet(),
        )
        .listen((event) {
          switch (event.status) {
            case CalendarSyncStatus.connected:
              _data.setConnection(
                AppConnectionStatus.online,
                resyncOnReconnect: true,
              );
              break;
            case CalendarSyncStatus.reconnecting:
              _data.setConnection(AppConnectionStatus.reconnecting);
              break;
            case CalendarSyncStatus.disconnected:
              _data.setConnection(AppConnectionStatus.offline);
              break;
          }
          if (event.invalidated) {
            _invalidationDebounce?.cancel();
            _invalidationDebounce = Timer(
              const Duration(milliseconds: 300),
              () => unawaited(_data.refresh()),
            );
          }
        });
  }

  @override
  void didUpdateWidget(covariant _CalendarSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextsChanged = !setEquals(
      oldWidget.contexts.map((item) => item.id).toSet(),
      widget.contexts.map((item) => item.id).toSet(),
    );
    if (oldWidget.contextValue.id != widget.contextValue.id ||
        contextsChanged) {
      _teamFilter = null;
      _data.replaceScope(scopeKey: _scopeKey, loader: _reload);
      _listenForInvalidations();
    }
    if (oldWidget.initialAction != widget.initialAction) {
      _openedInitialAction = false;
      _openInitialAction();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_data.refresh());
    }
  }

  Future<List<CalendarEventSummary>> _reload() {
    final now = DateTime.now();
    return widget.calendar.listCalendar(
      contextIds: widget.contexts.map((item) => item.id).toList(),
      from: DateTime(now.year, now.month - 1),
      to: DateTime(now.year, now.month + 11),
    );
  }

  Future<void> _refresh() async {
    final succeeded = await _data.refresh();
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(
              context,
            ).feature('Kalendern kunde inte uppdateras. Försök igen.'),
          ),
        ),
      );
    }
  }

  Future<void> _createEvent() async {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) return;
    List<String> suggestions;
    try {
      suggestions = await widget.calendar.listSavedLocations(
        clubId: widget.contextValue.clubId,
        teamId: teamId,
      );
    } catch (_) {
      suggestions = const [];
    }
    if (!mounted) return;
    final value = await showDialog<_EventEditorValue>(
      context: context,
      builder: (_) => _EventEditorDialog(
        teamName: widget.contextValue.teamName ?? '',
        locationSuggestions: suggestions,
      ),
    );
    if (value == null || !mounted) return;
    try {
      await widget.calendar.createEvent(
        CreateEventInput(
          clubId: widget.contextValue.clubId,
          teamId: teamId,
          title: value.title,
          description: value.description,
          type: value.type,
          state: value.state,
          startsAt: value.startsAt,
          endsAt: value.endsAt,
          allDay: value.allDay,
          timezone: value.timezone,
          audiences: value.audiences,
          locationName: value.locationName,
          recurrenceFrequency: value.recurring ? value.frequency : null,
          recurrenceInterval: value.recurring ? value.interval : null,
          recurrenceCount: value.recurring ? value.count : null,
        ),
        _newUuid(),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Eventet kunde inte skapas. Försök igen.'),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) unawaited(_data.refresh());
  }

  void _showDetails(CalendarEventSummary summary) {
    widget.onNavigate(ProductRouteContract.calendarEvent(summary.id));
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        widget.contextValue.teamId != null &&
        widget.contextValue.can('event.manage');
    return Scaffold(
      floatingActionButtonLocation:
          MediaQuery.sizeOf(context).width < AppBreakpoints.desktop
          ? _aboveAssistantFabLocation
          : null,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListenableBuilder(
          listenable: _data,
          builder: (context, _) {
            final state = _data.state;
            if (state.phase == AsyncDataPhase.loading) {
              return AppLoadingIndicator(label: AppStrings.of(context).loading);
            }
            if (state.phase == AsyncDataPhase.failed) {
              return ListView(
                children: [
                  _StateCard(
                    icon: Icons.cloud_off,
                    title: AppStrings.of(
                      context,
                    ).feature('Kalendern kunde inte synkroniseras'),
                    message: AppStrings.of(context).feature(
                      'Kontrollera anslutningen och försök igen. Ingen gammal data visas som aktuell.',
                    ),
                    action: FilledButton(
                      onPressed: _data.load,
                      child: Text(
                        AppStrings.of(context).feature('Försök igen'),
                      ),
                    ),
                  ),
                ],
              );
            }
            final events = state.data ?? const [];
            return _CalendarWorkspace(
              events: events,
              mode: _viewMode,
              selectedDate: _selectedDate,
              teamFilter: _teamFilter,
              eventTypeFilter: _eventTypeFilter,
              stale: state.isStale && !_staleBannerDismissed,
              reconnecting:
                  state.connection == AppConnectionStatus.reconnecting,
              lastUpdated: state.lastUpdated,
              onDismissStale: () =>
                  setState(() => _staleBannerDismissed = true),
              onModeChanged: (value) => setState(() => _viewMode = value),
              onDateChanged: (value) => setState(() => _selectedDate = value),
              onTeamChanged: (value) => setState(() => _teamFilter = value),
              onTypeChanged: (value) =>
                  setState(() => _eventTypeFilter = value),
              onEvent: _showDetails,
              showWeekNumbers: _showWeekNumbers,
              onShowWeekNumbersChanged: _setShowWeekNumbers,
              showQuarterHourMarks: _showQuarterHourMarks,
              onShowQuarterHourMarksChanged: _setShowQuarterHourMarks,
            );
          },
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: _createEvent,
              tooltip: AppStrings.of(context).feature('Nytt event'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
