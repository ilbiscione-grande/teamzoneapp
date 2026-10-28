part of '../../app/teamzone_app.dart';

/// The Week view: the week's days on top with the selected day wider on a
/// soft accent column, all-day events under them, and a time grid with each
/// timed event in its day's column. The selected day's cards get the room
/// for time, title and team; the narrow days show the start and title.
class _CalendarWeekView extends StatefulWidget {
  const _CalendarWeekView({
    required this.projection,
    required this.onDate,
    required this.onEvent,
  });

  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<CalendarEventSummary> onEvent;

  @override
  State<_CalendarWeekView> createState() => _CalendarWeekViewState();
}

class _CalendarWeekViewState extends State<_CalendarWeekView> {
  static const double _hourHeight = 44;
  static const double _labelWidth = 38;
  static const double _gutter = 6;
  // The selected day's share of the width against 1 for every other day.
  static const double _selectedShare = 1.9;
  static const double _minBlockHeight = 26;
  static const double _overlapStep = 6;

  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _anchorOffset(),
  );

  /// An hour above the week's earliest timed event, or 07:00.
  double _anchorOffset() {
    final projection = widget.projection;
    var earliest = 8 * 60;
    for (var offset = 0; offset < 7; offset++) {
      final day = calendarAddDays(projection.weekStart, offset);
      for (final event in projection.eventsOn(day)) {
        if (event.allDay) continue;
        final start = event.startsAt.toLocal();
        final minutes = start.isBefore(day)
            ? 0
            : start.difference(day).inMinutes;
        earliest = min(earliest, minutes);
      }
    }
    return max(0, (earliest / 60 - 1) * _hourHeight);
  }

  @override
  void didUpdateWidget(covariant _CalendarWeekView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDay(
          oldWidget.projection.weekStart,
          widget.projection.weekStart,
        ) &&
        _scroll.hasClients) {
      _scroll.jumpTo(min(_anchorOffset(), _scroll.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projection = widget.projection;
    final palette = AppPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final days = [
      for (var offset = 0; offset < 7; offset++)
        calendarAddDays(projection.weekStart, offset),
    ];
    final selected = projection.dayStart;
    final allDay = [
      for (final day in days)
        projection.eventsOn(day).where((event) => event.allDay).toList(),
    ];
    final column = Color.alphaBlend(
      palette.accentSoft.withValues(alpha: .3),
      colorScheme.surface,
    );
    return LayoutBuilder(
      key: const Key('calendarWeekView'),
      builder: (context, constraints) {
        final available = constraints.maxWidth - 2 * _gutter - _labelWidth;
        final unit = available / (6 + _selectedShare);
        final widths = [
          for (final day in days)
            _isSameDay(day, selected) ? unit * _selectedShare : unit,
        ];
        final lefts = <double>[];
        var x = _labelWidth;
        for (final width in widths) {
          lefts.add(x);
          x += width;
        }
        final selectedIndex = days.indexWhere(
          (day) => _isSameDay(day, selected),
        );
        Widget columns(Widget Function(int index) cell) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: _labelWidth),
            for (var index = 0; index < 7; index++)
              SizedBox(width: widths[index], child: cell(index)),
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              columns(
                (index) => _CalendarWeekHeaderDay(
                  day: days[index],
                  events: projection.eventsOn(days[index]),
                  isSelected: index == selectedIndex,
                  onTap: () => widget.onDate(days[index]),
                ),
              ),
              if (allDay.any((events) => events.isNotEmpty))
                columns(
                  (index) => ColoredBox(
                    color: index == selectedIndex ? column : Colors.transparent,
                    child: Column(
                      children: [
                        for (final event in allDay[index])
                          Padding(
                            padding: const EdgeInsets.fromLTRB(1, 2, 1, 0),
                            child: _WeekAllDayChip(
                              event: event,
                              onTap: () => widget.onEvent(event),
                            ),
                          ),
                        const SizedBox(height: 2),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('calendarWeekTimelineScroll'),
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 24),
                  child: SizedBox(
                    height: _hourHeight * 24,
                    child: Stack(
                      children: [
                        if (selectedIndex >= 0)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: lefts[selectedIndex],
                            width: widths[selectedIndex],
                            child: ColoredBox(color: column),
                          ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _WeekGridPainter(
                              hourHeight: _hourHeight,
                              labelWidth: _labelWidth,
                              columnLefts: lefts,
                              color: colorScheme.outlineVariant.withValues(
                                alpha: .45,
                              ),
                            ),
                          ),
                        ),
                        for (var hour = 2; hour <= 22; hour += 2)
                          Positioned(
                            top: hour * _hourHeight - 7,
                            left: 0,
                            width: _labelWidth - 5,
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: palette.muted,
                                    fontSize: 10,
                                  ),
                            ),
                          ),
                        for (var index = 0; index < 7; index++)
                          for (final item in _layoutDayEvents(
                            projection.eventsOn(days[index]),
                            days[index],
                          ))
                            // Overlapping events keep the day's width, too
                            // narrow to split, and lie over each other with
                            // a small step in.
                            Positioned(
                              top: item.startMinutes / 60 * _hourHeight + 1,
                              left:
                                  lefts[index] +
                                  item.column * _overlapStep +
                                  1.5,
                              width:
                                  widths[index] -
                                  item.column * _overlapStep -
                                  3,
                              height: item.cardHeight(
                                _hourHeight,
                                _minBlockHeight,
                              ),
                              child: _WeekEventBlock(
                                event: item.event,
                                detailed: index == selectedIndex,
                                onTap: () => widget.onEvent(item.event),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One day over the week grid: weekday, date and the type dots; the
/// selected day is lifted on a soft accent tab that runs on down its column.
class _CalendarWeekHeaderDay extends StatelessWidget {
  const _CalendarWeekHeaderDay({
    required this.day,
    required this.events,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final List<CalendarEventSummary> events;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final material = MaterialLocalizations.of(context);
    final isToday = _isSameDay(day, DateTime.now());
    final strong = isSelected || isToday;
    final radius = const BorderRadius.vertical(
      top: Radius.circular(AppRadius.tile),
    );
    return Semantics(
      selected: isSelected,
      button: true,
      label: material.formatFullDate(day),
      excludeSemantics: true,
      child: Material(
        key: ValueKey('calendarWeekDay-${day.weekday}'),
        color: isSelected ? palette.accentSoft : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(
                  _capitalized(_homeShortWeekday(material, day).toLowerCase()),
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: strong ? palette.accent : palette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${day.day}',
                  style:
                      (isSelected
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.titleSmall)
                          ?.copyWith(
                            color: strong
                                ? palette.accent
                                : theme.colorScheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final event in events.take(3))
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _calendarTypeColors(
                              context,
                              event.type,
                            ).strong,
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

/// Hour lines across the days and faint lines between the day columns.
class _WeekGridPainter extends CustomPainter {
  const _WeekGridPainter({
    required this.hourHeight,
    required this.labelWidth,
    required this.columnLefts,
    required this.color,
  });
  final double hourHeight, labelWidth;
  final List<double> columnLefts;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var hour = 0; hour <= 24; hour++) {
      final y = hour * hourHeight;
      canvas.drawLine(Offset(labelWidth, y), Offset(size.width, y), paint);
    }
    for (final x in [...columnLefts.skip(1), size.width]) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeekGridPainter oldDelegate) =>
      oldDelegate.hourHeight != hourHeight ||
      oldDelegate.color != color ||
      !listEquals(oldDelegate.columnLefts, columnLefts);
}

/// A timed event in the week grid, in its type's soft color: icon and
/// time over the title, with the team too on the selected day.
class _WeekEventBlock extends StatelessWidget {
  const _WeekEventBlock({
    required this.event,
    required this.detailed,
    required this.onTap,
  });

  final CalendarEventSummary event;
  final bool detailed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final cancelled = event.state == 'cancelled';
    final colors = _calendarTypeColors(context, event.type);
    final strong = cancelled ? palette.muted : colors.strong;
    final start = event.startsAt.toLocal();
    final time = detailed
        ? _eventTimeRange(context, start, event.endsAt.toLocal())
        : TimeOfDay.fromDateTime(start).format(context);
    final small = theme.textTheme.labelSmall?.copyWith(
      fontSize: detailed ? 10.5 : 9.5,
      height: 1.2,
    );
    Text line(String text, TextStyle? style, {Key? key}) => Text(
      text,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      style: style,
    );
    final icon = Icon(
      cancelled ? Icons.event_busy : _homeEventIcon(event.type),
      size: detailed ? 14 : 12,
      color: strong,
    );
    final timeLine = line(
      time,
      small?.copyWith(color: strong, fontWeight: FontWeight.w700),
    );
    return Opacity(
      opacity: cancelled ? .68 : 1,
      child: Material(
        key: ValueKey('week-event-${event.id}'),
        color: cancelled
            ? theme.colorScheme.surfaceContainerHighest
            : colors.soft,
        // The outline keeps blocks apart where they overlap and against
        // the selected day's soft column.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: strong.withValues(alpha: .35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(detailed ? 4 : 3),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  timeLine,
                  line(
                    _abbreviateHomeAwaySuffix(event.title),
                    small?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (detailed)
                    line(
                      event.teamName,
                      small?.copyWith(color: palette.muted),
                      key: ValueKey('week-event-team-${event.id}'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An all-day event under its day in the week header.
class _WeekAllDayChip extends StatelessWidget {
  const _WeekAllDayChip({required this.event, required this.onTap});
  final CalendarEventSummary event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _calendarTypeColors(context, event.type);
    return Material(
      color: colors.soft,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 9.5,
              color: colors.strong,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
