part of '../../app/teamzone_app.dart';

/// A period or block as the timeline reads it.
typedef _TdpSpan = ({
  String id,
  String? periodId,
  DateTime startsOn,
  DateTime endsOn,
});

/// A period or a block picked on the timeline.
typedef _TdpPick = ({bool block, String id});

/// A period or block laid out on the timeline: new when [id] is null; a
/// block inside [periodId].
typedef _TdpLayout = ({
  bool block,
  String? id,
  String? periodId,
  DateTime startsOn,
  DateTime endsOn,
});

/// A drag on the timeline: what is dragged, how, from where, and the dates
/// it may move between.
class _TdpDrag {
  _TdpDrag({
    required this.block,
    required this.mode,
    required this.anchor,
    required this.start,
    required this.end,
    required this.low,
    required this.high,
    this.id,
    this.periodId,
    this.innerStart,
    this.innerEnd,
  }) : origStart = start,
       origEnd = end;
  final bool block;
  final String? id, periodId;

  /// 'move', 'left', 'right' or 'create'.
  final String mode;
  final double anchor;
  final DateTime origStart, origEnd, low, high;

  /// A period's blocks, which a resize may not cut.
  final DateTime? innerStart, innerEnd;
  DateTime start, end;

  bool get changed => mode == 'create' || start != origStart || end != origEnd;
}

/// Planera's timeline (decision 11, 2026-11-01): the season on a ruler of
/// months and weeks, the periods on one lane and the blocks on another.
/// Drag on an empty stretch to lay out a new one, an edge to change its
/// dates, the middle to move it (a period takes its blocks along); a tap
/// picks one. Weeks start on Mondays; a moved one keeps its own weekdays.
class _TdpTimelineEditor extends StatefulWidget {
  const _TdpTimelineEditor({
    required this.plan,
    required this.canEdit,
    required this.picked,
    required this.onPick,
    required this.onLayout,
  });
  final SeasonPlan plan;
  final bool canEdit;
  final _TdpPick? picked;
  final ValueChanged<_TdpPick?> onPick;
  final Future<void> Function(_TdpLayout layout) onLayout;

  @override
  State<_TdpTimelineEditor> createState() => _TdpTimelineEditorState();
}

class _TdpTimelineEditorState extends State<_TdpTimelineEditor> {
  _TdpDrag? _drag;
  static const _day = Duration(days: 1);

  SeasonPlan get plan => widget.plan;
  DateTime get _monday =>
      plan.startsOn.subtract(Duration(days: plan.startsOn.weekday - 1));
  int get _days => plan.endsOn.difference(_monday).inDays + 1;

  double _x(DateTime day, double width) =>
      day.difference(_monday).inDays / _days * width;
  double _dayAt(double dx, double width) =>
      (dx / width * _days).clamp(0, _days - 1).toDouble();
  DateTime _date(double day) => _monday.add(Duration(days: day.floor()));
  DateTime _weekStart(double day) =>
      _monday.add(Duration(days: day.floor() ~/ 7 * 7));
  static DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  /// The dates free around [from]–[to] among [others], inside [low]–[high].
  (DateTime, DateTime) _room(
    Iterable<_TdpSpan> others,
    DateTime from,
    DateTime to,
    DateTime low,
    DateTime high,
  ) {
    for (final other in others) {
      if (other.endsOn.isBefore(from)) {
        low = _max(low, other.endsOn.add(_day));
      } else if (other.startsOn.isAfter(to)) {
        high = _min(high, other.startsOn.subtract(_day));
      }
    }
    return (low, high);
  }

  List<_TdpSpan> _items(bool block) => block
      ? [
          for (final b in plan.blocks)
            (
              id: b.id,
              periodId: b.periodId,
              startsOn: b.startsOn,
              endsOn: b.endsOn,
            ),
        ]
      : [
          for (final p in plan.periods)
            (id: p.id, periodId: null, startsOn: p.startsOn, endsOn: p.endsOn),
        ];

  void _start(bool block, double dx, double width) {
    if (!widget.canEdit) return;
    final day = _dayAt(dx, width);
    final date = _date(day);
    final items = _items(block);
    final hit = items
        .where(
          (item) =>
              dx >= _x(item.startsOn, width) - 2 &&
              dx <= _x(item.endsOn.add(_day), width) + 2,
        )
        .firstOrNull;
    if (hit != null) {
      final left = _x(hit.startsOn, width),
          right = _x(hit.endsOn.add(_day), width);
      final edge = (right - left) < 24 ? 4.0 : 10.0;
      final mode = dx - left < edge
          ? 'left'
          : right - dx < edge
          ? 'right'
          : 'move';
      final period = block
          ? plan.periods.where((p) => p.id == hit.periodId).firstOrNull
          : null;
      final siblings = items.where(
        (item) => item.id != hit.id && item.periodId == hit.periodId,
      );
      final (low, high) = _room(
        siblings,
        hit.startsOn,
        hit.endsOn,
        period?.startsOn ?? plan.startsOn,
        period?.endsOn ?? plan.endsOn,
      );
      final inner = block ? const <DevelopmentBlock>[] : plan.blocksOf(hit.id);
      _drag = _TdpDrag(
        block: block,
        id: hit.id,
        periodId: hit.periodId,
        mode: mode,
        anchor: day,
        start: hit.startsOn,
        end: hit.endsOn,
        low: low,
        high: high,
        innerStart: inner.firstOrNull?.startsOn,
        innerEnd: inner.lastOrNull?.endsOn,
      );
    } else {
      final period = block
          ? plan.periods.where((p) => p.contains(date)).firstOrNull
          : null;
      if (block && period == null) return;
      final (low, high) = _room(
        items.where((item) => !block || item.periodId == period!.id),
        date,
        date,
        period?.startsOn ?? plan.startsOn,
        period?.endsOn ?? plan.endsOn,
      );
      final week = _weekStart(day);
      _drag = _TdpDrag(
        block: block,
        periodId: period?.id,
        mode: 'create',
        anchor: day,
        start: _max(week, low),
        end: _min(week.add(const Duration(days: 6)), high),
        low: low,
        high: high,
      );
    }
    setState(() {});
  }

  void _update(double dx, double width) {
    final drag = _drag;
    if (drag == null) return;
    final day = _dayAt(dx, width);
    final weeks = ((day - drag.anchor) / 7).round();
    final shift = Duration(days: weeks * 7);
    switch (drag.mode) {
      case 'move':
        var start = drag.origStart.add(shift), end = drag.origEnd.add(shift);
        if (start.isBefore(drag.low)) {
          end = end.add(drag.low.difference(start));
          start = drag.low;
        }
        if (end.isAfter(drag.high)) {
          start = start.subtract(end.difference(drag.high));
          end = drag.high;
        }
        if (!start.isBefore(drag.low)) {
          drag.start = start;
          drag.end = end;
        }
      case 'left':
        var start = _max(drag.origStart.add(shift), drag.low);
        start = _min(start, drag.innerStart ?? drag.end);
        drag.start = _min(start, drag.end);
      case 'right':
        var end = _min(drag.origEnd.add(shift), drag.high);
        end = _max(end, drag.innerEnd ?? drag.start);
        drag.end = _max(end, drag.start);
      default:
        final a = _weekStart(drag.anchor), b = _weekStart(day);
        drag.start = _max(_min(a, b), drag.low);
        drag.end = _min(_max(a, b).add(const Duration(days: 6)), drag.high);
    }
    setState(() {});
  }

  Future<void> _end() async {
    final drag = _drag;
    if (drag == null) return;
    if (drag.changed && !drag.end.isBefore(drag.start)) {
      await widget.onLayout((
        block: drag.block,
        id: drag.id,
        periodId: drag.periodId,
        startsOn: drag.start,
        endsOn: drag.end,
      ));
    }
    if (mounted) setState(() => _drag = null);
  }

  void _tap(bool block, double dx, double width) {
    final hit = _items(block)
        .where(
          (item) =>
              dx >= _x(item.startsOn, width) &&
              dx <= _x(item.endsOn.add(_day), width),
        )
        .firstOrNull;
    widget.onPick(hit == null ? null : (block: block, id: hit.id));
  }

  /// Where an item is drawn now: dragged, moved with its dragged period,
  /// or as saved.
  (DateTime, DateTime) _shown(
    bool block,
    String id,
    String? periodId,
    DateTime from,
    DateTime to,
  ) {
    final drag = _drag;
    if (drag == null) return (from, to);
    if (drag.block == block && drag.id == id) return (drag.start, drag.end);
    if (block && !drag.block && drag.mode == 'move' && drag.id == periodId) {
      final shift = drag.start.difference(drag.origStart);
      return (from.add(shift), to.add(shift));
    }
    return (from, to);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        Widget lane(bool block, double height) {
          final drag = _drag;
          final children = <Widget>[
            for (final item in _items(block))
              _item(
                context,
                block,
                item.id,
                item.periodId,
                item.startsOn,
                item.endsOn,
                width,
              ),
            if (drag != null && drag.block == block && drag.mode == 'create')
              Positioned(
                left: _x(drag.start, width),
                width: _x(drag.end.add(_day), width) - _x(drag.start, width),
                top: 4,
                bottom: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            if (!today.isBefore(plan.startsOn) && !today.isAfter(plan.endsOn))
              Positioned(
                left: _x(today, width),
                top: 0,
                bottom: 0,
                width: 2,
                child: IgnorePointer(
                  child: ColoredBox(color: theme.colorScheme.error),
                ),
              ),
          ];
          return GestureDetector(
            key: Key(block ? 'tdp-lane-blocks' : 'tdp-lane-periods'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _tap(block, details.localPosition.dx, width),
            onHorizontalDragStart: (details) =>
                _start(block, details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _update(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: () => setState(() => _drag = null),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(clipBehavior: Clip.none, children: children),
            ),
          );
        }

        final label = theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ruler(context, width),
            const SizedBox(height: 8),
            Text(_tdpText(context, 'Perioder', 'Periods'), style: label),
            const SizedBox(height: 4),
            lane(false, 48),
            const SizedBox(height: 10),
            Text(_tdpText(context, 'Block', 'Blocks'), style: label),
            const SizedBox(height: 4),
            lane(true, 40),
          ],
        );
      },
    );
  }

  Widget _item(
    BuildContext context,
    bool block,
    String id,
    String? periodId,
    DateTime from,
    DateTime to,
    double width,
  ) {
    final theme = Theme.of(context);
    final (start, end) = _shown(block, id, periodId, from, to);
    final picked = widget.picked?.block == block && widget.picked?.id == id;
    final period = plan.periods
        .where((p) => p.id == (block ? periodId : id))
        .firstOrNull;
    final color = _tdpPhaseColor(period?.phase ?? PeriodPhase.other);
    final name = block
        ? plan.blocks.where((b) => b.id == id).firstOrNull?.name ?? ''
        : period?.name ?? '';
    final weeks = 'v${_tdpWeek(start)}–${_tdpWeek(end)}';
    return Positioned(
      key: ValueKey('tdp-item-$id'),
      left: _x(start, width) + 1,
      width: (_x(end.add(_day), width) - _x(start, width) - 2).clamp(
        2.0,
        width,
      ),
      top: 4,
      bottom: 4,
      child: MouseRegion(
        cursor: widget.canEdit ? SystemMouseCursors.grab : MouseCursor.defer,
        child: Tooltip(
          message: '$name · ${_tdpRange(context, start, end)}',
          waitDuration: const Duration(milliseconds: 600),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: block
                  ? theme.colorScheme.surface
                  : color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: picked ? theme.colorScheme.primary : color,
                width: picked ? 2.5 : 1,
              ),
            ),
            child: Text(
              block ? name : '$name · $weeks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: block ? FontWeight.w500 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Months above, every other week number under them.
  Widget _ruler(BuildContext context, double width) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final months = <DateTime>[];
    for (
      var month = DateTime(plan.startsOn.year, plan.startsOn.month);
      !month.isAfter(plan.endsOn);
      month = DateTime(month.year, month.month + 1)
    ) {
      months.add(month);
    }
    final weeks = (_days / 7).ceil();
    final names = MaterialLocalizations.of(context);
    return SizedBox(
      height: 34,
      child: Stack(
        children: [
          for (final month in months)
            Positioned(
              left: _x(_max(month, _monday), width),
              top: 0,
              child: Container(
                padding: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Text(
                  names.formatMonthYear(month).split(' ').first,
                  style: style,
                ),
              ),
            ),
          if (width / weeks >= 9)
            for (var week = 0; week < weeks; week += 2)
              Positioned(
                left: week * 7 / _days * width,
                width: 7 / _days * width * 2,
                top: 18,
                child: Text(
                  '${_tdpWeek(_monday.add(Duration(days: week * 7)))}',
                  style: style,
                ),
              ),
        ],
      ),
    );
  }
}
