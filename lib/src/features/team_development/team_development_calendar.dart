part of '../../app/teamzone_app.dart';

/// How near the year calendar is: the season's months, a month, a week or
/// a day.
enum _TdpZoom { year, month, week, day }

/// The year calendar (decision 8): opened over nearly the whole page from
/// the season, it shows the plan's periods and blocks together with the
/// team's activities, and zooms from the season's months to a month, a week
/// and a day. An activity opens on its own page.
abstract final class _TdpCalendar {
  static Future<void> open(
    BuildContext context, {
    required _TdpController controller,
    required SeasonPlan plan,
    DateTime? day,
  }) async {
    final eventId = await showDialog<String>(
      context: context,
      builder: (_) => _TdpCalendarDialog(
        controller: controller,
        plan: plan,
        day: day == null ? null : DateUtils.dateOnly(day),
      ),
    );
    if (eventId != null) controller.onOpenEvent(eventId);
  }
}

/// Short weekday names, Monday first.
List<String> _tdpWeekdays(BuildContext context) =>
    AppStrings.of(context).isSwedish
    ? const ['Mån', 'Tis', 'Ons', 'Tor', 'Fre', 'Lör', 'Sön']
    : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The Monday of [day]'s week.
DateTime _tdpMonday(DateTime day) => _tdpShift(day, 1 - day.weekday);

/// An activity's local day.
DateTime _tdpDayOf(CalendarEventSummary event) =>
    DateUtils.dateOnly(event.startsAt.toLocal());

String _tdpTime(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: true,
    );

/// An activity's start and end, with the end's date when it ends another day.
String _tdpTimes(BuildContext context, CalendarEventSummary event) {
  final from = _tdpTime(context, event.startsAt);
  final to = _tdpTime(context, event.endsAt);
  final end = event.endsAt.toLocal();
  return DateUtils.isSameDay(_tdpDayOf(event), end)
      ? '$from–$to'
      : '$from – ${_tdpDate(context, end)} $to';
}

IconData _tdpActivityIcon(String type) => switch (type) {
  'training' => Icons.fitness_center,
  'match' => Icons.sports_soccer,
  'meeting' => Icons.groups_outlined,
  _ => Icons.event_outlined,
};

Color _tdpActivityColor(BuildContext context, String type) => switch (type) {
  'match' => const Color(0xFFC62828),
  'training' => Theme.of(context).colorScheme.primary,
  _ => const Color(0xFFB8860B),
};

class _TdpCalendarDialog extends StatefulWidget {
  const _TdpCalendarDialog({
    required this.controller,
    required this.plan,
    this.day,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final DateTime? day;

  @override
  State<_TdpCalendarDialog> createState() => _TdpCalendarDialogState();
}

class _TdpCalendarDialogState extends State<_TdpCalendarDialog> {
  late _TdpZoom _zoom = widget.day == null ? _TdpZoom.year : _TdpZoom.day;
  late DateTime _at = widget.day ?? _start;

  SeasonPlan get _plan => widget.plan;

  /// Where the season's view starts: today within the season, else its
  /// first day.
  DateTime get _start {
    final today = DateUtils.dateOnly(DateTime.now());
    return today.isBefore(_plan.startsOn) || today.isAfter(_plan.endsOn)
        ? _plan.startsOn
        : today;
  }

  void _go(_TdpZoom zoom, DateTime at) => setState(() {
    _zoom = zoom;
    _at = DateUtils.dateOnly(at);
  });

  /// The days the view shows, to read the activities for.
  (DateTime, DateTime) get _range => switch (_zoom) {
    _TdpZoom.year => (
      DateTime(_plan.startsOn.year, _plan.startsOn.month),
      DateTime(_plan.endsOn.year, _plan.endsOn.month + 1, 0),
    ),
    _TdpZoom.month => (
      _tdpMonday(DateTime(_at.year, _at.month)),
      _tdpShift(_tdpMonday(DateTime(_at.year, _at.month + 1, 0)), 6),
    ),
    _TdpZoom.week => (_tdpMonday(_at), _tdpShift(_tdpMonday(_at), 6)),
    _TdpZoom.day => (_at, _at),
  };

  void _step(int by) => setState(() {
    _at = switch (_zoom) {
      _TdpZoom.year => _at,
      _TdpZoom.month => DateTime(_at.year, _at.month + by),
      _TdpZoom.week => _tdpShift(_at, 7 * by),
      _TdpZoom.day => _tdpShift(_at, by),
    };
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    final (from, to) = _range;
    final body = FutureBuilder<List<CalendarEventSummary>>(
      future: widget.controller.activities(from, to),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              _tdpText(
                context,
                'Aktiviteterna kunde inte hämtas.',
                'The activities could not be loaded.',
              ),
            ),
          );
        }
        final events = snapshot.data;
        if (events == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return switch (_zoom) {
          _TdpZoom.year => _TdpYearView(
            plan: _plan,
            events: events,
            onMonth: (month) => _go(_TdpZoom.month, month),
          ),
          _TdpZoom.month => _TdpMonthView(
            plan: _plan,
            month: DateTime(_at.year, _at.month),
            events: events,
            onWeek: (monday) => _go(_TdpZoom.week, monday),
            onDay: (day) => _go(_TdpZoom.day, day),
          ),
          _TdpZoom.week => _TdpWeekView(
            plan: _plan,
            monday: _tdpMonday(_at),
            events: events,
            onDay: (day) => _go(_TdpZoom.day, day),
          ),
          _TdpZoom.day => _TdpDayView(
            plan: _plan,
            day: _at,
            events: events,
            onOpen: (event) => Navigator.pop(context, event.id),
          ),
        };
      },
    );
    final content = Column(
      key: const Key('tdp-calendar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TdpCalendarBar(
          plan: _plan,
          zoom: _zoom,
          at: _at,
          onCrumb: _go,
          onStep: _zoom == _TdpZoom.year ? null : _step,
          onToday: () => _go(
            _zoom == _TdpZoom.year ? _TdpZoom.month : _zoom,
            DateTime.now(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(padding: const EdgeInsets.all(16), child: body),
        ),
      ],
    );
    return wide
        ? Dialog(
            insetPadding: const EdgeInsets.all(24),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: size.width - 48,
              height: size.height - 48,
              child: content,
            ),
          )
        : Dialog.fullscreen(child: SafeArea(child: content));
  }
}

/// The calendar's top: the way back up (season › month › week › day), the
/// arrows, today and close.
class _TdpCalendarBar extends StatelessWidget {
  const _TdpCalendarBar({
    required this.plan,
    required this.zoom,
    required this.at,
    required this.onCrumb,
    required this.onStep,
    required this.onToday,
  });
  final SeasonPlan plan;
  final _TdpZoom zoom;
  final DateTime at;
  final void Function(_TdpZoom zoom, DateTime at) onCrumb;
  final ValueChanged<int>? onStep;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    final crumbs = <(_TdpZoom, String)>[
      (_TdpZoom.year, plan.title),
      if (zoom.index >= _TdpZoom.month.index)
        (_TdpZoom.month, local.formatMonthYear(at)),
      if (zoom.index >= _TdpZoom.week.index)
        (
          _TdpZoom.week,
          _tdpText(context, 'Vecka ${_tdpWeek(at)}', 'Week ${_tdpWeek(at)}'),
        ),
      if (zoom == _TdpZoom.day)
        (
          _TdpZoom.day,
          '${_tdpWeekdays(context)[at.weekday - 1]} ${_tdpDate(context, at)}',
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (index, (level, label)) in crumbs.indexed) ...[
                    if (index > 0)
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    index == crumbs.length - 1
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              label,
                              style: theme.textTheme.titleMedium,
                            ),
                          )
                        : TextButton(
                            key: Key('tdp-cal-crumb-${level.name}'),
                            onPressed: () => onCrumb(level, at),
                            child: Text(label),
                          ),
                  ],
                ],
              ),
            ),
          ),
          if (onStep != null) ...[
            IconButton(
              key: const Key('tdp-cal-previous'),
              tooltip: _tdpText(context, 'Föregående', 'Previous'),
              onPressed: () => onStep!(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              key: const Key('tdp-cal-next'),
              tooltip: _tdpText(context, 'Nästa', 'Next'),
              onPressed: () => onStep!(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
          TextButton(
            key: const Key('tdp-cal-today'),
            onPressed: onToday,
            child: Text(_tdpText(context, 'I dag', 'Today')),
          ),
          IconButton(
            key: const Key('tdp-cal-close'),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// The season's months as cards: the days in their period's color, a dot
/// per activity, and a count of the month's activities. A tap zooms in.
class _TdpYearView extends StatelessWidget {
  const _TdpYearView({
    required this.plan,
    required this.events,
    required this.onMonth,
  });
  final SeasonPlan plan;
  final List<CalendarEventSummary> events;
  final ValueChanged<DateTime> onMonth;

  @override
  Widget build(BuildContext context) {
    final months = [
      for (
        var month = DateTime(plan.startsOn.year, plan.startsOn.month);
        !month.isAfter(plan.endsOn);
        month = DateTime(month.year, month.month + 1)
      )
        month,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1200
            ? 4
            : constraints.maxWidth >= 860
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 268,
          ),
          itemCount: months.length,
          itemBuilder: (context, index) => _TdpMonthCard(
            plan: plan,
            month: months[index],
            events: [
              for (final event in events)
                if (_tdpDayOf(event).year == months[index].year &&
                    _tdpDayOf(event).month == months[index].month)
                  event,
            ],
            onTap: () => onMonth(months[index]),
          ),
        );
      },
    );
  }
}

class _TdpMonthCard extends StatelessWidget {
  const _TdpMonthCard({
    required this.plan,
    required this.month,
    required this.events,
    required this.onTap,
  });
  final SeasonPlan plan;
  final DateTime month;
  final List<CalendarEventSummary> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final first = _tdpMonday(month);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final weeks = ((month.weekday - 1 + days) / 7).ceil();
    int count(String type) => events.where((e) => e.type == type).length;
    final matches = count('match'), trainings = count('training');
    final others = events.length - matches - trainings;
    final periodsHere = [
      for (final period in plan.periods)
        if (!period.endsOn.isBefore(month) &&
            !period.startsOn.isAfter(DateTime(month.year, month.month + 1, 0)))
          period,
    ];
    return Card(
      key: Key('tdp-cal-month-${month.year}-${month.month}'),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                MaterialLocalizations.of(context).formatMonthYear(month),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final name in _tdpWeekdays(context))
                    Expanded(
                      child: Text(
                        name.substring(0, 1),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
              for (var week = 0; week < weeks; week++)
                Row(
                  children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(
                        child: _TdpMiniDay(
                          plan: plan,
                          day: _tdpShift(first, week * 7 + weekday),
                          month: month,
                          today: today,
                          events: events,
                        ),
                      ),
                  ],
                ),
              const Spacer(),
              Text(
                [
                  if (matches > 0)
                    _tdpText(context, '$matches matcher', '$matches matches'),
                  if (trainings > 0)
                    _tdpText(
                      context,
                      '$trainings träningar',
                      '$trainings trainings',
                    ),
                  if (others > 0)
                    _tdpText(context, '$others andra', '$others other'),
                  if (events.isEmpty)
                    _tdpText(context, 'Inga aktiviteter', 'No activities'),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              if (periodsHere.isNotEmpty)
                Text(
                  periodsHere.map((period) => period.name).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _tdpPhaseColor(periodsHere.first.phase),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A day in a month card: tinted by its period, ringed today, with a dot for
/// a match (red) or another activity.
class _TdpMiniDay extends StatelessWidget {
  const _TdpMiniDay({
    required this.plan,
    required this.day,
    required this.month,
    required this.today,
    required this.events,
  });
  final SeasonPlan plan;
  final DateTime day, month, today;
  final List<CalendarEventSummary> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (day.month != month.month) return const SizedBox(height: 26);
    final period = plan.periodOn(day);
    final here = [
      for (final event in events)
        if (DateUtils.isSameDay(_tdpDayOf(event), day)) event,
    ];
    final match = here.any((event) => event.type == 'match');
    final cell = Container(
      height: 26,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: period == null
            ? null
            : _tdpPhaseColor(period.phase).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: DateUtils.isSameDay(day, today)
            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('${day.day}', style: theme.textTheme.labelSmall),
          if (here.isNotEmpty)
            Positioned(
              bottom: 2,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: match
                      ? _tdpActivityColor(context, 'match')
                      : _tdpActivityColor(context, here.first.type),
                ),
              ),
            ),
        ],
      ),
    );
    if (here.isEmpty) return cell;
    // A hover (a long press on a phone) lists the day's activities; the list
    // goes when the pointer moves on.
    return Tooltip(
      key: Key('tdp-cal-mini-${day.year}-${day.month}-${day.day}'),
      waitDuration: const Duration(milliseconds: 150),
      exitDuration: Duration.zero,
      preferBelow: false,
      richMessage: TextSpan(
        children: [
          TextSpan(
            text:
                '${_tdpWeekdays(context)[day.weekday - 1]} ${_tdpDate(context, day)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final event in here)
            TextSpan(
              text: event.allDay
                  ? '\n${event.title}'
                  : '\n${_tdpTime(context, event.startsAt)}  ${event.title}',
            ),
        ],
      ),
      child: cell,
    );
  }
}

/// A month as a calendar: the week numbers in their period's color (a tap
/// opens the week) and the activities in the days (a tap opens the day).
class _TdpMonthView extends StatelessWidget {
  const _TdpMonthView({
    required this.plan,
    required this.month,
    required this.events,
    required this.onWeek,
    required this.onDay,
  });
  final SeasonPlan plan;
  final DateTime month;
  final List<CalendarEventSummary> events;
  final ValueChanged<DateTime> onWeek, onDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final first = _tdpMonday(month);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final weeks = ((month.weekday - 1 + days) / 7).ceil();
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 48),
            for (final name in _tdpWeekdays(context))
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var week = 0; week < weeks; week++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TdpWeekNumber(
                  plan: plan,
                  monday: _tdpShift(first, week * 7),
                  onTap: () => onWeek(_tdpShift(first, week * 7)),
                ),
                for (var weekday = 0; weekday < 7; weekday++)
                  Expanded(
                    child: _TdpMonthDay(
                      plan: plan,
                      day: _tdpShift(first, week * 7 + weekday),
                      inMonth:
                          _tdpShift(first, week * 7 + weekday).month ==
                          month.month,
                      today: today,
                      events: [
                        for (final event in events)
                          if (DateUtils.isSameDay(
                            _tdpDayOf(event),
                            _tdpShift(first, week * 7 + weekday),
                          ))
                            event,
                      ],
                      onTap: () => onDay(_tdpShift(first, week * 7 + weekday)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TdpWeekNumber extends StatelessWidget {
  const _TdpWeekNumber({
    required this.plan,
    required this.monday,
    required this.onTap,
  });
  final SeasonPlan plan;
  final DateTime monday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The week belongs to the period its Thursday is in.
    final period = plan.periodOn(_tdpShift(monday, 3));
    final color = period == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : _tdpPhaseColor(period.phase);
    return SizedBox(
      width: 48,
      child: Tooltip(
        message: period?.name ?? '',
        child: InkWell(
          key: Key('tdp-cal-week-${_tdpWeek(monday)}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.all(2),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: period == null ? null : color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _tdpText(
                context,
                'v. ${_tdpWeek(monday)}',
                'w. ${_tdpWeek(monday)}',
              ),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _TdpMonthDay extends StatelessWidget {
  const _TdpMonthDay({
    required this.plan,
    required this.day,
    required this.inMonth,
    required this.today,
    required this.events,
    required this.onTap,
  });
  final SeasonPlan plan;
  final DateTime day, today;
  final bool inMonth;
  final List<CalendarEventSummary> events;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final block = plan.blockOn(day);
    final startsBlock =
        block != null &&
        (DateUtils.isSameDay(block.startsOn, day) || day.weekday == 1);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: inMonth
            ? colors.surfaceContainerLow
            : colors.surfaceContainerLow.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('tdp-cal-day-${day.year}-${day.month}-${day.day}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: DateUtils.isSameDay(day, today)
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.primary, width: 1.5),
                  )
                : null,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // As many activities as there is room for, then a count.
                final room = ((constraints.maxHeight - 36) / 18).floor().clamp(
                  0,
                  events.length,
                );
                final shown = room < events.length
                    ? (room - 1).clamp(0, events.length)
                    : room;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${day.day}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: inMonth ? null : colors.onSurfaceVariant,
                      ),
                    ),
                    if (startsBlock)
                      Text(
                        block.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                        ),
                      )
                    else
                      const SizedBox(height: 14),
                    for (final event in events.take(shown))
                      _TdpActivityLine(event: event),
                    if (shown < events.length)
                      Text(
                        _tdpText(
                          context,
                          '+${events.length - shown} till',
                          '+${events.length - shown} more',
                        ),
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// An activity on one line: its kind's icon, the time and the title.
class _TdpActivityLine extends StatelessWidget {
  const _TdpActivityLine({required this.event});
  final CalendarEventSummary event;

  @override
  Widget build(BuildContext context) {
    final color = _tdpActivityColor(context, event.type);
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          Icon(_tdpActivityIcon(event.type), size: 12, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              event.allDay
                  ? event.title
                  : '${_tdpTime(context, event.startsAt)} ${event.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
