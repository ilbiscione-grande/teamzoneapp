part of '../../app/teamzone_app.dart';

/// The strong and soft color of an event type, the same in every view:
/// green for training, red for match and blue for anything else.
({Color strong, Color soft}) _calendarTypeColors(
  BuildContext context,
  String type,
) {
  final palette = AppPalette.of(context);
  final other = _calendarOtherEventColor(context);
  return switch (type) {
    'match' => (strong: palette.danger, soft: palette.dangerSoft),
    'training' => (strong: palette.accent, soft: palette.accentSoft),
    _ => (
      strong: other,
      soft: Color.alphaBlend(
        other.withValues(alpha: .16),
        Theme.of(context).colorScheme.surface,
      ),
    ),
  };
}

/// The Day view: a 24-hour timeline that opens at the current or next
/// activity, a red line at the current time on today, and a soft card over
/// the empty timeline on a day without events.
class _CalendarDayTimeline extends StatefulWidget {
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

  @override
  State<_CalendarDayTimeline> createState() => _CalendarDayTimelineState();
}

class _CalendarDayTimelineState extends State<_CalendarDayTimeline> {
  static const double _hourHeight = 64;
  static const double _labelWidth = 48;
  static const double _minCardHeight = 34;

  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _anchorOffset(),
  );
  // Moves the current-time line along while the day is open.
  late final Timer _clock;

  /// An hour of context above the activity the timeline opens at.
  double _anchorOffset() {
    final anchor = calendarDayScrollAnchor(
      widget.events,
      widget.date,
      DateTime.now(),
    );
    final day = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final minutes = anchor.difference(day).inMinutes;
    return max(0, (minutes / 60 - 1) * _hourHeight);
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _CalendarDayTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDay(oldWidget.date, widget.date) && _scroll.hasClients) {
      _scroll.jumpTo(min(_anchorOffset(), _scroll.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _clock.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    final events = widget.events;
    final onEvent = widget.onEvent;
    final dayStart = DateTime(date.year, date.month, date.day);
    final allDayEvents = events.where((event) => event.allDay).toList();
    final positioned = _layoutDayEvents(events, dayStart);
    final colorScheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final now = DateTime.now();
    final nowMinutes = _isSameDay(now, dayStart)
        ? now.difference(dayStart).inMinutes
        : null;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: palette.muted);
    final timeline = SingleChildScrollView(
      key: const Key('calendarDayTimelineScroll'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final eventsWidth = constraints.maxWidth - _labelWidth;
          return SizedBox(
            height: _hourHeight * 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DayGridPainter(
                      hourHeight: _hourHeight,
                      labelWidth: _labelWidth,
                      showQuarterHours: widget.showQuarterHours,
                      hourColor: colorScheme.outlineVariant.withValues(
                        alpha: .7,
                      ),
                      halfColor: colorScheme.outlineVariant.withValues(
                        alpha: .3,
                      ),
                      quarterColor: colorScheme.outlineVariant.withValues(
                        alpha: .15,
                      ),
                    ),
                  ),
                ),
                for (var hour = 0; hour <= 23; hour++)
                  // The current time takes the place of an hour it is close to.
                  if (nowMinutes == null || (nowMinutes - hour * 60).abs() > 12)
                    Positioned(
                      top: hour * _hourHeight - 7,
                      left: 0,
                      width: _labelWidth - 8,
                      child: Text(
                        '${hour.toString().padLeft(2, '0')}:00',
                        textAlign: TextAlign.right,
                        style: labelStyle,
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
                    height: item.cardHeight(_hourHeight, _minCardHeight),
                    child: _DayTimelineEventCard(
                      event: item.event,
                      height: item.cardHeight(_hourHeight, _minCardHeight),
                      onTap: () => onEvent(item.event),
                    ),
                  ),
                if (nowMinutes != null)
                  _DayNowLine(
                    top: nowMinutes / 60 * _hourHeight,
                    labelWidth: _labelWidth,
                    label: TimeOfDay.fromDateTime(now).format(context),
                  ),
              ],
            ),
          );
        },
      ),
    );
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
          child: events.isEmpty
              ? Stack(
                  children: [
                    timeline,
                    Center(child: _DayEmptyCard(today: nowMinutes != null)),
                  ],
                )
              : timeline,
        ),
      ],
    );
  }
}

/// The current time across the timeline: the time in red in the label
/// column, a dot and a thin red line.
class _DayNowLine extends StatelessWidget {
  const _DayNowLine({
    required this.top,
    required this.labelWidth,
    required this.label,
  });
  final double top, labelWidth;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = AppPalette.of(context).danger;
    return Positioned(
      key: const Key('calendarDayNowLine'),
      top: top - 8,
      left: 0,
      right: 0,
      height: 16,
      child: IgnorePointer(
        child: Row(
          children: [
            SizedBox(
              width: labelWidth - 8,
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(child: Container(height: 1.5, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Shown over the empty timeline of a day without events.
class _DayEmptyCard extends StatelessWidget {
  const _DayEmptyCard({required this.today});
  final bool today;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return IgnorePointer(
      child: Container(
        key: const Key('calendarDayEmpty'),
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            palette.accentSoft.withValues(alpha: .5),
            theme.colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 36,
              color: palette.muted,
            ),
            const SizedBox(height: 10),
            Text(
              today
                  ? strings.feature('Inga aktiviteter idag')
                  : strings.feature('Inga aktiviteter'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.feature('Din kalender är tom den här dagen.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
        ),
      ),
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

/// One event card on the day timeline, in its type's soft color with a
/// strong bar on the left: the icon beside time, title, team and place.
/// Shorter cards fold team and place into one line, and the shortest put
/// the time on that line too.
class _DayTimelineEventCard extends StatelessWidget {
  const _DayTimelineEventCard({
    required this.event,
    required this.height,
    required this.onTap,
  });
  final CalendarEventSummary event;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    final time = _eventTimeRange(context, start, end);
    final cancelled = event.state == 'cancelled';
    final colors = _calendarTypeColors(context, event.type);
    final strong = cancelled ? palette.muted : colors.strong;
    final soft = cancelled
        ? theme.colorScheme.surfaceContainerHighest
        : colors.soft;
    final place = event.locationName?.trim() ?? '';
    final small = theme.textTheme.labelSmall?.copyWith(color: palette.muted);
    final tall = height >= 88;
    final roomy = height >= 58;
    Text line(String text, {Key? key, TextStyle? style}) => Text(
      text,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ?? small,
    );
    final title = Row(
      children: [
        if (event.isShared) ...[
          _sharedEventMarker(context, 13),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: line(
            _abbreviateHomeAwaySuffix(event.title),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              decoration: cancelled ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: cancelled ? 0.68 : 1,
      child: Material(
        color: soft,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: strong, width: 4)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  cancelled ? Icons.event_busy : _homeEventIcon(event.type),
                  size: 18,
                  color: strong,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (roomy)
                          line(
                            time,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        title,
                        if (tall) ...[
                          line(
                            event.teamName,
                            key: ValueKey('day-event-team-${event.id}'),
                          ),
                          if (place.isNotEmpty)
                            line(
                              place,
                              key: ValueKey('day-event-place-${event.id}'),
                            ),
                        ] else if (roomy)
                          line(
                            _eventTeamAndPlace(event),
                            key: ValueKey('day-event-where-${event.id}'),
                          )
                        else
                          line('$time · ${_eventTeamAndPlace(event)}'),
                      ],
                    ),
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

/// "Team · place" for calendar previews; the place is left out when unset.
String _eventTeamAndPlace(CalendarEventSummary event) {
  final place = event.locationName?.trim();
  return place == null || place.isEmpty
      ? event.teamName
      : '${event.teamName} · $place';
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

  double cardHeight(double hourHeight, double minHeight) =>
      max((endMinutes - startMinutes) / 60 * hourHeight - 2, minHeight);
}

/// Lays out a day's timed events into columns so overlapping events sit
/// side by side instead of on top of each other: events are clustered by
/// transitive time overlap, then greedily assigned the first column whose
/// previous occupant has already ended (standard interval-graph coloring).
List<_PositionedDayEvent> _layoutDayEvents(
  List<CalendarEventSummary> events,
  DateTime dayStart,
) {
  final dayEnd = calendarAddDays(dayStart, 1);
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
