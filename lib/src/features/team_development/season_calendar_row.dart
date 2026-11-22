part of '../../app/teamzone_app.dart';

/// The colour of a holiday, school break, vacation or other days off.
Color _tdpCalendarColor(CalendarPeriodKind kind) => switch (kind) {
  CalendarPeriodKind.holiday => const Color(0xFFC0392B),
  CalendarPeriodKind.schoolBreak => const Color(0xFFB7791F),
  CalendarPeriodKind.vacation => const Color(0xFF1F7A8C),
  CalendarPeriodKind.other => const Color(0xFF6C757D),
};

IconData _tdpCalendarIcon(CalendarPeriodKind kind) => switch (kind) {
  CalendarPeriodKind.holiday => Icons.celebration_outlined,
  CalendarPeriodKind.schoolBreak => Icons.school_outlined,
  CalendarPeriodKind.vacation => Icons.beach_access_outlined,
  CalendarPeriodKind.other => Icons.event_busy_outlined,
};

String _tdpCalendarKind(BuildContext context, CalendarPeriodKind kind) =>
    _tdpText(context, kind.label, kind.english);

/// The timeline's third row (2026-11-22): holidays, school breaks and
/// vacations that affect the planning. They may overlap, so each takes the
/// first line free at its dates. A tap opens one; a drag on an empty
/// stretch lays out a new one in whole weeks.
class _TdpCalendarLane extends StatefulWidget {
  const _TdpCalendarLane({
    required this.plan,
    required this.width,
    required this.canEdit,
    required this.x,
    required this.dayAt,
    required this.weekStart,
    required this.onOpen,
    required this.onCreate,
  });
  final SeasonPlan plan;
  final double width;
  final bool canEdit;

  /// Where a day begins on the timeline, and the day and week at a point.
  final double Function(DateTime day) x;
  final DateTime Function(double dx) dayAt;
  final DateTime Function(double dx) weekStart;
  final ValueChanged<SeasonCalendarPeriod> onOpen;
  final void Function(DateTime startsOn, DateTime endsOn) onCreate;

  static const _line = 22.0;

  /// Each stretch's line: the first one free at its dates.
  static Map<String, int> lines(List<SeasonCalendarPeriod> items) {
    final ends = <DateTime>[];
    final lines = <String, int>{};
    for (final item in items) {
      var line = ends.indexWhere((end) => end.isBefore(item.startsOn));
      if (line < 0) {
        line = ends.length;
        ends.add(item.endsOn);
      } else {
        ends[line] = item.endsOn;
      }
      lines[item.id] = line;
    }
    return lines;
  }

  @override
  State<_TdpCalendarLane> createState() => _TdpCalendarLaneState();
}

class _TdpCalendarLaneState extends State<_TdpCalendarLane> {
  (DateTime, DateTime)? _drag;
  DateTime? _anchor;

  SeasonCalendarPeriod? _hit(Offset at, Map<String, int> lines) {
    final line = ((at.dy - 4) / _TdpCalendarLane._line).floor();
    return widget.plan.calendarPeriods
        .where(
          (item) =>
              lines[item.id] == line &&
              at.dx >= widget.x(item.startsOn) &&
              at.dx <= widget.x(_tdpShift(item.endsOn, 1)),
        )
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.plan.calendarPeriods;
    final lines = _TdpCalendarLane.lines(items);
    final count = lines.values.fold(0, (a, b) => b + 1 > a ? b + 1 : a);
    final height = (count < 1 ? 1 : count) * _TdpCalendarLane._line + 8;
    final drag = _drag;
    double left(DateTime day) => widget.x(day).clamp(0.0, widget.width);
    double right(DateTime day) =>
        widget.x(_tdpShift(day, 1)).clamp(0.0, widget.width);
    return GestureDetector(
      key: const Key('tdp-lane-calendar'),
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final hit = _hit(details.localPosition, lines);
        if (hit != null) widget.onOpen(hit);
      },
      onHorizontalDragStart: widget.canEdit
          ? (details) => setState(() {
              final week = widget.weekStart(details.localPosition.dx);
              _anchor = week;
              _drag = (week, _tdpShift(week, 6));
            })
          : null,
      onHorizontalDragUpdate: widget.canEdit
          ? (details) => setState(() {
              final anchor = _anchor;
              if (anchor == null) return;
              final week = widget.weekStart(details.localPosition.dx);
              final first = week.isBefore(anchor) ? week : anchor;
              final last = week.isBefore(anchor) ? anchor : week;
              _drag = (first, _tdpShift(last, 6));
            })
          : null,
      onHorizontalDragEnd: widget.canEdit
          ? (_) {
              final done = _drag;
              setState(() => _drag = _anchor = null);
              if (done != null) widget.onCreate(done.$1, done.$2);
            }
          : null,
      onHorizontalDragCancel: () => setState(() => _drag = _anchor = null),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (items.isEmpty && drag == null)
              Center(
                child: Text(
                  widget.canEdit
                      ? _tdpText(
                          context,
                          'Inga lov eller högtider ännu. Dra här för att lägga till en ledighet.',
                          'No breaks or holidays yet. Drag here to add days off.',
                        )
                      : _tdpText(
                          context,
                          'Inga lov eller högtider.',
                          'No breaks or holidays.',
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final item in items)
              Positioned(
                key: ValueKey('tdp-calendar-${item.id}'),
                left: left(item.startsOn) + 1,
                width: (right(item.endsOn) - left(item.startsOn) - 2).clamp(
                  3.0,
                  widget.width,
                ),
                top: 4 + lines[item.id]! * _TdpCalendarLane._line,
                height: _TdpCalendarLane._line - 3,
                child: _TdpCalendarChip(item: item),
              ),
            if (drag != null)
              Positioned(
                left: left(drag.$1),
                width: right(drag.$2) - left(drag.$1),
                top: 2,
                bottom: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.colorScheme.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TdpCalendarChip extends StatelessWidget {
  const _TdpCalendarChip({required this.item});
  final SeasonCalendarPeriod item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _tdpCalendarColor(item.kind);
    return Tooltip(
      message:
          '${item.name} · ${_tdpCalendarKind(context, item.kind)} · '
          '${_tdpRange(context, item.startsOn, item.endsOn)}',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The row's heading with what a leader may do there.
class _TdpCalendarHeader extends StatelessWidget {
  const _TdpCalendarHeader({required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // On a narrow screen the buttons go under the heading.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          _tdpText(
            context,
            'Lov, högtider och semestrar',
            'Breaks, holidays and vacations',
          ),
          style: label,
        ),
        if (controller.canEdit) ...[
          TextButton.icon(
            key: const Key('tdp-calendar-suggest'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => _TdpHolidayDialog.show(context, controller, plan),
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text(
              _tdpText(
                context,
                'Lägg in högtider och lov',
                'Add holidays and breaks',
              ),
            ),
          ),
          TextButton.icon(
            key: const Key('tdp-calendar-add'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () =>
                _TdpCalendarPeriodDialog.edit(context, controller, plan),
            icon: const Icon(Icons.add, size: 16),
            label: Text(_tdpText(context, 'Lägg till', 'Add')),
          ),
        ],
      ],
    );
  }
}

/// The holidays, breaks and vacations touching [from]–[to], as chips: in
/// the year calendar's week and day.
class _TdpCalendarNote extends StatelessWidget {
  const _TdpCalendarNote({
    required this.plan,
    required this.from,
    required this.to,
  });
  final SeasonPlan plan;
  final DateTime from, to;

  @override
  Widget build(BuildContext context) {
    final here = [
      for (final item in plan.calendarPeriods)
        if (!item.startsOn.isAfter(to) && !item.endsOn.isBefore(from)) item,
    ];
    if (here.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('tdp-cal-calendar-note'),
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in here)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                _tdpCalendarIcon(item.kind),
                size: 16,
                color: _tdpCalendarColor(item.kind),
              ),
              side: BorderSide(
                color: _tdpCalendarColor(item.kind).withValues(alpha: 0.5),
              ),
              label: Text(
                item.startsOn == item.endsOn
                    ? '${item.name} · ${_tdpDate(context, item.startsOn)}'
                    : '${item.name} · ${_tdpRange(context, item.startsOn, item.endsOn)}',
              ),
            ),
        ],
      ),
    );
  }
}
