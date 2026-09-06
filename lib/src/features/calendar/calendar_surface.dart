part of '../../app/teamzone_app.dart';

class _CalendarSurface extends StatefulWidget {
  const _CalendarSurface({
    required this.contextValue,
    required this.contexts,
    required this.calendar,
    required this.match,
    required this.onNavigate,
    required this.matchSpaceV2,
    this.initialEventId,
  });

  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final CalendarServices calendar;
  final MatchServices match;
  final ValueChanged<String> onNavigate;
  final bool matchSpaceV2;
  final String? initialEventId;

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
    this.teamFilter,
    this.eventTypeFilter,
    this.lastUpdated,
  });
  final List<CalendarEventSummary> events;
  final CalendarViewMode mode;
  final DateTime selectedDate;
  final String? teamFilter, eventTypeFilter;
  final bool stale, reconnecting, showWeekNumbers;
  final DateTime? lastUpdated;
  final ValueChanged<CalendarViewMode> onModeChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String?> onTeamChanged, onTypeChanged;
  final ValueChanged<CalendarEventSummary> onEvent;
  final ValueChanged<bool> onShowWeekNumbersChanged;

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
        Expanded(
          child: mode == CalendarViewMode.month
              ? _CalendarMonthDayPanel(projection: projection, onEvent: onEvent)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: projection.visibleEvents.isEmpty
                      ? _StateCard(
                          icon: Icons.event_busy,
                          title: strings.feature('Inga event i vald vy'),
                          message: strings.feature(
                            'Byt datum eller justera filtren.',
                          ),
                        )
                      : switch (mode) {
                          CalendarViewMode.agenda => _CalendarAgenda(
                            projection: projection,
                            onEvent: onEvent,
                          ),
                          CalendarViewMode.week => _CalendarWeek(
                            projection: projection,
                            onEvent: onEvent,
                          ),
                          CalendarViewMode.day => _CalendarDay(
                            date: projection.dayStart,
                            events: projection.visibleEvents,
                            onEvent: onEvent,
                          ),
                          CalendarViewMode.month => const SizedBox.shrink(),
                        },
                ),
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
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      var localTeam = teamFilter;
      var localType = eventTypeFilter;
      var localShowWeekNumbers = showWeekNumbers;
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

class _CalendarWeek extends StatelessWidget {
  const _CalendarWeek({required this.projection, required this.onEvent});
  final CalendarProjection projection;
  final ValueChanged<CalendarEventSummary> onEvent;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final days = [
        for (var offset = 0; offset < 7; offset++)
          projection.weekStart.add(Duration(days: offset)),
      ];
      if (constraints.maxWidth < 840) {
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
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final day in days)
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _CalendarDay(
                    date: day,
                    events: projection.eventsOn(day),
                    onEvent: onEvent,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
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
    final colorScheme = Theme.of(context).colorScheme;
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
        final items = projection.eventsOn(day);
        final inMonth = day.month == projection.selectedDate.month;
        final isSelected =
            day.year == selected.year &&
            day.month == selected.month &&
            day.day == selected.day;
        return InkWell(
          onTap: () => onDate(day),
          child: Card(
            color: inMonth ? null : colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? BorderSide(color: colorScheme.primary, width: 2)
                  : BorderSide.none,
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('${day.day}'),
                ),
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
            ),
          ),
        );
      },
    );
  }
}

class _CalendarMonthDayPanel extends StatelessWidget {
  const _CalendarMonthDayPanel({
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
      key: const Key('calendarMonthDayPanel'),
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

class _EventDetailsPanel extends StatefulWidget {
  const _EventDetailsPanel({
    required this.event,
    required this.calendar,
    required this.matchSpaceV2,
    required this.onParticipants,
    required this.onMatchSpace,
    required this.onEdit,
    required this.onShare,
    required this.onPublish,
    required this.onRestore,
    required this.onCancel,
    required this.onDelete,
    required this.onArchive,
    required this.onComplete,
  });

  final EventDetails event;
  final CalendarServices calendar;
  final bool matchSpaceV2;
  final Future<void> Function() onParticipants,
      onMatchSpace,
      onEdit,
      onShare,
      onPublish,
      onRestore,
      onCancel,
      onDelete,
      onArchive,
      onComplete;

  @override
  State<_EventDetailsPanel> createState() => _EventDetailsPanelState();
}

class _EventDetailsPanelState extends State<_EventDetailsPanel> {
  late final Future<SquadDetails> _squad = widget.calendar.getEventSquad(
    widget.event.id,
  );

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final strings = AppStrings.of(context);
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '${strings.domainValue(event.type)} · ${strings.domainValue(event.state)}',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: strings.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: strings.feature('Info')),
              Tab(text: strings.feature('Deltagare')),
              Tab(text: strings.feature('Förberedelser')),
              Tab(text: strings.feature('Uppföljning')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _scroll(_info(context)),
                _scroll(_participants(context)),
                _scroll(_preparation(context)),
                _scroll(_followUp(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.all(20), child: child);

  Widget _info(BuildContext context) {
    final event = widget.event;
    final strings = AppStrings.of(context);
    final teamNames = event.teams
        .map((team) {
          final name = team['name'] as String? ?? '';
          return team['relation'] == 'primary'
              ? strings.eventOwner(name)
              : name;
        })
        .where((name) => name.isNotEmpty)
        .join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: Text(_eventDateTimeLabel(context, event)),
          subtitle: Text(widget.event.timezone),
        ),
        if (event.locationName != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(event.locationName!),
          ),
        if (teamNames.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_outlined),
            title: Text(teamNames),
          ),
        if (event.description != null) ...[
          const SizedBox(height: 8),
          Text(event.description!),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (event.can('revise'))
              OutlinedButton.icon(
                onPressed: widget.onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(AppStrings.of(context).feature('Redigera')),
              ),
            if (event.can('manage_sharing'))
              OutlinedButton.icon(
                onPressed: widget.onShare,
                icon: const Icon(Icons.share_outlined),
                label: Text(
                  AppStrings.of(context).feature('Dela med andra lag'),
                ),
              ),
            if (event.can('cancel') && event.state == 'draft')
              FilledButton.tonalIcon(
                onPressed: widget.onPublish,
                icon: const Icon(Icons.publish_outlined),
                label: Text(AppStrings.of(context).feature('Publicera event')),
              ),
            if (event.can('cancel') && event.state == 'cancelled')
              FilledButton.tonalIcon(
                onPressed: widget.onRestore,
                icon: const Icon(Icons.restore),
                label: Text(AppStrings.of(context).feature('Återställ event')),
              ),
            if (event.can('cancel') && event.state != 'cancelled')
              TextButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.event_busy),
                label: Text(AppStrings.of(context).feature('Ställ in')),
              ),
            if (event.can('delete'))
              TextButton.icon(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(AppStrings.of(context).feature('Ta bort utkast')),
              ),
            if (event.can('archive'))
              TextButton.icon(
                onPressed: widget.onArchive,
                icon: const Icon(Icons.archive_outlined),
                label: Text(AppStrings.of(context).feature('Arkivera event')),
              ),
          ],
        ),
      ],
    );
  }

  String _eventDateTimeLabel(BuildContext context, EventDetails event) {
    final localizations = MaterialLocalizations.of(context);
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    final sameDay = DateUtils.isSameDay(start, end);
    if (event.allDay) {
      final startDate = localizations.formatFullDate(start);
      return sameDay
          ? startDate
          : '$startDate – ${localizations.formatFullDate(end)}';
    }
    final startTime = TimeOfDay.fromDateTime(start).format(context);
    final endTime = TimeOfDay.fromDateTime(end).format(context);
    if (sameDay) {
      return '${localizations.formatFullDate(start)} · $startTime–$endTime';
    }
    return '${localizations.formatMediumDate(start)} $startTime – '
        '${localizations.formatMediumDate(end)} $endTime';
  }

  Widget _participants(BuildContext context) => FutureBuilder<SquadDetails>(
    future: _squad,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        final strings = AppStrings.of(context);
        return ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(
            AppStrings.of(
              context,
            ).feature('Deltagaruppgifter är inte tillgängliga'),
          ),
          subtitle: Text(
            strings.feature(
              'Din roll kan sakna åtkomst eller informationen kunde inte laddas.',
            ),
          ),
        );
      }
      final squad = snapshot.requireData;
      final accepted = squad.callups
          .where((callup) => callup.state == 'accepted')
          .length;
      final pending = squad.callups
          .where((callup) => callup.state == 'pending')
          .length;
      final strings = AppStrings.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.of(context).feature('Urval'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(strings.selectedParticipants(squad.members.length)),
          const SizedBox(height: 16),
          Text(
            strings.feature('Kallelser och svar'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(strings.callupSummary(squad.callups.length, accepted, pending)),
          const SizedBox(height: 16),
          Text(
            AppStrings.of(context).feature('Närvaro'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(strings.registeredParticipants(squad.attendance.length)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: widget.onParticipants,
            icon: const Icon(Icons.groups_outlined),
            label: Text(
              squad.callerActions.isEmpty
                  ? strings.viewParticipantsAndResponses
                  : strings.manageEventParticipation,
            ),
          ),
        ],
      );
    },
  );

  Widget _preparation(BuildContext context) {
    final event = widget.event;
    final actions = event.preparationActions;
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.preparationTitle(event.type),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(strings.preparationDescription(event.type)),
        const SizedBox(height: 20),
        if (actions.contains(EventPreparationAction.matchSpace))
          FilledButton.tonalIcon(
            onPressed: widget.onMatchSpace,
            icon: const Icon(Icons.sports_soccer),
            label: Text(strings.matchSpaceAction(widget.matchSpaceV2)),
          ),
        if (actions.contains(EventPreparationAction.participants))
          OutlinedButton.icon(
            onPressed: widget.onParticipants,
            icon: const Icon(Icons.groups_outlined),
            label: Text(
              AppStrings.of(
                context,
              ).feature('Förbered deltagare och kallelser'),
            ),
          ),
        if (actions.contains(EventPreparationAction.editEvent))
          OutlinedButton.icon(
            onPressed: widget.onEdit,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: Text(
              AppStrings.of(context).feature('Uppdatera eventinformation'),
            ),
          ),
      ],
    );
  }

  Widget _followUp(BuildContext context) => FutureBuilder<SquadDetails>(
    future: _squad,
    builder: (context, snapshot) {
      final attendance = snapshot.data?.attendance ?? const <AttendanceView>[];
      final recorded = attendance
          .where((entry) => entry.status != 'unknown')
          .length;
      final strings = AppStrings.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.of(context).feature('Uppföljning'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.hasError
                ? strings.followUpUnavailable
                : strings.attendanceSummary(recorded, attendance.length),
          ),
          const SizedBox(height: 20),
          if (widget.event.can('manage_roster'))
            OutlinedButton.icon(
              onPressed: widget.onParticipants,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                AppStrings.of(
                  context,
                ).feature('Registrera och granska närvaro'),
              ),
            ),
          if (widget.event.type == 'match')
            OutlinedButton.icon(
              onPressed: widget.onMatchSpace,
              icon: const Icon(Icons.query_stats_outlined),
              label: Text(AppStrings.of(context).feature('Följ upp matchen')),
            ),
          if (widget.event.can('complete') && widget.event.state == 'scheduled')
            FilledButton.icon(
              onPressed: widget.onComplete,
              icon: const Icon(Icons.task_alt),
              label: Text(AppStrings.of(context).feature('Markera genomfört')),
            ),
        ],
      );
    },
  );
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
  bool _showWeekNumbers = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = AsyncDataController<List<CalendarEventSummary>>(
      scopeKey: _scopeKey,
      loader: _reload,
      isEmpty: (events) => events.isEmpty,
    );
    unawaited(_data.load());
    _listenForInvalidations();
    _openInitialEvent();
    unawaited(_loadShowWeekNumbers());
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

  String? _openedInitialEventId;

  void _openInitialEvent() {
    final eventId = widget.initialEventId;
    if (eventId == null || eventId == _openedInitialEventId) return;
    _openedInitialEventId = eventId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showDetailsById(eventId));
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
    if (oldWidget.initialEventId != widget.initialEventId) _openInitialEvent();
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

  Future<void> _showDetails(CalendarEventSummary summary) async {
    _openedInitialEventId = summary.id;
    widget.onNavigate(
      Uri(
        path: ProductRouteContract.calendar,
        queryParameters: {'event': summary.id},
      ).toString(),
    );
    await _showDetailsById(summary.id);
  }

  Future<void> _showDetailsById(String eventId) async {
    EventDetails details;
    try {
      details = await widget.calendar.getEventDetails(eventId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Eventdetaljer kunde inte laddas.'),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    Widget panel(BuildContext routeContext) {
      Future<void> run(Future<void> Function() action) async {
        Navigator.pop(routeContext);
        await action();
      }

      return _EventDetailsPanel(
        event: details,
        calendar: widget.calendar,
        matchSpaceV2: widget.matchSpaceV2,
        onParticipants: () => run(() => _showSquad(details)),
        onMatchSpace: () => run(() => _showMatchSpace(details)),
        onEdit: () => run(() => _revise(details)),
        onShare: () => run(() => _showSharing(details)),
        onPublish: () => run(() => _transition(details, 'scheduled')),
        onRestore: () => run(() => _transition(details, 'scheduled')),
        onCancel: () => run(() => _transition(details, 'cancelled')),
        onDelete: () => run(() => _deleteDraft(details)),
        onArchive: () => run(() => _archive(details)),
        onComplete: () => run(() => _transition(details, 'completed')),
      );
    }

    if (MediaQuery.sizeOf(context).width >= 720) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: 760, height: 680, child: panel(dialogContext)),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .9,
          child: panel(sheetContext),
        ),
      );
    }
    if (mounted && widget.initialEventId == eventId) {
      _openedInitialEventId = null;
      widget.onNavigate(ProductRouteContract.calendar);
    }
  }

  Future<void> _showSharing(EventDetails event) async {
    EventSharingSettings settings;
    try {
      settings = await widget.calendar.getEventSharing(event.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Delningsinställningarna kunde inte laddas.'),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final levels = <String, String>{};
    final audiences = <String, Set<String>>{};
    for (final team in settings.teams) {
      levels[team.teamId] = !team.selected
          ? 'none'
          : team.capabilities.contains('co_manage')
          ? 'co_manage'
          : team.capabilities.contains('manage_roster')
          ? 'manage_roster'
          : 'view';
      audiences[team.teamId] = settings.audiences
          .where((entry) => entry['team_id'] == team.teamId)
          .map((entry) => entry['type'])
          .whereType<String>()
          .toSet();
    }
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).feature('Dela event')),
          content: SizedBox(
            width: 520,
            child: settings.teams.isEmpty
                ? Text(
                    AppStrings.of(
                      context,
                    ).feature('Det finns inga andra aktiva lag i klubben.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: settings.teams.map((team) {
                      final level = levels[team.teamId]!;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                team.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              DropdownButtonFormField<String>(
                                initialValue: level,
                                decoration: const InputDecoration(
                                  labelText: 'Rättighet',
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'none',
                                    child: Text(
                                      AppStrings.of(
                                        context,
                                      ).feature('Ingen delning'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'view',
                                    child: Text(
                                      AppStrings.of(context).feature('Kan se'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'manage_roster',
                                    child: Text(
                                      AppStrings.of(
                                        context,
                                      ).feature('Kan hantera deltagare'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'co_manage',
                                    child: Text(
                                      AppStrings.of(
                                        context,
                                      ).feature('Kan samredigera eventet'),
                                    ),
                                  ),
                                ],
                                onChanged: saving
                                    ? null
                                    : (value) => setDialogState(() {
                                        levels[team.teamId] = value!;
                                        if (value == 'none') {
                                          audiences[team.teamId]!.clear();
                                        }
                                      }),
                              ),
                              if (level != 'none') ...[
                                const SizedBox(height: 8),
                                Text(
                                  AppStrings.of(
                                    context,
                                  ).feature('Mottagare (ger endast synlighet)'),
                                ),
                                Wrap(
                                  children:
                                      const {
                                            'players': 'Spelare',
                                            'leaders': 'Ledare',
                                            'guardians': 'Vårdnadshavare',
                                          }.entries
                                          .map(
                                            (entry) => FilterChip(
                                              label: Text(entry.value),
                                              selected: audiences[team.teamId]!
                                                  .contains(entry.key),
                                              onSelected: saving
                                                  ? null
                                                  : (
                                                      selected,
                                                    ) => setDialogState(() {
                                                      selected
                                                          ? audiences[team
                                                                    .teamId]!
                                                                .add(entry.key)
                                                          : audiences[team
                                                                    .teamId]!
                                                                .remove(
                                                                  entry.key,
                                                                );
                                                    }),
                                            ),
                                          )
                                          .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      final shared = settings.teams
                          .where((team) => levels[team.teamId] != 'none')
                          .map((team) {
                            final level = levels[team.teamId]!;
                            return <String, dynamic>{
                              'team_id': team.teamId,
                              'capabilities': [
                                'view',
                                if (level != 'view') level,
                              ],
                            };
                          })
                          .toList();
                      final audienceEntries = settings.audiences
                          .where(
                            (entry) =>
                                entry['team_id'] == null ||
                                !levels.containsKey(entry['team_id']),
                          )
                          .map(
                            (entry) =>
                                Map<String, dynamic>.from(entry)
                                  ..remove('team_name'),
                          )
                          .toList();
                      for (final entry in audiences.entries) {
                        if (levels[entry.key] == 'none') continue;
                        for (final type in entry.value) {
                          audienceEntries.add({
                            'type': type,
                            'team_id': entry.key,
                          });
                        }
                      }
                      try {
                        await widget.calendar.updateEventSharing(
                          eventId: event.id,
                          sharedTeams: shared,
                          audiences: audienceEntries,
                          expectedRevision: settings.revision,
                          idempotencyKey: _newUuid(),
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppStrings.of(
                                  this.context,
                                ).feature('Delningen har sparats.'),
                              ),
                            ),
                          );
                          unawaited(_data.refresh());
                        }
                      } catch (_) {
                        setDialogState(() => saving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Delningen kunde inte sparas. Ladda om och försök igen.',
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppStrings.of(context).feature('Spara')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDraft(EventDetails event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Ta bort utkast?')),
        content: const Text(
          'Endast detta opublicerade event utan kallelser eller historik tas bort. Åtgärden går inte att ångra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).feature('Ta bort')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.calendar.deleteEventDraft(
        eventId: event.id,
        expectedRevision: event.revision,
        idempotencyKey: _newUuid(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).feature('Utkastet har tagits bort.'),
          ),
        ),
      );
      unawaited(_data.refresh());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Utkastet kan inte tas bort. Det kan ha ändrats eller fått historik.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _archive(EventDetails event) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Arkivera event')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Orsak',
            helperText: 'Historik, kallelser och närvaro bevaras.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 3) Navigator.pop(context, value);
            },
            child: Text(AppStrings.of(context).feature('Arkivera')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    try {
      await widget.calendar.archiveEvent(
        eventId: event.id,
        expectedRevision: event.revision,
        reason: reason,
        idempotencyKey: _newUuid(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).feature('Eventet har arkiverats.'),
          ),
        ),
      );
      unawaited(_data.refresh());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Eventet kunde inte arkiveras.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showMatchSpace(EventDetails event) => showDialog<void>(
    context: context,
    builder: (_) => _MatchSpaceDialog(
      event: event,
      match: widget.match,
      compactFallback: !widget.matchSpaceV2,
    ),
  );

  Future<void> _showSquad(EventDetails event) async {
    SquadDetails squad;
    try {
      squad = await widget.calendar.getEventSquad(event.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Truppen kunde inte laddas.'),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStrings.of(context).feature('Trupp'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${AppStrings.of(context).statusLabel}: ${AppStrings.of(context).domainValue(squad.state)}${squad.revision == null ? '' : ' · ${AppStrings.of(context).revisionLabel} ${squad.revision}'}',
                ),
                if (squad.revision != null)
                  Text(
                    'Urval: ${AppStrings.of(context).domainValue(squad.selectionSource)} · ${squad.dispatchKind == 'late' ? 'Sen kallelse' : 'Ordinarie utskick'}',
                  ),
                if (squad.can('set_callup_visibility')) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: squad.showCallupsToMembers,
                    title: const Text(
                      'Visa kallade för spelare och vårdnadshavare',
                    ),
                    subtitle: const Text(
                      'Av som standard. Om du slår på detta kan deltagare se '
                      'vilka som kallats och deras svar, men aldrig närvaro eller '
                      'administrativa uppgifter.',
                    ),
                    onChanged: (value) async {
                      Navigator.pop(sheetContext);
                      try {
                        await widget.calendar.setEventCallupVisibility(
                          eventId: event.id,
                          showToMembers: value,
                          expectedRevision: squad.callupVisibilityRevision,
                          idempotencyKey: _newUuid(),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              value
                                  ? 'Deltagarlistan är synlig för kallade.'
                                  : 'Deltagarlistan är privat.',
                            ),
                          ),
                        );
                        await _showSquad(event);
                      } catch (_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Synligheten kunde inte sparas. Försök igen.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
                if (squad.members.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      AppStrings.of(context).feature('Ingen trupp är uttagen.'),
                    ),
                  ),
                ...squad.members.map(
                  (member) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(member.name),
                    subtitle: Text(
                      '${AppStrings.of(context).domainValue(member.state)} · ${AppStrings.of(context).domainValue(member.source)}',
                    ),
                  ),
                ),
                if (squad.can('save_squad') && squad.state != 'locked')
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _showSquadDraftEditor(event, squad);
                    },
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(
                      squad.members.isEmpty
                          ? 'Skapa deltagardraft'
                          : 'Redigera deltagardraft',
                    ),
                  ),
                if (squad.can('lock_squad') &&
                    squad.state == 'draft' &&
                    squad.revision != null)
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _runSquadAction(
                        () => widget.calendar.lockSquad(
                          eventId: event.id,
                          expectedRevision: squad.revision!,
                          idempotencyKey: _newUuid(),
                        ),
                        event,
                      );
                    },
                    icon: const Icon(Icons.lock_outline),
                    label: Text(AppStrings.of(context).feature('Lås trupp')),
                  ),
                if (squad.can('send_callups') &&
                    squad.state == 'locked' &&
                    squad.squadRevisionId != null)
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _runSquadAction(
                        () => widget.calendar.sendCallups(
                          squadRevisionId: squad.squadRevisionId!,
                          expiry: DateTime.now().add(const Duration(days: 7)),
                          idempotencyKey: _newUuid(),
                        ),
                        event,
                      );
                    },
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      squad.dispatchKind == 'late'
                          ? 'Skicka sena kallelser'
                          : AppStrings.of(context).feature('Skicka kallelser'),
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  'Kallelser',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (squad.callups.isEmpty)
                  Text(
                    AppStrings.of(context).feature('Inga kallelser skickade.'),
                  ),
                ...squad.callups.map(
                  (callup) => ListTile(
                    title: Text(callup.name),
                    subtitle: Text(
                      '${AppStrings.of(context).domainValue(callup.state)} · ${AppStrings.of(context).deliveryLabel} ${AppStrings.of(context).domainValue(callup.deliveryState)}'
                      '${callup.responseRole == 'guardian' ? ' · svar som vårdnadshavare' : ''}'
                      '${callup.reminderCount == 0 ? '' : ' · påminnelse ${callup.reminderCount}: ${AppStrings.of(context).domainValue(callup.reminderDeliveryState ?? 'pending')}'}',
                    ),
                    trailing:
                        (callup.canRespond && callup.state != 'cancelled') ||
                            (squad.can('remind_callup') &&
                                callup.state != 'cancelled')
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (callup.canRespond &&
                                  callup.state != 'cancelled')
                                PopupMenuButton<String>(
                                  tooltip: AppStrings.of(
                                    context,
                                  ).feature('Svara på kallelse'),
                                  onSelected: (response) async {
                                    Navigator.pop(sheetContext);
                                    await _respondToCallup(
                                      event,
                                      callup,
                                      response,
                                    );
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'accepted',
                                      child: Text(
                                        AppStrings.of(
                                          context,
                                        ).feature('Acceptera'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'tentative',
                                      child: Text(
                                        AppStrings.of(
                                          context,
                                        ).feature('Kanske'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'declined',
                                      child: Text(
                                        AppStrings.of(context).feature('Avböj'),
                                      ),
                                    ),
                                  ],
                                ),
                              if (squad.can('remind_callup') &&
                                  callup.state != 'cancelled')
                                PopupMenuButton<String>(
                                  tooltip: AppStrings.of(
                                    context,
                                  ).feature('Hantera kallelse'),
                                  onSelected: (action) async {
                                    Navigator.pop(sheetContext);
                                    await _runSquadAction(
                                      () => widget.calendar.manageCallup(
                                        callupId: callup.id,
                                        action: action,
                                        expectedRevision: callup.revision,
                                        idempotencyKey: _newUuid(),
                                      ),
                                      event,
                                    );
                                  },
                                  itemBuilder: (_) => [
                                    if (callup.state == 'pending' &&
                                        (callup.lastRemindedAt == null ||
                                            DateTime.now().difference(
                                                  callup.lastRemindedAt!,
                                                ) >=
                                                const Duration(hours: 6)))
                                      PopupMenuItem(
                                        value: 'remind',
                                        child: Text(
                                          AppStrings.of(
                                            context,
                                          ).feature('Påminn'),
                                        ),
                                      ),
                                    PopupMenuItem(
                                      value: 'cancel',
                                      child: Text(
                                        AppStrings.of(
                                          context,
                                        ).feature('Återkalla'),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          )
                        : null,
                  ),
                ),
                const Divider(height: 32),
                Text(
                  AppStrings.of(context).feature('Närvaro'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  AppStrings.of(context).feature(
                    'Okänd och frånvarande är alltid separata statusar.',
                  ),
                ),
                if (squad.can('record_attendance') &&
                    squad.attendance.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _showAttendanceEditor(event, squad);
                    },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      AppStrings.of(context).feature('Registrera närvaro'),
                    ),
                  ),
                ...squad.attendance.map(
                  (attendance) => ListTile(
                    title: Text(attendance.name),
                    subtitle: Text(
                      '${AppStrings.of(context).domainValue(attendance.status)} · ${AppStrings.of(context).revisionLabel} ${attendance.revision}',
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

  Future<void> _showAttendanceEditor(
    EventDetails event,
    SquadDetails squad,
  ) async {
    AttendancePermissions permissions;
    try {
      permissions = await widget.calendar.getAttendancePermissions(event.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Närvarobehörigheten kunde inte kontrolleras.'),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    if (!permissions.canRecord ||
        (permissions.lateWindow && !permissions.canCorrectLate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).feature(
              permissions.lateWindow
                  ? 'Sen närvarokorrigering kräver särskild behörighet.'
                  : 'Du saknar behörighet att registrera närvaro.',
            ),
          ),
        ),
      );
      return;
    }
    final statuses = {
      for (final entry in squad.attendance) entry.personId: entry.status,
    };
    final minutes = {
      for (final entry in squad.attendance)
        entry.personId: entry.minutes?.toString() ?? '',
    };
    final dirty = <String>{};
    final reasonController = TextEditingController();
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .92,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.of(context).feature('Registrera närvaro'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.of(context).feature('Stäng'),
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  AppStrings.of(context).feature(
                    'Okänd är neutralt och räknas aldrig som närvarande eller frånvarande.',
                  ),
                ),
              ),
              if (permissions.lateWindow)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: TextField(
                    controller: reasonController,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(
                        context,
                      ).feature('Orsak till sen korrigering'),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: squad.attendance.length,
                  itemBuilder: (context, index) {
                    final attendance = squad.attendance[index];
                    final status = statuses[attendance.personId]!;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(attendance.name)),
                                DropdownButton<String>(
                                  value: status,
                                  items: [
                                    for (final entry in const {
                                      'unknown': 'Okänd',
                                      'present': 'Närvarande',
                                      'late': 'Sen',
                                      'partial': 'Delvis',
                                      'absent': 'Frånvarande',
                                    }.entries)
                                      DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(
                                          AppStrings.of(
                                            context,
                                          ).feature(entry.value),
                                        ),
                                      ),
                                  ],
                                  onChanged: saving
                                      ? null
                                      : (value) => setSheetState(() {
                                          statuses[attendance.personId] =
                                              value!;
                                          if (value == 'late' ||
                                              value == 'partial') {
                                            if (minutes[attendance.personId]!
                                                .isEmpty) {
                                              minutes[attendance.personId] =
                                                  '1';
                                            }
                                          } else {
                                            minutes[attendance.personId] = '';
                                          }
                                          dirty.add(attendance.personId);
                                        }),
                                ),
                              ],
                            ),
                            if (status == 'late' || status == 'partial')
                              TextFormField(
                                key: ValueKey('${attendance.personId}:$status'),
                                initialValue: minutes[attendance.personId],
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: AppStrings.of(context).feature(
                                    status == 'late'
                                        ? 'Minuter sen'
                                        : 'Deltagna minuter',
                                  ),
                                ),
                                onChanged: (value) {
                                  minutes[attendance.personId] = value;
                                  dirty.add(attendance.personId);
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: saving || dirty.isEmpty
                      ? null
                      : () async {
                          final reason = reasonController.text.trim();
                          if (permissions.lateWindow && reason.length < 3) {
                            return;
                          }
                          final changes = squad.attendance
                              .where((entry) => dirty.contains(entry.personId))
                              .map((entry) {
                                final status = statuses[entry.personId]!;
                                return <String, dynamic>{
                                  'person_id': entry.personId,
                                  'status': status,
                                  'expected_revision': entry.revision,
                                  if (status == 'late' || status == 'partial')
                                    'minutes': int.tryParse(
                                      minutes[entry.personId] ?? '',
                                    ),
                                };
                              })
                              .toList();
                          if (changes.any(
                            (change) =>
                                (change['status'] == 'late' ||
                                    change['status'] == 'partial') &&
                                change['minutes'] == null,
                          )) {
                            return;
                          }
                          setSheetState(() => saving = true);
                          try {
                            await widget.calendar.recordAttendance(
                              eventId: event.id,
                              changes: changes,
                              correctionReason: permissions.lateWindow
                                  ? reason
                                  : null,
                              idempotencyKey: _newUuid(),
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppStrings.of(
                                      this.context,
                                    ).feature('Närvaron har sparats.'),
                                  ),
                                ),
                              );
                              await _showDetailsById(event.id);
                            }
                          } catch (_) {
                            setSheetState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppStrings.of(this.context).feature(
                                      'Närvaron kunde inte sparas. Ladda om och försök igen.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    saving
                        ? AppStrings.of(context).feature('Sparar…')
                        : AppStrings.of(context).feature('Spara ändringar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    reasonController.dispose();
  }

  Future<void> _respondToCallup(
    EventDetails event,
    CallupView callup,
    String response,
  ) async {
    String? reasonCode;
    String? reasonText;
    if (response == 'declined') {
      final result = await _showDeclineReason();
      if (result == null || !mounted) return;
      reasonCode = result.$1;
      reasonText = result.$2;
    }
    await _runSquadAction(
      () => widget.calendar.respondCallup(
        callupId: callup.id,
        response: response,
        actingAsPersonId: callup.actingAsPersonId,
        declineReasonCode: reasonCode,
        declineReasonText: reasonText,
        expectedRevision: callup.revision,
        idempotencyKey: _newUuid(),
      ),
      event,
    );
  }

  Future<(String, String?)?> _showDeclineReason() async {
    final controller = TextEditingController();
    var code = 'illness';
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            AppStrings.of(context).feature('Varför kan du inte delta?'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: code,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Anledning'),
                ),
                items:
                    const {
                          'illness': 'Sjukdom',
                          'injury': 'Skada',
                          'unavailable': 'Inte tillgänglig',
                          'transport': 'Transport',
                          'other': 'Annat',
                        }.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              AppStrings.of(context).feature(entry.value),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setDialogState(() => code = value!),
              ),
              if (code == 'other')
                TextField(
                  controller: controller,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(
                      context,
                    ).feature('Beskriv anledning'),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (code != 'other' || text.length >= 2) {
                  Navigator.pop(dialogContext, (
                    code,
                    code == 'other' ? text : null,
                  ));
                }
              },
              child: Text(AppStrings.of(context).feature('Skicka svar')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showSquadDraftEditor(
    EventDetails event,
    SquadDetails squad,
  ) async {
    List<SquadCandidate> candidates;
    try {
      candidates = await widget.calendar.listSquadCandidates(event.id);
      if (candidates.isEmpty) throw StateError('no candidates');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Behöriga deltagare kunde inte laddas.'),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    var source = squad.state == 'draft' ? squad.selectionSource : 'manual';
    var selected = squad.members.map((member) => member.personId).toSet();
    String? groupKind = squad.selectionContext['eligibility_kind'] as String?;
    var targetCount =
        (squad.selectionContext['target_count'] as num?)?.toInt() ??
        candidates.length.clamp(1, 18);
    final groupKinds =
        candidates
            .map((candidate) => candidate.eligibilityKind)
            .toSet()
            .toList()
          ..sort();
    groupKind ??= groupKinds.first;

    void applyStrategy() {
      if (source == 'all') {
        selected = candidates.map((candidate) => candidate.personId).toSet();
      } else if (source == 'group') {
        selected = candidates
            .where((candidate) => candidate.eligibilityKind == groupKind)
            .map((candidate) => candidate.personId)
            .toSet();
      } else if (source == 'generator') {
        final ordered = [...candidates]
          ..sort((left, right) {
            final leftPriority = left.eligibilityKind == 'team_assignment'
                ? 0
                : 1;
            final rightPriority = right.eligibilityKind == 'team_assignment'
                ? 0
                : 1;
            final priority = leftPriority.compareTo(rightPriority);
            if (priority != 0) return priority;
            final name = left.name.compareTo(right.name);
            return name != 0 ? name : left.personId.compareTo(right.personId);
          });
        selected = ordered
            .take(targetCount.clamp(1, ordered.length))
            .map((candidate) => candidate.personId)
            .toSet();
      }
    }

    if (source != 'manual') applyStrategy();
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            squad.state == 'sent' ? 'Skapa sen deltagardraft' : 'Deltagardraft',
          ),
          content: SizedBox(
            width: 560,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Alla metoder sparar till samma revisionerade draft.',
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'manual',
                      label: Text(AppStrings.of(context).feature('Manuell')),
                    ),
                    ButtonSegment(
                      value: 'all',
                      label: Text(AppStrings.of(context).feature('Alla')),
                    ),
                    ButtonSegment(
                      value: 'group',
                      label: Text(AppStrings.of(context).feature('Grupp')),
                    ),
                    ButtonSegment(
                      value: 'generator',
                      label: Text(AppStrings.of(context).feature('Generator')),
                    ),
                  ],
                  selected: {source},
                  showSelectedIcon: false,
                  onSelectionChanged: saving
                      ? null
                      : (value) => setDialogState(() {
                          source = value.single;
                          applyStrategy();
                        }),
                ),
                if (source == 'group')
                  DropdownButtonFormField<String>(
                    initialValue: groupKind,
                    decoration: const InputDecoration(
                      labelText: 'Behörighetsgrupp',
                    ),
                    items: groupKinds
                        .map(
                          (kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(
                              AppStrings.of(context).domainValue(kind),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(() {
                            groupKind = value;
                            applyStrategy();
                          }),
                  ),
                if (source == 'generator') ...[
                  const SizedBox(height: 8),
                  Text('Antal deltagare: $targetCount'),
                  Slider(
                    value: targetCount.toDouble().clamp(
                      1,
                      candidates.length.toDouble(),
                    ),
                    min: 1,
                    max: candidates.length.toDouble(),
                    divisions: candidates.length > 1
                        ? candidates.length - 1
                        : null,
                    label: '$targetCount',
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(() {
                            targetCount = value.round();
                            applyStrategy();
                          }),
                  ),
                  const Text(
                    'Generatorn prioriterar ordinarie spelare och är deterministisk.',
                  ),
                ],
                const SizedBox(height: 8),
                Text('${selected.length} deltagare valda'),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final candidate = candidates[index];
                      return CheckboxListTile(
                        value: selected.contains(candidate.personId),
                        title: Text(candidate.name),
                        subtitle: Text(
                          AppStrings.of(
                            context,
                          ).domainValue(candidate.eligibilityKind),
                        ),
                        onChanged: source != 'manual' || saving
                            ? null
                            : (value) => setDialogState(() {
                                value == true
                                    ? selected.add(candidate.personId)
                                    : selected.remove(candidate.personId);
                              }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: saving || selected.isEmpty
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      final contextValue = <String, dynamic>{
                        if (source == 'group') 'eligibility_kind': groupKind,
                        if (source == 'generator') ...{
                          'generator': 'balanced_v1',
                          'target_count': targetCount,
                        },
                      };
                      try {
                        List<SquadCandidate>? orderedCandidates;
                        if (source == 'generator') {
                          orderedCandidates =
                              candidates
                                  .where(
                                    (candidate) =>
                                        selected.contains(candidate.personId),
                                  )
                                  .toList()
                                ..sort((left, right) {
                                  final lp =
                                      left.eligibilityKind == 'team_assignment'
                                      ? 0
                                      : 1;
                                  final rp =
                                      right.eligibilityKind == 'team_assignment'
                                      ? 0
                                      : 1;
                                  final priority = lp.compareTo(rp);
                                  if (priority != 0) return priority;
                                  final name = left.name.compareTo(right.name);
                                  return name != 0
                                      ? name
                                      : left.personId.compareTo(right.personId);
                                });
                        }
                        await widget.calendar.saveSquadDraft(
                          eventId: event.id,
                          memberIds:
                              orderedCandidates
                                  ?.map((candidate) => candidate.personId)
                                  .toList() ??
                              selected.toList(),
                          source: source,
                          selectionContext: contextValue,
                          expectedRevision: squad.state == 'draft'
                              ? squad.revision
                              : null,
                          idempotencyKey: _newUuid(),
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${selected.length} deltagare sparade i ny draft.',
                              ),
                            ),
                          );
                          await _showDetailsById(event.id);
                        }
                      } catch (_) {
                        setDialogState(() => saving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Draften kunde inte sparas. Ladda om och försök igen.',
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppStrings.of(context).feature('Spara draft')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runSquadAction(
    Future<void> Function() action,
    EventDetails event,
  ) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Ändringen är sparad.'),
            ),
          ),
        );
        await _showSquad(event);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Ändringen kunde inte sparas. Ladda om och försök igen.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _transition(EventDetails details, String targetState) async {
    try {
      await widget.calendar.transitionEvent(
        eventId: details.id,
        targetState: targetState,
        expectedRevision: details.revision,
        reason: AppStrings.of(context).feature('Ändrad i kalendern'),
        idempotencyKey: _newUuid(),
      );
      if (mounted) {
        unawaited(_data.refresh());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Eventet ändrades av någon annan. Ladda om och försök igen.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _revise(EventDetails details) async {
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
        initial: details,
      ),
    );
    if (value == null || !mounted) return;
    try {
      await widget.calendar.reviseEvent(
        eventId: details.id,
        scope: value.scope,
        patch: {
          'title': value.title,
          'description': value.description,
          'event_type': value.type,
          'starts_at': value.startsAt.toUtc().toIso8601String(),
          'ends_at': value.endsAt.toUtc().toIso8601String(),
          'all_day': value.allDay,
          'timezone': value.timezone,
          'location_name': value.locationName,
          'audience_types': value.audiences,
        },
        expectedRevision: details.revision,
        idempotencyKey: _newUuid(),
      );
      if (mounted) {
        unawaited(_data.refresh());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Eventet ändrades av någon annan. Ladda om och försök igen.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        widget.contextValue.teamId != null &&
        widget.contextValue.can('event.manage');
    return Scaffold(
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
              stale: state.isStale,
              reconnecting:
                  state.connection == AppConnectionStatus.reconnecting,
              lastUpdated: state.lastUpdated,
              onModeChanged: (value) => setState(() => _viewMode = value),
              onDateChanged: (value) => setState(() => _selectedDate = value),
              onTeamChanged: (value) => setState(() => _teamFilter = value),
              onTypeChanged: (value) =>
                  setState(() => _eventTypeFilter = value),
              onEvent: _showDetails,
              showWeekNumbers: _showWeekNumbers,
              onShowWeekNumbersChanged: _setShowWeekNumbers,
            );
          },
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _createEvent,
              icon: const Icon(Icons.add),
              label: Text(AppStrings.of(context).feature('Nytt event')),
            )
          : null,
    );
  }
}
