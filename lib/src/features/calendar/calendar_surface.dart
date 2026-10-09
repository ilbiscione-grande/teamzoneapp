part of '../../app/teamzone_app.dart';

class _CalendarSurface extends StatefulWidget {
  const _CalendarSurface({
    required this.contextValue,
    required this.contexts,
    required this.calendar,
    required this.calendarPreferences,
    required this.match,
    required this.onNavigate,
    required this.matchSpaceV2,
    this.initialAction,
    this.initialEventType,
  });

  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final CalendarServices calendar;
  final CalendarPreferences calendarPreferences;
  final MatchServices match;
  final ValueChanged<String> onNavigate;
  final bool matchSpaceV2;
  // Set by the swipe-up quick actions sheet's "Skapa nytt event" shortcut
  // (ProductRouteContract.calendarCreateEvent) to open the create-event
  // dialog immediately on arrival — see _openInitialAction.
  final String? initialAction;

  /// Event type preselected by a create shortcut (`&type=match`).
  final String? initialEventType;

  @override
  State<_CalendarSurface> createState() => _CalendarSurfaceState();
}

class _CalendarWorkspace extends StatelessWidget {
  const _CalendarWorkspace({
    required this.events,
    required this.teams,
    required this.mode,
    required this.selectedDate,
    required this.stale,
    required this.reconnecting,
    required this.onModeChanged,
    required this.onDateChanged,
    required this.onTeamChanged,
    required this.onTypeChanged,
    required this.showArchived,
    required this.onShowArchivedChanged,
    required this.onEvent,
    required this.showWeekNumbers,
    required this.onShowWeekNumbersChanged,
    required this.showQuarterHourMarks,
    required this.onShowQuarterHourMarksChanged,
    required this.onDismissStale,
    required this.monthEventScope,
    required this.onMonthEventScopeChanged,
    this.teamFilter,
    this.eventTypeFilter,
    this.lastUpdated,
  });

  /// Teams shown; null shows every team you are connected to.
  final List<CalendarEventSummary> events;
  final Map<String, String> teams;
  final CalendarViewMode mode;
  final DateTime selectedDate;
  final Set<String>? teamFilter;
  final String? eventTypeFilter;
  final bool stale, reconnecting, showWeekNumbers, showQuarterHourMarks;
  final bool showArchived;
  final DateTime? lastUpdated;
  final _MonthEventScope monthEventScope;
  final ValueChanged<_MonthEventScope> onMonthEventScopeChanged;
  final ValueChanged<CalendarViewMode> onModeChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<Set<String>?> onTeamChanged;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<bool> onShowArchivedChanged;
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
      eventType: eventTypeFilter,
    );
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
              Row(
                children: [
                  // The date navigation uses the whole row, with the period
                  // centred between the arrows; the view-and-filter button
                  // stays pinned to the right.
                  Expanded(
                    child: showArchived
                        ? const SizedBox.shrink()
                        : _CalendarDateNavigation(
                            mode: mode,
                            selectedDate: selectedDate,
                            onChanged: onDateChanged,
                            showWeekNumber: showWeekNumbers,
                          ),
                  ),
                  // View mode, filters and display options share one button.
                  IconButton(
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: strings.feature('Vy och filter'),
                    onPressed: () => _showCalendarFilterSheet(
                      context: context,
                      mode: mode,
                      onModeChanged: onModeChanged,
                      teams: teams,
                      types: types,
                      teamFilter: teamFilter,
                      eventTypeFilter: eventTypeFilter,
                      showArchived: showArchived,
                      onShowArchivedChanged: onShowArchivedChanged,
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
                          teamFilter != null ||
                          eventTypeFilter != null ||
                          showArchived,
                      smallSize: 8,
                      child: const Icon(Icons.filter_list),
                    ),
                  ),
                ],
              ),
              if (showArchived)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(strings.feature('Arkiverade event')),
                  subtitle: Text(
                    strings.feature(
                      'Historiken är bevarad. Öppna ett event för att visa eller återställa det.',
                    ),
                  ),
                ),
              const Divider(height: 1),
            ],
          ),
        ),
        Expanded(
          child: showArchived
              ? _ArchivedEventList(
                  events: projection.events
                      .where(
                        (event) =>
                            eventTypeFilter == null ||
                            event.type == eventTypeFilter,
                      )
                      .toList(growable: false),
                  onEvent: onEvent,
                )
              : _CalendarSwipe(
                  mode: mode,
                  selectedDate: selectedDate,
                  onDateChanged: onDateChanged,
                  child: _CalendarModeBody(
                    projection: projection,
                    onDate: onDateChanged,
                    onEvent: onEvent,
                    showQuarterHourMarks: showQuarterHourMarks,
                    monthEventScope: monthEventScope,
                    onMonthEventScopeChanged: onMonthEventScopeChanged,
                  ),
                ),
        ),
      ],
    );
  }
}

class _CalendarModeBody extends StatelessWidget {
  const _CalendarModeBody({
    required this.projection,
    required this.onDate,
    required this.onEvent,
    required this.showQuarterHourMarks,
    required this.monthEventScope,
    required this.onMonthEventScopeChanged,
  });

  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<CalendarEventSummary> onEvent;
  final bool showQuarterHourMarks;
  final _MonthEventScope monthEventScope;
  final ValueChanged<_MonthEventScope> onMonthEventScopeChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= AppBreakpoints.tablet;
        final selectedEvents = _CalendarSelectedDayPanel(
          projection: projection,
          onEvent: onEvent,
        );
        final monthEvents = _CalendarMonthEventsPanel(
          projection: projection,
          onEvent: onEvent,
          scope: monthEventScope,
          onScopeChanged: onMonthEventScopeChanged,
        );

        Widget split(Widget primary, Widget secondary) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: primary),
            const VerticalDivider(width: 1),
            Expanded(flex: 2, child: secondary),
          ],
        );

        return switch (projection.mode) {
          CalendarViewMode.month =>
            twoColumns
                ? split(
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _CalendarMonthGrid(
                        projection: projection,
                        onDate: onDate,
                        fillHeight: true,
                      ),
                    ),
                    monthEvents,
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: _CalendarMonthGrid(
                          projection: projection,
                          onDate: onDate,
                        ),
                      ),
                      Expanded(child: monthEvents),
                    ],
                  ),
          CalendarViewMode.week =>
            twoColumns
                ? split(
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _CalendarWeekGrid(
                        projection: projection,
                        onDate: onDate,
                      ),
                    ),
                    selectedEvents,
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: _CalendarWeekGrid(
                            projection: projection,
                            onDate: onDate,
                          ),
                        ),
                      ),
                      Expanded(child: selectedEvents),
                    ],
                  ),
          CalendarViewMode.day =>
            twoColumns
                ? split(
                    _CalendarDayTimeline(
                      date: projection.dayStart,
                      events: projection.visibleEvents,
                      onEvent: onEvent,
                      showQuarterHours: showQuarterHourMarks,
                    ),
                    _CalendarUpcomingAgenda(
                      projection: projection,
                      onDate: onDate,
                      onEvent: onEvent,
                    ),
                  )
                : _CalendarDayTimeline(
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
        };
      },
    );
  }
}

enum _MonthEventScope { selectedDay, wholeMonth }

class _CalendarMonthEventsPanel extends StatelessWidget {
  const _CalendarMonthEventsPanel({
    required this.projection,
    required this.onEvent,
    required this.scope,
    required this.onScopeChanged,
  });

  final CalendarProjection projection;
  final ValueChanged<CalendarEventSummary> onEvent;
  final _MonthEventScope scope;
  final ValueChanged<_MonthEventScope> onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final toggle = _MonthScopeToggle(scope: scope, onChanged: onScopeChanged);
    if (scope == _MonthEventScope.selectedDay) {
      return _CalendarSelectedDayPanel(
        projection: projection,
        onEvent: onEvent,
        trailing: toggle,
      );
    }
    final monthStart = DateTime(
      projection.selectedDate.year,
      projection.selectedDate.month,
    );
    final wholeMonthProjection = CalendarProjection(
      events: projection.events,
      mode: CalendarViewMode.month,
      selectedDate: monthStart,
      teamId: projection.teamId,
      eventType: projection.eventType,
    );
    return ListView(
      key: const Key('calendarMonthEventsPanel'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _CalendarPanelTitle(
          title: MaterialLocalizations.of(context).formatMonthYear(monthStart),
          trailing: toggle,
        ),
        const Divider(),
        if (wholeMonthProjection.visibleEvents.isEmpty)
          _StateCard(
            icon: Icons.event_busy,
            title: strings.feature('Inga event denna månad'),
            message: strings.feature('Byt månad eller justera filtren.'),
          )
        else
          _CalendarAgenda(projection: wholeMonthProjection, onEvent: onEvent),
      ],
    );
  }
}

/// Title row above an event list, with an optional control on the right.
class _CalendarPanelTitle extends StatelessWidget {
  const _CalendarPanelTitle({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

/// Shows the selected day's events or the whole month's under the month grid.
class _MonthScopeToggle extends StatelessWidget {
  const _MonthScopeToggle({required this.scope, required this.onChanged});
  final _MonthEventScope scope;
  final ValueChanged<_MonthEventScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SegmentedButton<_MonthEventScope>(
      key: const Key('calendarMonthScopeToggle'),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -4, vertical: -4),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        minimumSize: WidgetStatePropertyAll(Size(36, 32)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        ButtonSegment(
          value: _MonthEventScope.selectedDay,
          label: Text(strings.feature('Dag')),
          tooltip: strings.feature('Vald dag'),
        ),
        ButtonSegment(
          value: _MonthEventScope.wholeMonth,
          label: Text(strings.feature('Månad')),
          tooltip: strings.feature('Hela månaden'),
        ),
      ],
      selected: {scope},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _CalendarUpcomingAgenda extends StatelessWidget {
  const _CalendarUpcomingAgenda({
    required this.projection,
    required this.onDate,
    required this.onEvent,
  });

  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<CalendarEventSummary> onEvent;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final agenda = CalendarProjection(
      events: projection.events,
      mode: CalendarViewMode.agenda,
      selectedDate: projection.selectedDate,
      teamId: projection.teamId,
      eventType: projection.eventType,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.feature('Kommande event'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (agenda.visibleEvents.isEmpty)
            _StateCard(
              icon: Icons.event_busy,
              title: strings.feature('Inga kommande event'),
              message: strings.feature('Byt datum eller justera filtren.'),
            )
          else
            _CalendarAgenda(
              projection: agenda,
              onEvent: (event) {
                final localStart = event.startsAt.toLocal();
                onDate(
                  DateTime(localStart.year, localStart.month, localStart.day),
                );
                onEvent(event);
              },
            ),
        ],
      ),
    );
  }
}

String _calendarViewModeLabel(CalendarViewMode mode) => switch (mode) {
  CalendarViewMode.agenda => 'Agenda',
  CalendarViewMode.month => 'Månad',
  CalendarViewMode.week => 'Vecka',
  CalendarViewMode.day => 'Dag',
};

class _CalendarDateNavigation extends StatelessWidget {
  const _CalendarDateNavigation({
    required this.mode,
    required this.selectedDate,
    required this.onChanged,
    required this.showWeekNumber,
  });
  final CalendarViewMode mode;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;
  final bool showWeekNumber;
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
    final periodTitle = switch (mode) {
      CalendarViewMode.month =>
        compact
            ? _compactMonthYear(localizations.formatMonthYear(selectedDate))
            : localizations.formatMonthYear(selectedDate),
      CalendarViewMode.week =>
        compact
            ? '${localizations.formatShortMonthDay(weekStart)} – ${localizations.formatShortMonthDay(weekStart.add(const Duration(days: 6)))}'
            : '${localizations.formatMediumDate(weekStart)} – ${localizations.formatMediumDate(weekStart.add(const Duration(days: 6)))}',
      CalendarViewMode.agenda || CalendarViewMode.day =>
        compact
            ? localizations.formatMediumDate(selectedDate)
            : localizations.formatFullDate(selectedDate),
    };
    final title = mode == CalendarViewMode.agenda
        ? strings.calendarFrom(periodTitle)
        : periodTitle;
    DateTime move(int direction) =>
        _calendarStep(mode, selectedDate, direction);
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
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: AppStrings.of(context).feature('Föregående period'),
          onPressed: () => onChanged(move(-1)),
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
        Expanded(
          child: Tooltip(
            message: strings.feature('Välj datum'),
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: mode == CalendarViewMode.agenda
                      ? strings.feature('Välj startdatum för agendan')
                      : strings.feature('Välj datum'),
                );
                if (picked != null) onChanged(picked);
              },
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: AppStrings.of(context).feature('Nästa period'),
          onPressed: () => onChanged(move(1)),
          icon: const Icon(Icons.chevron_right, size: 20),
        ),
        IconButton(
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: AppStrings.of(context).feature('Idag'),
          onPressed: () => onChanged(DateTime.now()),
          icon: const Icon(Icons.today_outlined, size: 20),
        ),
      ],
    );
  }
}

/// The previous (-1) or next (+1) period of a view, shared by the arrows and
/// the horizontal swipe.
DateTime _calendarStep(CalendarViewMode mode, DateTime date, int direction) =>
    switch (mode) {
      CalendarViewMode.month => DateTime(date.year, date.month + direction, 1),
      CalendarViewMode.week => date.add(Duration(days: 7 * direction)),
      CalendarViewMode.agenda ||
      CalendarViewMode.day => date.add(Duration(days: direction)),
    };

/// Swiping sideways over the calendar steps to the next or previous period,
/// like the arrows. Vertical scrolling and horizontal scrollables inside win
/// their own gestures; only a deliberate fling changes the period.
class _CalendarSwipe extends StatelessWidget {
  const _CalendarSwipe({
    required this.mode,
    required this.selectedDate,
    required this.onDateChanged,
    required this.child,
  });
  final CalendarViewMode mode;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final Widget child;

  static const double _minFlingVelocity = 300;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('calendarSwipeArea'),
    behavior: HitTestBehavior.translucent,
    onHorizontalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      if (velocity.abs() < _minFlingVelocity) return;
      // Swiping left (negative velocity) shows the next period.
      onDateChanged(_calendarStep(mode, selectedDate, velocity < 0 ? 1 : -1));
    },
    child: child,
  );
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

/// View mode, filters and display options behind one calendar button.
/// Picking a view applies it and closes the sheet; the other settings apply
/// immediately and the sheet stays open until "Klar".
Future<void> _showCalendarFilterSheet({
  required BuildContext context,
  required CalendarViewMode mode,
  required ValueChanged<CalendarViewMode> onModeChanged,
  required Map<String, String> teams,
  required List<String> types,
  required Set<String>? teamFilter,
  required String? eventTypeFilter,
  required ValueChanged<Set<String>?> onTeamChanged,
  required ValueChanged<String?> onTypeChanged,
  required bool showArchived,
  required ValueChanged<bool> onShowArchivedChanged,
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
      var localShowArchived = showArchived;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.of(sheetContext).feature('Vy och filter'),
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                    // Changes apply immediately; this only closes the sheet.
                    IconButton(
                      key: const Key('calendarFilterClose'),
                      tooltip: AppStrings.of(sheetContext).close,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.of(sheetContext).feature('Vy'),
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  key: const Key('calendarViewModeSelector'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in CalendarViewMode.values)
                      ChoiceChip(
                        label: Text(
                          AppStrings.of(
                            sheetContext,
                          ).feature(_calendarViewModeLabel(value)),
                        ),
                        selected: value == mode,
                        onSelected: (_) {
                          onModeChanged(value);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  AppStrings.of(sheetContext).feature('Lag'),
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                // Several teams can be shown at once; with none picked, or
                // all of them, every team is shown.
                Wrap(
                  key: const Key('calendarTeamFilter'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text(
                        AppStrings.of(sheetContext).feature('Alla lag'),
                      ),
                      selected: localTeam == null,
                      onSelected: (_) {
                        setSheetState(() => localTeam = null);
                        onTeamChanged(null);
                      },
                    ),
                    for (final entry in teams.entries)
                      FilterChip(
                        label: Text(
                          entry.value,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: localTeam?.contains(entry.key) ?? false,
                        onSelected: (selected) {
                          final next = {...?localTeam};
                          selected
                              ? next.add(entry.key)
                              : next.remove(entry.key);
                          final value =
                              next.isEmpty ||
                                  next.containsAll(teams.keys.toSet())
                              ? null
                              : next;
                          setSheetState(() => localTeam = value);
                          onTeamChanged(value);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
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
                    AppStrings.of(
                      sheetContext,
                    ).feature('Visa arkiverade event'),
                  ),
                  subtitle: Text(
                    AppStrings.of(sheetContext).feature(
                      'Döljer aktiva event och visar den bevarade historiken.',
                    ),
                  ),
                  value: localShowArchived,
                  onChanged: (value) {
                    setSheetState(() => localShowArchived = value);
                    onShowArchivedChanged(value);
                  },
                ),
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
                    AppStrings.of(
                      sheetContext,
                    ).feature('Visa kvartsmarkeringar'),
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
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ArchivedEventList extends StatelessWidget {
  const _ArchivedEventList({required this.events, required this.onEvent});

  final List<CalendarEventSummary> events;
  final ValueChanged<CalendarEventSummary> onEvent;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (events.isEmpty) {
      return Center(
        child: _StateCard(
          icon: Icons.archive_outlined,
          title: strings.feature('Inga arkiverade event'),
          message: strings.feature(
            'Arkiverade event för det valda laget visas här.',
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = events[index];
        final archivedAt = event.archivedAt?.toLocal();
        return Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(
              event.title,
              style: const TextStyle(decoration: TextDecoration.lineThrough),
            ),
            subtitle: Text(
              <String?>[
                event.teamName,
                strings.domainValue(event.state),
                archivedAt == null
                    ? null
                    : '${strings.feature('Arkiverad')} ${MaterialLocalizations.of(context).formatShortDate(archivedAt)}',
                event.archiveReason,
              ].whereType<String>().join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onEvent(event),
          ),
        );
      },
    );
  }
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

  /// The day view opens at the afternoon, when most team activities are.
  static const int initialHour = 15;

  @override
  State<_CalendarDayTimeline> createState() => _CalendarDayTimelineState();
}

class _CalendarDayTimelineState extends State<_CalendarDayTimeline> {
  static const double _hourHeight = 64;
  static const double _labelWidth = 44;
  static const double _minCardHeight = 34;

  // Kept while swiping between days, so a chosen position is not lost.
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _CalendarDayTimeline.initialHour * _hourHeight,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    final events = widget.events;
    final onEvent = widget.onEvent;
    final showQuarterHours = widget.showQuarterHours;
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
            key: const Key('calendarDayTimelineScroll'),
            controller: _scroll,
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
    final cancelled = event.state == 'cancelled';
    return Opacity(
      opacity: cancelled ? 0.68 : 1,
      child: Material(
        color: cancelled
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
                    Icon(
                      cancelled ? Icons.event_busy : _eventTypeIcon(event.type),
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    if (event.isShared) ...[
                      _sharedEventMarker(context, 13),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        _abbreviateHomeAwaySuffix(event.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: cancelled
                                  ? TextDecoration.lineThrough
                                  : null,
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
    final cancelled = event.state == 'cancelled';
    return Opacity(
      opacity: cancelled ? 0.68 : 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: cancelled
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  cancelled ? Icons.event_busy : _eventTypeIcon(event.type),
                  size: 11,
                ),
                const SizedBox(width: 3),
                if (event.isShared) ...[
                  _sharedEventMarker(context, 11),
                  const SizedBox(width: 3),
                ],
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
                decoration: cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
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
  const _CalendarMonthGrid({
    required this.projection,
    required this.onDate,
    this.fillHeight = false,
  });
  final CalendarProjection projection;
  final ValueChanged<DateTime> onDate;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final first = projection.rangeStart;
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final selected = projection.selectedDate;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        final cellHeight = constraints.maxHeight / 6;
        final aspectRatio = fillHeight && cellHeight > 0
            ? cellWidth / cellHeight
            : MediaQuery.sizeOf(context).width >= 600
            ? 1.7
            : 1.3;
        return GridView.builder(
          shrinkWrap: !fillHeight,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: aspectRatio,
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
    this.trailing,
  });
  final CalendarProjection projection;
  final ValueChanged<CalendarEventSummary> onEvent;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final selected = projection.selectedDate;
    final dayEvents = projection.eventsOn(selected);
    return ListView(
      key: const Key('calendarSelectedDayPanel'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _CalendarPanelTitle(
          title: MaterialLocalizations.of(context).formatFullDate(selected),
          trailing: trailing,
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
    final cancelled = event.state == 'cancelled';
    return ColoredBox(
      color: cancelled
          ? Theme.of(context).colorScheme.surfaceContainerLowest
          : Colors.transparent,
      child: Opacity(
        opacity: cancelled ? 0.68 : 1,
        child: ListTile(
          leading: Icon(cancelled ? Icons.event_busy : Icons.event),
          title: Text(
            event.title,
            style: TextStyle(
              decoration: cancelled ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(
            '$time · ${event.teamName} · ${strings.domainValue(event.type)}${event.locationName == null ? '' : ' · ${event.locationName}'}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (event.isShared) ...[
                _sharedEventMarker(context, 20),
                const SizedBox(width: 8),
              ],
              if (cancelled)
                Chip(
                  avatar: const Icon(Icons.event_busy, size: 16),
                  label: Text(strings.domainValue(event.state)),
                  visualDensity: VisualDensity.compact,
                )
              // Planned events are the normal case and carry no label; a
              // draft is marked so it isn't mistaken for a published event.
              else if (event.state == 'draft')
                _draftEventMarker(context, 20),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

Widget _draftEventMarker(BuildContext context, double size) => Tooltip(
  key: const Key('calendarDraftMarker'),
  message: AppStrings.of(context).domainValue('draft'),
  child: Icon(
    Icons.edit_note,
    size: size,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
);

Widget _sharedEventMarker(BuildContext context, double size) => Tooltip(
  message: AppStrings.of(context).feature('Delat event'),
  child: Icon(Icons.share_outlined, size: size),
);

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
    this.locationPitch,
    this.locationSurface,
    this.trainingTheme,
    this.trainingFocus,
    this.trainingPlan,
    this.opponentName,
    this.homeAway,
    this.matchNotes,
    this.meetingPurpose,
    this.meetingAgenda,
    required this.assemblyMinutesBefore,
  });
  final String title, type, state, timezone, frequency, scope;
  final String? description, locationName, locationPitch, locationSurface;
  final DateTime startsAt, endsAt;
  final bool allDay, recurring;
  final List<String> audiences;
  final int interval, count;
  final int assemblyMinutesBefore;
  final String? trainingTheme, trainingFocus, trainingPlan;
  final String? opponentName, homeAway, matchNotes;
  final String? meetingPurpose, meetingAgenda;
}

class _EventEditorDialog extends StatefulWidget {
  const _EventEditorDialog({
    required this.teamName,
    required this.locationSuggestions,
    this.initial,
    this.initialType,
  });
  final String teamName;
  final List<SavedEventPlace> locationSuggestions;
  final EventDetails? initial;

  /// Preselected type for a new event, e.g. from the quick actions sheet.
  final String? initialType;
  @override
  State<_EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<_EventEditorDialog> {
  final _draft = AppFormController();
  late final TextEditingController _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.initial?.locationName,
  );
  late final TextEditingController _pitch = TextEditingController(
    text: widget.initial?.locationPitch,
  );
  late final TextEditingController _surface = TextEditingController(
    text: widget.initial?.locationSurface,
  );
  late final TextEditingController _timezone = TextEditingController(
    text: widget.initial?.timezone ?? 'Europe/Stockholm',
  );
  late final TextEditingController _interval = TextEditingController(text: '1');
  late String _type = widget.initial?.type ?? widget.initialType ?? 'training';
  late final TextEditingController _assembly = TextEditingController(
    text: (widget.initial?.assemblyMinutesBefore ?? _defaultAssembly(_type))
        .toString(),
  );
  late final TextEditingController _trainingTheme = TextEditingController(
    text: widget.initial?.trainingTheme,
  );
  late final TextEditingController _trainingFocus = TextEditingController(
    text: widget.initial?.trainingFocus,
  );
  late final TextEditingController _trainingPlan = TextEditingController(
    text: widget.initial?.trainingPlan,
  );
  late final TextEditingController _opponent = TextEditingController(
    text: widget.initial?.opponentName,
  );
  late final TextEditingController _matchNotes = TextEditingController(
    text: widget.initial?.matchNotes,
  );
  late final TextEditingController _meetingPurpose = TextEditingController(
    text: widget.initial?.meetingPurpose,
  );
  late final TextEditingController _meetingAgenda = TextEditingController(
    text: widget.initial?.meetingAgenda,
  );
  late String _homeAway = widget.initial?.homeAway ?? 'home';
  late String _state = widget.initial?.state ?? 'scheduled';
  late DateTime _startsAt =
      widget.initial?.startsAt.toLocal() ?? _defaultStart();
  late DateTime _endsAt =
      widget.initial?.endsAt.toLocal() ??
      _defaultStart().add(const Duration(hours: 2));
  late DateTime _seriesEndsOn = DateUtils.dateOnly(
    _startsAt.add(const Duration(days: 28)),
  );
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
  bool _assemblyWasEdited = false;

  static int _defaultAssembly(String type) => switch (type) {
    'match' => 75,
    'meeting' => 5,
    _ => 15,
  };

  static DateTime _defaultStart() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18);
  }

  @override
  void initState() {
    super.initState();
    if (_audiences.isEmpty) _audiences.addAll({'players', 'leaders'});
    for (final controller in [
      _description,
      _location,
      _pitch,
      _surface,
      _timezone,
      _interval,
      _trainingTheme,
      _trainingFocus,
      _trainingPlan,
      _opponent,
      _matchNotes,
      _meetingPurpose,
      _meetingAgenda,
    ]) {
      controller.addListener(_draft.markDirty);
    }
    _assembly.addListener(_assemblyChanged);
  }

  void _assemblyChanged() {
    _assemblyWasEdited = true;
    _draft.markDirty();
  }

  @override
  void dispose() {
    for (final controller in [
      _description,
      _location,
      _pitch,
      _surface,
      _timezone,
      _interval,
      _trainingTheme,
      _trainingFocus,
      _trainingPlan,
      _opponent,
      _matchNotes,
      _meetingPurpose,
      _meetingAgenda,
    ]) {
      controller.removeListener(_draft.markDirty);
      controller.dispose();
    }
    _assembly.removeListener(_assemblyChanged);
    _assembly.dispose();
    _draft.dispose();
    super.dispose();
  }

  void _save() {
    final interval = int.tryParse(_interval.text);
    final count = interval == null ? null : _seriesCount(interval);
    final assembly = int.tryParse(_assembly.text);
    final generatedTitle = _generatedTitle();
    final problem = _validationError(AppStrings.of(context));
    if (problem != null || assembly == null) {
      setState(() => _error = problem);
      return;
    }
    _draft.markClean();
    Navigator.pop(
      context,
      _EventEditorValue(
        title: generatedTitle,
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
        // Pitch and surface only belong with a facility.
        locationPitch: _location.text.trim().isEmpty ? null : _optional(_pitch),
        locationSurface: _location.text.trim().isEmpty
            ? null
            : _optional(_surface),
        recurring: _recurring,
        frequency: _frequency,
        interval: interval ?? 1,
        count: count ?? 4,
        scope: _scope,
        assemblyMinutesBefore: assembly,
        trainingTheme: _optional(_trainingTheme),
        trainingFocus: _optional(_trainingFocus),
        trainingPlan: _optional(_trainingPlan),
        opponentName: _optional(_opponent),
        homeAway: _type == 'match' ? _homeAway : null,
        matchNotes: _optional(_matchNotes),
        meetingPurpose: _optional(_meetingPurpose),
        meetingAgenda: _optional(_meetingAgenda),
      ),
    );
  }

  int _seriesCount(int interval) {
    final start = DateUtils.dateOnly(_startsAt);
    final stepDays = (_frequency == 'daily' ? 1 : 7) * interval;
    if (_seriesEndsOn.isBefore(start) || stepDays < 1) return 0;
    return _seriesEndsOn.difference(start).inDays ~/ stepDays + 1;
  }

  Future<void> _pickSeriesEnd() async {
    final firstDate = DateUtils.dateOnly(_startsAt);
    final picked = await showDatePicker(
      context: context,
      initialDate: _seriesEndsOn.isBefore(firstDate)
          ? firstDate
          : _seriesEndsOn,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    setState(() {
      _seriesEndsOn = DateUtils.dateOnly(picked);
      _draft.markDirty();
    });
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  String _generatedTitle() => switch (_type) {
    'training' => 'Träning',
    'match' => 'vs ${_opponent.text.trim()}',
    'meeting' => 'Möte',
    _ => 'Aktivitet',
  };

  static const _typeIcons = {
    'training': Icons.fitness_center,
    'match': Icons.sports_soccer,
    'meeting': Icons.groups_outlined,
    'activity': Icons.event_outlined,
  };

  /// Type-specific details: what the event is about.
  List<Widget> _typedFields(AppStrings strings) => switch (_type) {
    'training' => [
      TextFormField(
        controller: _trainingTheme,
        maxLength: 160,
        decoration: InputDecoration(labelText: strings.feature('Träningstema')),
      ),
      TextFormField(
        controller: _trainingFocus,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: strings.feature('Fokus')),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _trainingPlan,
        minLines: 3,
        maxLines: 8,
        decoration: InputDecoration(labelText: strings.feature('Träningsplan')),
      ),
    ],
    'match' => [
      TextFormField(
        controller: _matchNotes,
        minLines: 2,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: strings.feature('Matchanteckningar'),
        ),
      ),
    ],
    'meeting' => [
      TextFormField(
        controller: _meetingPurpose,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(labelText: strings.feature('Syfte')),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _meetingAgenda,
        minLines: 3,
        maxLines: 8,
        decoration: InputDecoration(labelText: strings.feature('Mötesagenda')),
      ),
    ],
    _ => const [],
  };

  /// First problem with the form, in plain words, or null when it is valid.
  String? _validationError(AppStrings strings) {
    final interval = int.tryParse(_interval.text);
    final count = interval == null ? null : _seriesCount(interval);
    final assembly = int.tryParse(_assembly.text);
    if (_type == 'match' && _opponent.text.trim().isEmpty) {
      return strings.feature('Ange motståndare.');
    }
    if (_generatedTitle().length > 160) {
      return strings.feature('Motståndarens namn är för långt.');
    }
    if (!_endsAt.isAfter(_startsAt)) {
      return strings.feature('Sluttiden måste vara efter starttiden.');
    }
    if (assembly == null || assembly < 0 || assembly > 1440) {
      return strings.feature('Samlingen ska vara 0–1440 minuter före start.');
    }
    if (_location.text.trim().isEmpty &&
        (_pitch.text.trim().isNotEmpty || _surface.text.trim().isNotEmpty)) {
      return strings.feature('Ange anläggning för planen och underlaget.');
    }
    if (_audiences.isEmpty) return strings.feature('Välj minst en målgrupp.');
    if (_timezone.text.trim().isEmpty) {
      return strings.feature('Ange en tidszon.');
    }
    if (_recurring &&
        (interval == null ||
            interval < 1 ||
            interval > 52 ||
            count == null ||
            count < 2 ||
            count > 104)) {
      return strings.feature(
        'Kontrollera serien: 2–104 tillfällen och ett intervall på 1–52.',
      );
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final duration = _endsAt.difference(_startsAt);
      _startsAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startsAt.hour,
        _startsAt.minute,
      );
      _endsAt = _startsAt.add(duration);
      if (_seriesEndsOn.isBefore(DateUtils.dateOnly(_startsAt))) {
        _seriesEndsOn = DateUtils.dateOnly(
          _startsAt.add(const Duration(days: 28)),
        );
      }
      _draft.markDirty();
    });
  }

  Future<void> _pickEndDate() async {
    final first = DateUtils.dateOnly(_startsAt);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endsAt.isBefore(first) ? first : _endsAt,
      firstDate: first,
      lastDate: first.add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _endsAt = DateTime(picked.year, picked.month, picked.day);
      if (!_endsAt.isAfter(_startsAt)) {
        _endsAt = _startsAt.add(const Duration(days: 1));
      }
      _draft.markDirty();
    });
  }

  /// Start keeps the length; end on the same day, or the next when it is
  /// earlier than the start (an evening event past midnight).
  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start ? _startsAt : _endsAt),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        final duration = _endsAt.difference(_startsAt);
        _startsAt = DateTime(
          _startsAt.year,
          _startsAt.month,
          _startsAt.day,
          picked.hour,
          picked.minute,
        );
        _endsAt = _startsAt.add(duration);
      } else {
        var end = DateTime(
          _startsAt.year,
          _startsAt.month,
          _startsAt.day,
          picked.hour,
          picked.minute,
        );
        if (!end.isAfter(_startsAt)) end = end.add(const Duration(days: 1));
        _endsAt = end;
      }
      _draft.markDirty();
    });
  }

  Widget _section(
    BuildContext context,
    IconData icon,
    String title,
    List<Widget> children,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  /// An outlined field that opens a picker.
  Widget _pickerField({
    required Key key,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(icon, size: 20),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _whenFields(AppStrings strings) {
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime value) =>
        TimeOfDay.fromDateTime(value).format(context);
    final nextDay = !DateUtils.isSameDay(_startsAt, _endsAt);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 440;
        if (_allDay) {
          final from = _pickerField(
            key: const ValueKey('event-date'),
            label: strings.feature('Från'),
            value: localizations.formatMediumDate(_startsAt),
            icon: Icons.calendar_today_outlined,
            onTap: _pickDate,
          );
          final to = _pickerField(
            key: const ValueKey('event-end-date'),
            label: strings.feature('Till'),
            value: localizations.formatMediumDate(_endsAt),
            icon: Icons.calendar_today_outlined,
            onTap: _pickEndDate,
          );
          return Row(
            children: [
              Expanded(child: from),
              const SizedBox(width: 12),
              Expanded(child: to),
            ],
          );
        }
        final date = _pickerField(
          key: const ValueKey('event-date'),
          label: strings.feature('Datum'),
          value: localizations.formatMediumDate(_startsAt),
          icon: Icons.calendar_today_outlined,
          onTap: _pickDate,
        );
        final times = Row(
          children: [
            Expanded(
              child: _pickerField(
                key: const ValueKey('event-start-time'),
                label: strings.feature('Start'),
                value: time(_startsAt),
                icon: Icons.schedule,
                onTap: () => _pickTime(start: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _pickerField(
                key: const ValueKey('event-end-time'),
                label: strings.feature('Slut'),
                value: nextDay ? '${time(_endsAt)} (+1)' : time(_endsAt),
                icon: Icons.schedule,
                onTap: () => _pickTime(start: false),
              ),
            ),
          ],
        );
        return wide
            ? Row(
                children: [
                  Expanded(flex: 5, child: date),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: times),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [date, const SizedBox(height: 12), times],
              );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final creating = widget.initial == null;
    final fullScreen = MediaQuery.sizeOf(context).width < 600;
    final assembly = int.tryParse(_assembly.text);
    final assemblyAt = assembly == null || _allDay
        ? null
        : _startsAt.subtract(Duration(minutes: assembly));

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: strings.feature('Stäng'),
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.feature(creating ? 'Skapa event' : 'Redigera event'),
                  style: theme.textTheme.titleLarge,
                ),
                Text(widget.teamName, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          FilledButton(
            onPressed: _save,
            child: Text(strings.feature(creating ? 'Skapa' : 'Spara')),
          ),
        ],
      ),
    );

    final form = ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        // What
        _section(
          context,
          Icons.category_outlined,
          strings.feature('Typ av event'),
          [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in _typeIcons.keys)
                  ChoiceChip(
                    key: ValueKey('event-type-$value'),
                    avatar: Icon(_typeIcons[value], size: 18),
                    label: Text(strings.domainValue(value)),
                    selected: _type == value,
                    onSelected: (_) => setState(() {
                      if (!_assemblyWasEdited) {
                        _assembly.text = _defaultAssembly(value).toString();
                        _assemblyWasEdited = false;
                      }
                      _type = value;
                      _error = null;
                      _draft.markDirty();
                    }),
                  ),
              ],
            ),
            if (_type == 'match') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _opponent,
                maxLength: 157,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: strings.feature('Motståndare *'),
                  prefixIcon: const Icon(Icons.shield_outlined),
                ),
              ),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'home',
                    icon: const Icon(Icons.home_outlined),
                    label: Text(strings.feature('Hemma')),
                  ),
                  ButtonSegment(
                    value: 'away',
                    icon: const Icon(Icons.directions_bus_outlined),
                    label: Text(strings.feature('Borta')),
                  ),
                ],
                selected: {_homeAway},
                onSelectionChanged: (value) => setState(() {
                  _homeAway = value.single;
                  _draft.markDirty();
                }),
              ),
            ],
          ],
        ),
        // When
        _section(context, Icons.event_outlined, strings.feature('När'), [
          _whenFields(strings),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
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
                _endsAt = DateTime(_endsAt.year, _endsAt.month, _endsAt.day);
                if (!_endsAt.isAfter(_startsAt)) {
                  _endsAt = _startsAt.add(const Duration(days: 1));
                }
              } else {
                _startsAt = DateTime(
                  _startsAt.year,
                  _startsAt.month,
                  _startsAt.day,
                  18,
                );
                _endsAt = _startsAt.add(const Duration(hours: 2));
              }
              _draft.markDirty();
            }),
          ),
          if (!_allDay)
            TextFormField(
              controller: _assembly,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: strings.feature('Samling före start (minuter)'),
                prefixIcon: const Icon(Icons.flag_outlined),
                suffixText: 'min',
                helperText: assemblyAt == null
                    ? null
                    : '${strings.feature('Samling kl.')} ${TimeOfDay.fromDateTime(assemblyAt).format(context)}',
              ),
              onChanged: (_) => setState(() {}),
            ),
          if (creating) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(strings.feature('Återkommande serie')),
              subtitle: Text(
                strings.feature('Skapar ett event per tillfälle.'),
              ),
              value: _recurring,
              onChanged: (value) => setState(() {
                _recurring = value;
                _draft.markDirty();
              }),
            ),
            if (_recurring) _seriesFields(strings),
          ],
          if (widget.initial?.recurrenceId != null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _scope,
              decoration: InputDecoration(labelText: strings.feature('Ändra')),
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
          ],
        ]),
        // Where
        _section(context, Icons.place_outlined, strings.feature('Plats'), [
          if (widget.locationSuggestions.isNotEmpty) ...[
            // Earlier places, picked as a whole (facility, pitch, surface).
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final place in widget.locationSuggestions.take(8))
                  ActionChip(
                    key: ValueKey('saved-place-${place.label}'),
                    avatar: const Icon(Icons.history, size: 16),
                    label: Text(place.label),
                    onPressed: () => setState(() {
                      _location.text = place.name;
                      _pitch.text = place.pitch ?? '';
                      _surface.text = place.surface ?? '';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            key: const ValueKey('event-place-facility'),
            controller: _location,
            maxLength: 160,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: strings.feature('Anläggning'),
              hintText: strings.feature('T.ex. Bergby IP'),
              prefixIcon: const Icon(Icons.stadium_outlined),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('event-place-pitch'),
                  controller: _pitch,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: strings.feature('Plan (valfritt)'),
                    hintText: strings.feature('T.ex. Plan 3'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('event-place-surface'),
                  controller: _surface,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: strings.feature('Underlag (valfritt)'),
                    hintText: strings.feature('T.ex. konstgräs'),
                  ),
                ),
              ),
            ],
          ),
        ]),
        // Who
        _section(context, Icons.people_outline, strings.feature('Målgrupp'), [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in ['players', 'leaders', 'guardians', 'club'])
                FilterChip(
                  label: Text(strings.domainValue(value)),
                  selected: _audiences.contains(value),
                  onSelected: (selected) => setState(() {
                    selected ? _audiences.add(value) : _audiences.remove(value);
                    _draft.markDirty();
                  }),
                ),
            ],
          ),
        ]),
        // Details
        _section(context, Icons.notes_outlined, strings.feature('Detaljer'), [
          ..._typedFields(strings),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: strings.feature('Beskrivning'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (creating)
          SwitchListTile(
            key: const ValueKey('event-save-as-draft'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.edit_note_outlined),
            title: Text(strings.feature('Spara som utkast')),
            subtitle: Text(
              strings.feature('Planeras klart och publiceras senare.'),
            ),
            value: _state == 'draft',
            onChanged: (value) => setState(() {
              _state = value ? 'draft' : 'scheduled';
              _draft.markDirty();
            }),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(strings.feature('Fler inställningar')),
          children: [
            TextFormField(
              controller: _timezone,
              decoration: InputDecoration(
                labelText: strings.feature('Tidszon'),
              ),
            ),
          ],
        ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1),
        if (_error != null)
          Material(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: form),
      ],
    );

    return AppUnsavedChangesScope(
      controller: _draft,
      title: strings.feature('Kasta ändringar?'),
      message: strings.feature('Dina osparade ändringar går förlorade.'),
      discardLabel: strings.feature('Kasta'),
      cancelLabel: strings.feature('Fortsätt redigera'),
      child: fullScreen
          ? Dialog.fullscreen(child: SafeArea(child: body))
          : Dialog(
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 600,
                  maxHeight: MediaQuery.sizeOf(context).height * .9,
                ),
                child: body,
              ),
            ),
    );
  }

  Widget _seriesFields(AppStrings strings) {
    final interval = int.tryParse(_interval.text);
    final count = interval == null ? null : _seriesCount(interval);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _interval,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.feature('Varje'),
                  suffixText: strings.feature(
                    _frequency == 'daily' ? 'dag' : 'vecka',
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _pickerField(
          key: const ValueKey('event-series-end'),
          label: strings.feature('Serien slutar'),
          value: MaterialLocalizations.of(
            context,
          ).formatMediumDate(_seriesEndsOn),
          icon: Icons.event_repeat_outlined,
          onTap: _pickSeriesEnd,
        ),
        if (count != null && count > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              strings
                  .feature('{count} tillfällen')
                  .replaceFirst('{count}', '$count'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _CalendarSurfaceState extends State<_CalendarSurface>
    with WidgetsBindingObserver {
  late final AsyncDataController<List<CalendarEventSummary>> _data;
  StreamSubscription<CalendarSyncEvent>? _invalidationSubscription;
  Timer? _invalidationDebounce;
  // Falls back to month view until (if) a stored default overrides it --
  // see _loadDefaultViewMode.
  CalendarViewMode _viewMode = CalendarViewMode.month;
  _MonthEventScope _monthEventScope = _MonthEventScope.selectedDay;
  DateTime _selectedDate = DateTime.now();
  // The loaded date window follows the selected date (see _reload and
  // _changeDate) instead of being fixed around today.
  late DateTime _windowAnchor = _selectedDate;
  Set<String>? _teamFilter;
  String? _eventTypeFilter;
  bool _showArchived = false;
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
    _teamFilter = _initialTeamFilter;
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
    unawaited(_loadDefaultViewMode());
  }

  Future<void> _loadDefaultViewMode() async {
    final stored = await widget.calendarPreferences.readDefaultViewMode();
    if (stored == null || !mounted) return;
    for (final value in CalendarViewMode.values) {
      if (value.name == stored) {
        setState(() => _viewMode = value);
        return;
      }
    }
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
  // Only the editor's own types; anything else falls back to its default.
  String? get _allowedInitialType =>
      const {
        'training',
        'match',
        'meeting',
        'activity',
      }.contains(widget.initialEventType)
      ? widget.initialEventType
      : null;

  void _openInitialAction() {
    if (widget.initialAction != 'create' || _openedInitialAction) return;
    final canCreate =
        widget.contextValue.teamId != null &&
        widget.contextValue.can('event.manage');
    if (!canCreate) return;
    _openedInitialAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_createEvent(type: _allowedInitialType));
    });
  }

  /// The active team to start with; a club-level context shows all teams.
  Set<String>? get _initialTeamFilter {
    final teamId = widget.contextValue.teamId;
    return teamId == null ? null : {teamId};
  }

  String get _scopeKey {
    final ids = widget.contexts.map((item) => item.id).toList()..sort();
    final teams = _teamFilter == null
        ? 'all'
        : (_teamFilter!.toList()..sort()).join('+');
    return '${widget.contextValue.id}:$teams:${_showArchived ? 'archived' : 'active'}:${ids.join(',')}';
  }

  List<String> get _filteredContextIds {
    final teamIds = _teamFilter;
    return widget.contexts
        .where((item) => teamIds == null || teamIds.contains(item.teamId))
        .map((item) => item.id)
        .toList(growable: false);
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
      _teamFilter = _initialTeamFilter;
      _data.replaceScope(scopeKey: _scopeKey, loader: _reload);
      _listenForInvalidations();
    }
    if (oldWidget.initialAction != widget.initialAction ||
        oldWidget.initialEventType != widget.initialEventType) {
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
    if (_showArchived) {
      return widget.calendar.listArchivedEvents(
        contextIds: _filteredContextIds,
      );
    }
    return widget.calendar.listCalendar(
      contextIds: _filteredContextIds,
      from: _windowFrom(_windowAnchor),
      to: _windowTo(_windowAnchor),
    );
  }

  // From the month before the anchor, so a month grid's leading days from
  // the previous month have their events, to eleven months ahead.
  static DateTime _windowFrom(DateTime anchor) =>
      DateTime(anchor.year, anchor.month - 1);
  static DateTime _windowTo(DateTime anchor) =>
      DateTime(anchor.year, anchor.month + 11);

  /// Selects a date and reloads around it once any visible day (a month
  /// grid reaches up to a week into the neighbouring months) falls outside
  /// the loaded window. Shown events stay visible while reloading.
  void _changeDate(DateTime value) {
    final needFrom = DateTime(
      value.year,
      value.month,
    ).subtract(const Duration(days: 7));
    final needTo = DateTime(value.year, value.month + 2);
    final outside =
        needFrom.isBefore(_windowFrom(_windowAnchor)) ||
        needTo.isAfter(_windowTo(_windowAnchor));
    setState(() {
      _selectedDate = value;
      if (outside) _windowAnchor = value;
    });
    if (outside && !_showArchived) unawaited(_data.refresh());
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

  Future<void> _createEvent({String? type}) async {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) return;
    List<SavedEventPlace> suggestions;
    try {
      suggestions = await widget.calendar.listSavedPlaces(
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
        initialType: type,
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
          locationPitch: value.locationPitch,
          locationSurface: value.locationSurface,
          recurrenceFrequency: value.recurring ? value.frequency : null,
          recurrenceInterval: value.recurring ? value.interval : null,
          recurrenceCount: value.recurring ? value.count : null,
          assemblyMinutesBefore: value.assemblyMinutesBefore,
          trainingTheme: value.trainingTheme,
          trainingFocus: value.trainingFocus,
          trainingPlan: value.trainingPlan,
          opponentName: value.opponentName,
          homeAway: value.homeAway,
          matchNotes: value.matchNotes,
          meetingPurpose: value.meetingPurpose,
          meetingAgenda: value.meetingAgenda,
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
      floatingActionButtonLocation: _assistantUsesFab(context)
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
              teams: {
                for (final item in widget.contexts)
                  if (item.teamId != null && item.teamName != null)
                    item.teamId!: item.teamName!,
              },
              mode: _viewMode,
              selectedDate: _selectedDate,
              teamFilter: _teamFilter,
              eventTypeFilter: _eventTypeFilter,
              showArchived: _showArchived,
              stale: state.isStale && !_staleBannerDismissed,
              reconnecting:
                  state.connection == AppConnectionStatus.reconnecting,
              lastUpdated: state.lastUpdated,
              onDismissStale: () =>
                  setState(() => _staleBannerDismissed = true),
              onModeChanged: (value) => setState(() => _viewMode = value),
              onDateChanged: _changeDate,
              onTeamChanged: (value) {
                if (setEquals(value, _teamFilter)) return;
                setState(() => _teamFilter = value);
                _data.replaceScope(scopeKey: _scopeKey, loader: _reload);
              },
              onTypeChanged: (value) =>
                  setState(() => _eventTypeFilter = value),
              onShowArchivedChanged: (value) {
                if (value == _showArchived) return;
                setState(() => _showArchived = value);
                _data.replaceScope(scopeKey: _scopeKey, loader: _reload);
              },
              onEvent: _showDetails,
              showWeekNumbers: _showWeekNumbers,
              onShowWeekNumbersChanged: _setShowWeekNumbers,
              showQuarterHourMarks: _showQuarterHourMarks,
              onShowQuarterHourMarksChanged: _setShowQuarterHourMarks,
              monthEventScope: _monthEventScope,
              onMonthEventScopeChanged: (value) =>
                  setState(() => _monthEventScope = value),
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
