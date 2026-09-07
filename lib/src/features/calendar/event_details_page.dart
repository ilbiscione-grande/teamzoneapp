part of '../../app/teamzone_app.dart';

/// EventDetails as its own page (route: ProductRouteContract.calendarEvent),
/// replacing the previous dialog/bottom-sheet panel. A status header (see
/// _StatusHeaderRow) sits above the same four tabs as before — Info,
/// Deltagare, Förberedelser, Uppföljning — and is visible regardless of
/// which tab is active, per the request that this summary "finns på alla
/// flikar". The Deltagare tab (_ParticipantsTab) is the rebuilt part: a
/// club-wide search that can add people straight to the draft, and one
/// roster list whose rows switch between draft-selection, callup-status and
/// attendance-recording depending on where the event is in its lifecycle —
/// replacing the old "Hantera urval"/"Trupp" bottom sheet entirely.
class _EventDetailsPage extends StatefulWidget {
  const _EventDetailsPage({
    required this.eventId,
    required this.contextValue,
    required this.calendar,
    required this.match,
    required this.matchSpaceV2,
    required this.onNavigate,
  });

  final String eventId;
  final TeamZoneContext contextValue;
  final CalendarServices calendar;
  final MatchServices match;
  final bool matchSpaceV2;
  final ValueChanged<String> onNavigate;

  @override
  State<_EventDetailsPage> createState() => _EventDetailsPageState();
}

class _EventDetailsPageState extends State<_EventDetailsPage> {
  Future<(EventDetails, SquadDetails)>? _load;
  // Kept separately from _load's snapshot so the AppBar title stays correct
  // after _EventDetailsBody refreshes the event in place (a rename via
  // "Redigera", say) without this page itself reloading.
  String? _title;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _updateTitle(String title) {
    if (_title != title) setState(() => _title = title);
  }

  void _reload() {
    // Not `setState(() => _load = _fetch())`: an assignment expression's
    // value is the assigned value, so that arrow-body callback would
    // itself "return" the Future — exactly what Flutter's setState
    // guards against ("callback argument returned a Future").
    setState(() {
      _load = _fetch();
    });
  }

  Future<(EventDetails, SquadDetails)> _fetch() async {
    final event = await widget.calendar.getEventDetails(widget.eventId);
    final squad = await widget.calendar.getEventSquad(widget.eventId);
    return (event, squad);
  }

  void _goBackToCalendar() => widget.onNavigate(ProductRouteContract.calendar);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: _title == null ? null : Text(_title!),
        actions: [
          IconButton(
            tooltip: strings.close,
            onPressed: _goBackToCalendar,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: FutureBuilder<(EventDetails, SquadDetails)>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AppLoadingIndicator(label: strings.loading);
          }
          if (snapshot.hasError) {
            return Center(
              child: _StateCard(
                icon: Icons.sync_problem,
                title: strings.feature('Eventdetaljer kunde inte laddas'),
                message: strings.safeError,
                action: FilledButton(
                  onPressed: _reload,
                  child: Text(strings.retry),
                ),
              ),
            );
          }
          final (event, squad) = snapshot.requireData;
          // A stable key (not just position) so a future rebuild of this
          // FutureBuilder for an unrelated reason (theme/locale change,
          // say) can never be mistaken for a fresh load and reset
          // _EventDetailsBodyState — only _reload() (a real retry) does
          // that, by replacing _load itself.
          return _EventDetailsBody(
            key: const ValueKey('event-details-body'),
            initialEvent: event,
            initialSquad: squad,
            eventId: widget.eventId,
            contextValue: widget.contextValue,
            calendar: widget.calendar,
            match: widget.match,
            matchSpaceV2: widget.matchSpaceV2,
            onDeleted: _goBackToCalendar,
            onTitleChanged: _updateTitle,
          );
        },
      ),
    );
  }
}

class _EventDetailsBody extends StatefulWidget {
  const _EventDetailsBody({
    required this.initialEvent,
    required this.initialSquad,
    required this.eventId,
    required this.contextValue,
    required this.calendar,
    required this.match,
    required this.matchSpaceV2,
    required this.onDeleted,
    required this.onTitleChanged,
    super.key,
  });

  final EventDetails initialEvent;
  final SquadDetails initialSquad;
  final String eventId;
  final TeamZoneContext contextValue;
  final CalendarServices calendar;
  final MatchServices match;
  final bool matchSpaceV2;
  final VoidCallback onDeleted;
  final ValueChanged<String> onTitleChanged;

  @override
  State<_EventDetailsBody> createState() => _EventDetailsBodyState();
}

class _EventDetailsBodyState extends State<_EventDetailsBody> {
  // Seeded once from the page's initial load, then updated in place by
  // _refresh() after an action — never by tearing this widget down and
  // rebuilding it, which used to reset the active tab back to Info and
  // lose the Deltagare tab's search/staged-edit state on every single
  // draft toggle ("varje gång jag trycker på en checkbox så laddar sidan
  // om och jag måste gå in på deltagare igen").
  late EventDetails event = widget.initialEvent;
  late SquadDetails squad = widget.initialSquad;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onTitleChanged(event.title),
    );
  }

  Future<void> _refresh() async {
    try {
      final event = await widget.calendar.getEventDetails(widget.eventId);
      final squad = await widget.calendar.getEventSquad(widget.eventId);
      if (mounted) {
        setState(() {
          this.event = event;
          this.squad = squad;
        });
        widget.onTitleChanged(event.title);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Kunde inte uppdatera. Försök igen.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _StatusHeaderRow(event: event, squad: squad),
          ),
          const SizedBox(height: 4),
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
                _ParticipantsTab(
                  event: event,
                  squad: squad,
                  calendar: widget.calendar,
                  onReload: _refresh,
                ),
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
          subtitle: Text(event.timezone),
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
                onPressed: _revise,
                icon: const Icon(Icons.edit_outlined),
                label: Text(strings.feature('Redigera')),
              ),
            if (event.can('manage_sharing'))
              OutlinedButton.icon(
                onPressed: _showSharing,
                icon: const Icon(Icons.share_outlined),
                label: Text(strings.feature('Dela med andra lag')),
              ),
            if (event.can('cancel') && event.state == 'draft')
              FilledButton.tonalIcon(
                onPressed: () => _transition('scheduled'),
                icon: const Icon(Icons.publish_outlined),
                label: Text(strings.feature('Publicera event')),
              ),
            if (event.can('cancel') && event.state == 'cancelled')
              FilledButton.tonalIcon(
                onPressed: () => _transition('scheduled'),
                icon: const Icon(Icons.restore),
                label: Text(strings.feature('Återställ event')),
              ),
            if (event.can('cancel') && event.state != 'cancelled')
              TextButton.icon(
                onPressed: () => _transition('cancelled'),
                icon: const Icon(Icons.event_busy),
                label: Text(strings.feature('Ställ in')),
              ),
            if (event.can('delete'))
              TextButton.icon(
                onPressed: _deleteDraft,
                icon: const Icon(Icons.delete_outline),
                label: Text(strings.feature('Ta bort utkast')),
              ),
            if (event.can('archive'))
              TextButton.icon(
                onPressed: _archive,
                icon: const Icon(Icons.archive_outlined),
                label: Text(strings.feature('Arkivera event')),
              ),
          ],
        ),
      ],
    );
  }

  Widget _preparation(BuildContext context) {
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
            onPressed: _showMatchSpace,
            icon: const Icon(Icons.sports_soccer),
            label: Text(strings.matchSpaceAction(widget.matchSpaceV2)),
          ),
        if (actions.contains(EventPreparationAction.participants))
          OutlinedButton.icon(
            onPressed: () => DefaultTabController.of(context).animateTo(1),
            icon: const Icon(Icons.groups_outlined),
            label: Text(strings.feature('Förbered deltagare och kallelser')),
          ),
        if (actions.contains(EventPreparationAction.editEvent))
          OutlinedButton.icon(
            onPressed: _revise,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: Text(strings.feature('Uppdatera eventinformation')),
          ),
      ],
    );
  }

  Widget _followUp(BuildContext context) {
    final attendance = squad.attendance;
    final recorded = attendance
        .where((entry) => entry.status != 'unknown')
        .length;
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.feature('Uppföljning'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(strings.attendanceSummary(recorded, attendance.length)),
        const SizedBox(height: 20),
        if (event.can('manage_roster'))
          OutlinedButton.icon(
            onPressed: () => DefaultTabController.of(context).animateTo(1),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(strings.feature('Registrera eller granska närvaro')),
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
    final startDate = localizations.formatFullDate(start);
    final startTime = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(start),
    );
    final endTime = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end));
    return sameDay
        ? '$startDate · $startTime–$endTime'
        : '$startDate $startTime – ${localizations.formatFullDate(end)} $endTime';
  }

  Future<void> _revise() async {
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
        initial: event,
      ),
    );
    if (value == null || !mounted) return;
    try {
      await widget.calendar.reviseEvent(
        eventId: event.id,
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
        expectedRevision: event.revision,
        idempotencyKey: _newUuid(),
      );
      if (mounted) unawaited(_refresh());
    } catch (_) {
      if (mounted) _showError('Eventet ändrades av någon annan. Ladda om och försök igen.');
    }
  }

  Future<void> _transition(String targetState) async {
    try {
      await widget.calendar.transitionEvent(
        eventId: event.id,
        targetState: targetState,
        expectedRevision: event.revision,
        reason: AppStrings.of(context).feature('Ändrad i kalendern'),
        idempotencyKey: _newUuid(),
      );
      if (mounted) unawaited(_refresh());
    } catch (_) {
      if (mounted) _showError('Eventet ändrades av någon annan. Ladda om och försök igen.');
    }
  }

  Future<void> _deleteDraft() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.feature('Ta bort utkast?')),
        content: const Text(
          'Endast detta opublicerade event utan kallelser eller historik tas bort. Åtgärden går inte att ångra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.feature('Ta bort')),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.feature('Utkastet har tagits bort.'))));
      widget.onDeleted();
    } catch (_) {
      if (mounted) {
        _showError('Utkastet kan inte tas bort. Det kan ha ändrats eller fått historik.');
      }
    }
  }

  Future<void> _archive() async {
    final strings = AppStrings.of(context);
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.feature('Arkivera event')),
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
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 3) Navigator.pop(context, value);
            },
            child: Text(strings.feature('Arkivera')),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.feature('Eventet har arkiverats.'))));
      widget.onDeleted();
    } catch (_) {
      if (mounted) _showError('Eventet kunde inte arkiveras.');
    }
  }

  Future<void> _showMatchSpace() => showDialog<void>(
    context: context,
    builder: (_) => _MatchSpaceDialog(
      event: event,
      match: widget.match,
      compactFallback: !widget.matchSpaceV2,
    ),
  );

  Future<void> _showSharing() async {
    final strings = AppStrings.of(context);
    EventSharingSettings settings;
    try {
      settings = await widget.calendar.getEventSharing(event.id);
    } catch (_) {
      if (mounted) _showError('Delningsinställningarna kunde inte laddas.');
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
          title: Text(strings.feature('Dela event')),
          content: SizedBox(
            width: 520,
            child: settings.teams.isEmpty
                ? Text(strings.feature('Det finns inga andra aktiva lag i klubben.'))
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
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Rättighet'),
                                items: [
                                  DropdownMenuItem(
                                    value: 'none',
                                    child: Text(strings.feature('Ingen delning')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'view',
                                    child: Text(strings.feature('Kan se')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'manage_roster',
                                    child: Text(strings.feature('Kan hantera deltagare')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'co_manage',
                                    child: Text(strings.feature('Kan samredigera eventet')),
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
                                Text(strings.feature('Mottagare (ger endast synlighet)')),
                                Wrap(
                                  children: const {
                                    'players': 'Spelare',
                                    'leaders': 'Ledare',
                                    'guardians': 'Vårdnadshavare',
                                  }.entries.map((entry) {
                                    return FilterChip(
                                      label: Text(entry.value),
                                      selected: audiences[team.teamId]!.contains(entry.key),
                                      onSelected: saving
                                          ? null
                                          : (selected) => setDialogState(() {
                                              selected
                                                  ? audiences[team.teamId]!.add(entry.key)
                                                  : audiences[team.teamId]!.remove(entry.key);
                                            }),
                                    );
                                  }).toList(),
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
              child: Text(strings.feature('Avbryt')),
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
                              'capabilities': ['view', if (level != 'view') level],
                            };
                          })
                          .toList();
                      final audienceEntries = settings.audiences
                          .where(
                            (entry) =>
                                entry['team_id'] == null ||
                                !levels.containsKey(entry['team_id']),
                          )
                          .map((entry) => Map<String, dynamic>.from(entry)..remove('team_name'))
                          .toList();
                      for (final entry in audiences.entries) {
                        if (levels[entry.key] == 'none') continue;
                        for (final type in entry.value) {
                          audienceEntries.add({'type': type, 'team_id': entry.key});
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
                            SnackBar(content: Text(strings.feature('Delningen har sparats.'))),
                          );
                          unawaited(_refresh());
                        }
                      } catch (_) {
                        setDialogState(() => saving = false);
                        if (mounted) _showError('Delningen kunde inte sparas. Ladda om och försök igen.');
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(strings.feature('Spara')),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).feature(message))));
  }
}

/// The status circle row shown above the tabs, visible regardless of which
/// tab is active: draft/called/accepted/declined/unanswered counts, plus an
/// "attended" circle once the event has ended.
class _StatusHeaderRow extends StatelessWidget {
  const _StatusHeaderRow({required this.event, required this.squad});
  final EventDetails event;
  final SquadDetails squad;

  bool get _hasEnded => DateTime.now().toUtc().isAfter(event.endsAt.toUtc());

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final roster = squad.roster;
    final draft = roster.where((p) => p.inDraft).length;
    final called = roster.where((p) => p.isCalled).length;
    final accepted = roster.where((p) => p.callupState == 'accepted').length;
    final declined = roster.where((p) => p.callupState == 'declined').length;
    final unanswered = roster
        .where((p) => p.isCalled && p.callupState != 'accepted' && p.callupState != 'declined')
        .length;
    final attended = roster
        .where(
          (p) =>
              p.attendanceStatus == 'present' ||
              p.attendanceStatus == 'late' ||
              p.attendanceStatus == 'partial',
        )
        .length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StatusCircle(
            count: draft,
            label: strings.feature('Utkast'),
            color: Colors.blueGrey,
          ),
          _StatusCircle(
            count: called,
            label: strings.feature('Kallade'),
            color: Colors.indigo,
          ),
          _StatusCircle(
            count: accepted,
            label: strings.domainValue('accepted'),
            color: Colors.green,
          ),
          _StatusCircle(
            count: unanswered,
            label: strings.feature('Obesvarade'),
            color: Colors.amber.shade800,
          ),
          _StatusCircle(
            count: declined,
            label: strings.domainValue('declined'),
            color: Colors.red,
          ),
          if (_hasEnded)
            _StatusCircle(
              count: attended,
              label: strings.feature('Deltog'),
              color: Colors.teal,
            ),
        ],
      ),
    );
  }
}

class _StatusCircle extends StatelessWidget {
  const _StatusCircle({required this.count, required this.label, required this.color});
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: Column(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color,
          child: Text(
            '$count',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

/// The Deltagare tab: club-wide search-and-add at the top, then one roster
/// list (kallade spelare, kallade ledare, okallade spelare, okallade
/// ledare — the fixed order and internal sort the user asked for) whose
/// rows switch behavior with the event's lifecycle:
///  - before any callups exist: a checkbox toggles draft membership;
///  - once called: the row shows the person's callup response (read-only —
///    that's their own action) with remind/cancel where the caller can;
///  - once the event has ended: called rows switch to an attendance status
///    picker instead. Recording attendance for someone who was never
///    called is not something the backend supports (record_attendance_v2
///    requires an existing callup), so uncalled rows stay informational
///    there rather than offering a control that would just fail.
/// Replaces the old "Hantera urval"/"Trupp" bottom sheet entirely — no
/// button to go elsewhere, everything happens inline on this tab.
class _ParticipantsTab extends StatefulWidget {
  const _ParticipantsTab({
    required this.event,
    required this.squad,
    required this.calendar,
    required this.onReload,
  });

  final EventDetails event;
  final SquadDetails squad;
  final CalendarServices calendar;
  final VoidCallback onReload;

  @override
  State<_ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends State<_ParticipantsTab> {
  final _searchController = TextEditingController();
  final _reasonController = TextEditingController();
  List<SquadCandidate> _candidates = const [];
  String _query = '';
  bool _busy = false;
  AttendancePermissions? _resolvedPermissions;

  // Attendance edits staged locally until "Spara närvaro" — only entries
  // the person actually touched, so an empty map means nothing pending.
  final Map<String, String> _stagedStatus = {};
  final Map<String, int> _stagedMinutes = {};

  bool get _canManage => widget.squad.can('save_squad');
  bool get _canRecordAttendance => widget.squad.can('record_attendance');
  bool get _eventEnded => DateTime.now().toUtc().isAfter(widget.event.endsAt.toUtc());
  Set<String> get _draftMemberIds =>
      widget.squad.members.map((member) => member.personId).toSet();

  @override
  void initState() {
    super.initState();
    if (_canManage) unawaited(_loadCandidates());
    if (_eventEnded && _canRecordAttendance) {
      unawaited(
        widget.calendar.getAttendancePermissions(widget.event.id).then((value) {
          if (mounted) setState(() => _resolvedPermissions = value);
        }),
      );
    }
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void didUpdateWidget(covariant _ParticipantsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.squad.revision != widget.squad.revision) {
      // A save just landed and the parent refetched — drop any staged
      // attendance edits so the UI reflects the fresh server state rather
      // than a mix of old local edits and new data.
      _stagedStatus.clear();
      _stagedMinutes.clear();
      if (_canManage) unawaited(_loadCandidates());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    try {
      final candidates = await widget.calendar.listSquadCandidates(widget.event.id);
      if (mounted) setState(() => _candidates = candidates);
    } catch (_) {
      // Search just stays empty; the roster list below still works.
    }
  }

  List<SquadCandidate> get _matches {
    if (_query.isEmpty) return const [];
    final needle = _query.toLowerCase();
    return _candidates
        .where(
          (candidate) =>
              candidate.name.toLowerCase().contains(needle) ||
              (candidate.teamName?.toLowerCase().contains(needle) ?? false),
        )
        .toList();
  }

  Future<void> _toggleDraftMember(String personId) async {
    final ids = _draftMemberIds;
    ids.contains(personId) ? ids.remove(personId) : ids.add(personId);
    setState(() => _busy = true);
    try {
      await widget.calendar.saveSquadDraft(
        eventId: widget.event.id,
        memberIds: ids.toList(),
        source: 'manual',
        expectedRevision: widget.squad.state == 'draft' ? widget.squad.revision : null,
        idempotencyKey: _newUuid(),
      );
      widget.onReload();
    } catch (_) {
      if (mounted) _showError('Ändringen kunde inte sparas. Ladda om och försök igen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCallups() async {
    final revisionId = widget.squad.squadRevisionId;
    if (revisionId == null) return;
    setState(() => _busy = true);
    try {
      await widget.calendar.sendCallups(
        squadRevisionId: revisionId,
        expiry: DateTime.now().add(const Duration(days: 7)),
        idempotencyKey: _newUuid(),
      );
      widget.onReload();
    } catch (_) {
      if (mounted) _showError('Kallelserna kunde inte skickas. Ladda om och försök igen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageCallup(EventRosterPerson person, String action) async {
    final callupId = person.callupId;
    if (callupId == null) return;
    setState(() => _busy = true);
    try {
      await widget.calendar.manageCallup(
        callupId: callupId,
        action: action,
        expectedRevision:
            widget.squad.callups.where((callup) => callup.id == callupId).map((callup) => callup.revision).firstOrNull ??
            0,
        idempotencyKey: _newUuid(),
      );
      widget.onReload();
    } catch (_) {
      if (mounted) _showError('Åtgärden kunde inte utföras. Ladda om och försök igen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setAttendance(EventRosterPerson person, String status) {
    setState(() {
      _stagedStatus[person.personId] = status;
      if (status == 'late' || status == 'partial') {
        _stagedMinutes.putIfAbsent(person.personId, () => 1);
      } else {
        _stagedMinutes.remove(person.personId);
      }
    });
  }

  Future<void> _saveAttendance() async {
    final strings = AppStrings.of(context);
    final permissions = _resolvedPermissions;
    if (permissions == null || _stagedStatus.isEmpty) return;
    final reason = _reasonController.text.trim();
    if (permissions.lateWindow && reason.length < 3) {
      _showError('Ange en orsak till den sena korrigeringen (minst 3 tecken).');
      return;
    }
    final changes = <Map<String, dynamic>>[];
    for (final entry in _stagedStatus.entries) {
      final person = widget.squad.roster.where((item) => item.personId == entry.key).firstOrNull;
      if (person == null) continue;
      changes.add({
        'person_id': entry.key,
        'status': entry.value,
        'expected_revision': person.attendanceRevision,
        if (entry.value == 'late' || entry.value == 'partial')
          'minutes': _stagedMinutes[entry.key],
      });
    }
    if (changes.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.calendar.recordAttendance(
        eventId: widget.event.id,
        changes: changes,
        correctionReason: permissions.lateWindow ? reason : null,
        idempotencyKey: _newUuid(),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.feature('Närvaron har sparats.'))));
      }
      widget.onReload();
    } catch (_) {
      if (mounted) _showError('Närvaron kunde inte sparas. Ladda om och försök igen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).feature(message))));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final roster = widget.squad.roster;
    int priority(EventRosterPerson person) => switch (person.callupState) {
      'accepted' => 0,
      'declined' => 2,
      _ => 1,
    };
    List<EventRosterPerson> called(String role) =>
        roster.where((person) => person.isCalled && person.rolePackage == role).toList()
          ..sort((a, b) {
            final byPriority = priority(a).compareTo(priority(b));
            return byPriority != 0 ? byPriority : a.name.compareTo(b.name);
          });
    List<EventRosterPerson> uncalled(String role) =>
        roster.where((person) => !person.isCalled && person.rolePackage == role).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_canManage) ...[
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: strings.feature(
                        'Sök spelare eller lag i hela klubben',
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchController.clear(),
                            ),
                    ),
                  ),
                  if (_matches.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(top: 4),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final candidate in _matches)
                              _SelectableRow(
                                title: candidate.name,
                                subtitle: [
                                  if (candidate.teamName != null) candidate.teamName!,
                                  if (candidate.rolePackage != null)
                                    strings.domainValue(candidate.rolePackage!),
                                ].join(' · '),
                                selected: _draftMemberIds.contains(candidate.personId),
                                onTap: _busy
                                    ? null
                                    : () => _toggleDraftMember(candidate.personId),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (widget.squad.can('send_callups') && _draftMemberIds.isNotEmpty)
                    FilledButton.icon(
                      onPressed: _busy ? null : _sendCallups,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(
                        widget.squad.dispatchKind == 'late'
                            ? strings.feature('Skicka sena kallelser')
                            : strings.feature('Skicka kallelser'),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                if (_eventEnded && _canRecordAttendance && _stagedStatus.isNotEmpty) ...[
                  if (_resolvedPermissions?.lateWindow ?? false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _reasonController,
                        maxLength: 500,
                        decoration: InputDecoration(
                          labelText: strings.feature('Orsak till sen korrigering'),
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _saveAttendance,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(strings.feature('Spara närvaro')),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        _rosterSection(
          strings.feature('Kallade spelare'),
          called('player'),
        ),
        _rosterSection(
          strings.feature('Kallade ledare'),
          called('leader'),
        ),
        _rosterSection(
          strings.feature('Okallade spelare'),
          uncalled('player'),
        ),
        _rosterSection(
          strings.feature('Okallade ledare'),
          uncalled('leader'),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _rosterSection(String title, List<EventRosterPerson> people) {
    if (people.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        SliverList.builder(
          itemCount: people.length,
          itemBuilder: (context, index) => _RosterRow(
            person: people[index],
            eventEnded: _eventEnded,
            canManage: _canManage,
            canRecordAttendance: _canRecordAttendance,
            canRemindOrCancel: widget.squad.can('remind_callup') || widget.squad.can('cancel_callup'),
            busy: _busy,
            stagedStatus: _stagedStatus[people[index].personId],
            onToggleDraft: () => _toggleDraftMember(people[index].personId),
            onManageCallup: (action) => _manageCallup(people[index], action),
            onSetAttendance: (status) => _setAttendance(people[index], status),
          ),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.person,
    required this.eventEnded,
    required this.canManage,
    required this.canRecordAttendance,
    required this.canRemindOrCancel,
    required this.busy,
    required this.stagedStatus,
    required this.onToggleDraft,
    required this.onManageCallup,
    required this.onSetAttendance,
  });

  final EventRosterPerson person;
  final bool eventEnded, canManage, canRecordAttendance, canRemindOrCancel, busy;
  final String? stagedStatus;
  final VoidCallback onToggleDraft;
  final ValueChanged<String> onManageCallup;
  final ValueChanged<String> onSetAttendance;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final subtitle = [
      person.teamName,
      strings.domainValue(person.rolePackage),
    ].join(' · ');

    if (eventEnded) {
      if (!person.isCalled) {
        return ListTile(
          title: Text(person.name),
          subtitle: Text(subtitle),
          trailing: canRecordAttendance
              ? Text(
                  strings.feature('Aldrig kallad'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
        );
      }
      final current = stagedStatus ?? person.attendanceStatus ?? 'unknown';
      return ListTile(
        title: Text(person.name),
        subtitle: Text(subtitle),
        trailing: canRecordAttendance
            ? DropdownButton<String>(
                value: current,
                onChanged: busy ? null : (value) => onSetAttendance(value!),
                items: [
                  for (final status in const [
                    'unknown',
                    'present',
                    'late',
                    'partial',
                    'absent',
                  ])
                    DropdownMenuItem(
                      value: status,
                      child: Text(strings.domainValue(status)),
                    ),
                ],
              )
            : Text(strings.domainValue(current)),
      );
    }

    if (person.isCalled) {
      return ListTile(
        title: Text(person.name),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CallupStateBadge(state: person.callupState ?? 'pending'),
            if (canRemindOrCancel)
              PopupMenuButton<String>(
                tooltip: strings.feature('Hantera kallelse'),
                onSelected: busy ? null : onManageCallup,
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'remind', child: Text(strings.feature('Påminn'))),
                  PopupMenuItem(value: 'cancel', child: Text(strings.feature('Återkalla'))),
                ],
              ),
          ],
        ),
      );
    }

    return _SelectableRow(
      title: person.name,
      subtitle: subtitle,
      selected: person.inDraft,
      onTap: canManage && !busy ? onToggleDraft : null,
    );
  }
}

/// A row selected by tapping anywhere on it — the whole row tints with the
/// theme's accent color when selected — rather than a separate checkbox,
/// used both for the search results dropdown and the roster's draft rows.
class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: colors.primaryContainer,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle, color: colors.primary)
          : Icon(Icons.circle_outlined, color: colors.outlineVariant),
    );
  }
}

class _CallupStateBadge extends StatelessWidget {
  const _CallupStateBadge({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final color = switch (state) {
      'accepted' => Colors.green,
      'declined' => Colors.red,
      _ => Colors.amber.shade800,
    };
    return Chip(
      label: Text(strings.domainValue(state)),
      backgroundColor: color.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: color),
      side: BorderSide.none,
    );
  }
}
