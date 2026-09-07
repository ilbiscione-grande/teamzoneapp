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

class _EventDetailsBodyState extends State<_EventDetailsBody>
    with SingleTickerProviderStateMixin {
  // Seeded once from the page's initial load, then updated in place by
  // _refresh() after an action — never by tearing this widget down and
  // rebuilding it, which used to reset the active tab back to Info and
  // lose the Deltagare tab's search/staged-edit state on every single
  // draft toggle ("varje gång jag trycker på en checkbox så laddar sidan
  // om och jag måste gå in på deltagare igen").
  late EventDetails event = widget.initialEvent;
  late SquadDetails squad = widget.initialSquad;

  // An explicit controller (rather than DefaultTabController) so the
  // "Skicka kallelser" FAB knows which tab is active and the header can
  // track the swipe animation to shrink itself on every tab but Info.
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  )..addListener(_handleTabIndexChanged);

  bool _sendingCallups = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onTitleChanged(event.title),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabIndexChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabIndexChanged() {
    // Fires once the swipe/tap settles on a new tab — enough to show or
    // hide the "Skicka kallelser" FAB without rebuilding every frame.
    if (!_tabController.indexIsChanging) setState(() {});
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

  /// People currently drafted but not yet called — the ones a tap on
  /// "Skicka kallelser" would actually notify. Already-called members
  /// stay in the draft list too, so counting the raw draft is not enough.
  int get _pendingCallupCount => [
    ...squad.roster,
    ..._guestRosterFor(squad),
  ].where((person) => person.inDraft && !person.isCalled).length;

  /// The current actor's own callup for this event, if any — responseRole
  /// 'self' uniquely identifies it regardless of the actor's role package
  /// (a leader can be called up too). Read-only here: shown on Info so
  /// it's visible everywhere, but only actually respondable from the
  /// Deltagare tab, alongside everyone else's.
  EventRosterPerson? get _myCallup =>
      [...squad.roster, ..._guestRosterFor(squad)]
          .where((person) => person.isCalled && person.responseRole == 'self')
          .firstOrNull;

  Future<void> _sendCallups() async {
    final revisionId = squad.squadRevisionId;
    if (revisionId == null) return;
    setState(() => _sendingCallups = true);
    try {
      // send_callups_for_actor requires the squad to already be 'locked'
      // (it rejects a 'draft' revision outright) — a step the old
      // "Hantera urval" flow had its own button for, that this rebuild
      // never wired up, so every send failed. Skipped when already
      // locked (a prior send attempt that locked but then failed before
      // actually sending, say), never re-locked from 'sent'/'empty'.
      final draftRevision = squad.revision;
      if (squad.state == 'draft' && draftRevision != null) {
        await widget.calendar.lockSquad(
          eventId: widget.eventId,
          expectedRevision: draftRevision,
          idempotencyKey: _newUuid(),
        );
      }
      await widget.calendar.sendCallups(
        squadRevisionId: revisionId,
        expiry: DateTime.now().add(const Duration(days: 7)),
        idempotencyKey: _newUuid(),
      );
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Kallelserna kunde inte skickas. Ladda om och försök igen.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingCallups = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final pendingCount = _pendingCallupCount;
    final showSendFab =
        _tabController.index == 1 &&
        squad.can('send_callups') &&
        pendingCount > 0;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: !showSendFab
          ? null
          : FloatingActionButton.extended(
              onPressed: _sendingCallups ? null : _sendCallups,
              icon: _sendingCallups
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Badge(
                      label: Text('$pendingCount'),
                      child: const Icon(Icons.send_outlined),
                    ),
              label: Text(
                squad.dispatchKind == 'late'
                    ? strings.feature('Skicka sena kallelser')
                    : strings.feature('Skicka kallelser'),
              ),
            ),
      floatingActionButtonLocation: _leftOfAssistantFabLocation,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mirrors the reference app's header-collapse: the status
          // circles shrink and the surrounding padding tightens on every
          // tab except Info, tracking the swipe itself rather than
          // snapping once the tab settles.
          AnimatedBuilder(
            animation: _tabController.animation!,
            builder: (context, child) {
              final expanded =
                  (1 - _tabController.animation!.value.clamp(0.0, 1.0)).clamp(
                    0.0,
                    1.0,
                  );
              return Padding(
                padding: EdgeInsets.fromLTRB(20, 8 + 4 * expanded, 20, 0),
                child: Transform.scale(
                  scale: 0.82 + 0.18 * expanded,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              );
            },
            child: _StatusHeaderRow(event: event, squad: squad),
          ),
          const SizedBox(height: 4),
          TabBar(
            controller: _tabController,
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
              controller: _tabController,
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
        if (_myCallup != null)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(strings.feature('Din kallelse')),
              subtitle: Text(
                strings.domainValue(_myCallup!.callupState ?? 'pending'),
              ),
              trailing: TextButton(
                onPressed: () => _tabController.animateTo(1),
                child: Text(strings.feature('Svara')),
              ),
            ),
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
            onPressed: () => _tabController.animateTo(1),
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
            onPressed: () => _tabController.animateTo(1),
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
      if (mounted)
        _showError(
          'Eventet ändrades av någon annan. Ladda om och försök igen.',
        );
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
      if (mounted)
        _showError(
          'Eventet ändrades av någon annan. Ladda om och försök igen.',
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.feature('Utkastet har tagits bort.'))),
      );
      widget.onDeleted();
    } catch (_) {
      if (mounted) {
        _showError(
          'Utkastet kan inte tas bort. Det kan ha ändrats eller fått historik.',
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.feature('Eventet har arkiverats.'))),
      );
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
                ? Text(
                    strings.feature(
                      'Det finns inga andra aktiva lag i klubben.',
                    ),
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
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Rättighet',
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'none',
                                    child: Text(
                                      strings.feature('Ingen delning'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'view',
                                    child: Text(strings.feature('Kan se')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'manage_roster',
                                    child: Text(
                                      strings.feature('Kan hantera deltagare'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'co_manage',
                                    child: Text(
                                      strings.feature(
                                        'Kan samredigera eventet',
                                      ),
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
                                  strings.feature(
                                    'Mottagare (ger endast synlighet)',
                                  ),
                                ),
                                Wrap(
                                  children:
                                      const {
                                        'players': 'Spelare',
                                        'leaders': 'Ledare',
                                        'guardians': 'Vårdnadshavare',
                                      }.entries.map((entry) {
                                        return FilterChip(
                                          label: Text(entry.value),
                                          selected: audiences[team.teamId]!
                                              .contains(entry.key),
                                          onSelected: saving
                                              ? null
                                              : (
                                                  selected,
                                                ) => setDialogState(() {
                                                  selected
                                                      ? audiences[team.teamId]!
                                                            .add(entry.key)
                                                      : audiences[team.teamId]!
                                                            .remove(entry.key);
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
                                strings.feature('Delningen har sparats.'),
                              ),
                            ),
                          );
                          unawaited(_refresh());
                        }
                      } catch (_) {
                        setDialogState(() => saving = false);
                        if (mounted)
                          _showError(
                            'Delningen kunde inte sparas. Ladda om och försök igen.',
                          );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).feature(message))),
    );
  }
}

/// squad.roster only covers people with an active assignment on the
/// event's own team(s) — someone added via the club-wide search who isn't
/// on that roster (a cross-team/guest pick) has no assignment row to join
/// against, so the roster RPC can't see them at all. Without this, such a
/// person vanished from the tab (and the status counts) entirely the
/// moment they were added — nowhere to see their callup status or
/// un-select them. Synthesized here from squad.members/callups/attendance
/// instead, and shown as its own "Gästspelare" section — found while
/// comparing against the reference implementation's older Teamzone
/// project. Shared between the status header (all tabs) and the
/// Deltagare tab's roster list so both count/show the same people.
List<EventRosterPerson> _guestRosterFor(SquadDetails squad) {
  final rosterIds = squad.roster.map((p) => p.personId).toSet();
  final guests = <String, EventRosterPerson>{};
  for (final member in squad.members) {
    if (rosterIds.contains(member.personId)) continue;
    guests[member.personId] = EventRosterPerson(
      personId: member.personId,
      name: member.name,
      teamId: '',
      teamName: '',
      rolePackage: 'player',
      inDraft: true,
      isGuest: true,
    );
  }
  for (final callup in squad.callups) {
    if (rosterIds.contains(callup.personId)) continue;
    final existing = guests[callup.personId];
    guests[callup.personId] =
        (existing ??
                EventRosterPerson(
                  personId: callup.personId,
                  name: callup.name,
                  teamId: '',
                  teamName: '',
                  rolePackage: 'player',
                  inDraft: false,
                  isGuest: true,
                ))
            .copyWith(
              callupId: callup.id,
              callupState: callup.state,
              callupExpiresAt: callup.expiresAt,
              callupLastRemindedAt: callup.lastRemindedAt,
              canRespond: callup.canRespond,
              responseRole: callup.responseRole,
            );
  }
  for (final attendance in squad.attendance) {
    final existing = guests[attendance.personId];
    if (existing == null || rosterIds.contains(attendance.personId)) continue;
    guests[attendance.personId] = existing.copyWith(
      attendanceStatus: attendance.status,
      attendanceRevision: attendance.revision,
    );
  }
  return guests.values.toList()..sort((a, b) => a.name.compareTo(b.name));
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
    final roster = [...squad.roster, ..._guestRosterFor(squad)];
    final draft = roster.where((p) => p.inDraft).length;
    final called = roster.where((p) => p.isCalled).length;
    final accepted = roster.where((p) => p.callupState == 'accepted').length;
    final declined = roster.where((p) => p.callupState == 'declined').length;
    final unanswered = roster
        .where(
          (p) =>
              p.isCalled &&
              p.callupState != 'accepted' &&
              p.callupState != 'declined',
        )
        .length;
    final attended = roster
        .where(
          (p) =>
              p.attendanceStatus == 'present' ||
              p.attendanceStatus == 'late' ||
              p.attendanceStatus == 'partial',
        )
        .length;
    // Labels take real width across up to six circles — dropped below the
    // tablet breakpoint (a phone in portrait can't fit six labeled circles
    // without wrapping awkwardly), keeping just the numbers, which still
    // read fine at a glance; a tooltip on each circle covers the rest.
    final showLabels =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    final circles = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusCircle(
          count: draft,
          label: strings.feature('Utkast'),
          color: Colors.blueGrey,
          showLabel: showLabels,
        ),
        _StatusCircle(
          count: called,
          label: strings.feature('Kallade'),
          color: Colors.indigo,
          showLabel: showLabels,
        ),
        _StatusCircle(
          count: accepted,
          label: strings.domainValue('accepted'),
          color: Colors.green,
          showLabel: showLabels,
        ),
        _StatusCircle(
          count: unanswered,
          label: strings.feature('Obesvarade'),
          color: Colors.amber.shade800,
          showLabel: showLabels,
        ),
        _StatusCircle(
          count: declined,
          label: strings.domainValue('declined'),
          color: Colors.red,
          showLabel: showLabels,
        ),
        if (_hasEnded)
          _StatusCircle(
            count: attended,
            label: strings.feature('Deltog'),
            color: Colors.teal,
            showLabel: showLabels,
          ),
      ],
    );
    // Centered when it fits; the min-width constraint still lets the row
    // grow past the viewport (and scroll) on a narrow phone with six
    // labeled circles instead of clipping or wrapping awkwardly.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Center(child: circles),
        ),
      ),
    );
  }
}

class _StatusCircle extends StatelessWidget {
  const _StatusCircle({
    required this.count,
    required this.label,
    required this.color,
    required this.showLabel,
  });
  final int count;
  final String label;
  final Color color;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: Tooltip(
      message: label,
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              '$count',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
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
  // Future<void>, not VoidCallback: every caller below needs to await this
  // before clearing its own busy flag. A fire-and-forget reload used to let
  // a second tap (trivial to land now that a whole row is one tap target)
  // slip in on the still-stale widget.squad — its member list and revision
  // hadn't caught up yet — which the server then rightly rejected as a
  // stale_revision conflict, surfacing as a generic "kunde inte sparas".
  final Future<void> Function() onReload;

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

  bool _busyBulk = false;

  bool get _canManage => widget.squad.can('save_squad');
  bool get _canRecordAttendance => widget.squad.can('record_attendance');
  bool get _eventEnded =>
      DateTime.now().toUtc().isAfter(widget.event.endsAt.toUtc());
  Set<String> get _draftMemberIds =>
      widget.squad.members.map((member) => member.personId).toSet();

  List<EventRosterPerson> get _guestRoster => _guestRosterFor(widget.squad);

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
      final candidates = await widget.calendar.listSquadCandidates(
        widget.event.id,
      );
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
        expectedRevision: widget.squad.state == 'draft'
            ? widget.squad.revision
            : null,
        idempotencyKey: _newUuid(),
      );
      await widget.onReload();
    } catch (_) {
      if (mounted)
        _showError('Ändringen kunde inte sparas. Ladda om och försök igen.');
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
            widget.squad.callups
                .where((callup) => callup.id == callupId)
                .map((callup) => callup.revision)
                .firstOrNull ??
            0,
        idempotencyKey: _newUuid(),
      );
      await widget.onReload();
    } catch (_) {
      if (mounted)
        _showError('Åtgärden kunde inte utföras. Ladda om och försök igen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Responds to a callup — the person's own ('self'), or, for whoever
  /// can already manage the squad, anyone else's on the roster too
  /// ('manager' — same capability that already gates remind/cancel,
  /// covering both spelare and ledare buckets uniformly).
  Future<void> _respondToCallup(
    EventRosterPerson person,
    String response,
  ) async {
    final callupId = person.callupId;
    if (callupId == null) return;
    String? reasonCode;
    String? reasonText;
    if (response == 'declined') {
      final reason = await _declineCallupReasonDialog(context);
      if (reason == null || !mounted) return;
      reasonCode = reason.$1;
      reasonText = reason.$2;
    }
    setState(() => _busy = true);
    try {
      await widget.calendar.respondCallup(
        callupId: callupId,
        response: response,
        actingAsPersonId: person.responseRole == 'self'
            ? null
            : person.personId,
        declineReasonCode: reasonCode,
        declineReasonText: reasonText,
        expectedRevision:
            widget.squad.callups
                .where((callup) => callup.id == callupId)
                .map((callup) => callup.revision)
                .firstOrNull ??
            0,
        idempotencyKey: _newUuid(),
      );
      await widget.onReload();
    } catch (_) {
      if (mounted)
        _showError('Svaret kunde inte sparas. Ladda om och försök igen.');
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
    final everyone = [...widget.squad.roster, ..._guestRoster];
    final changes = <Map<String, dynamic>>[];
    for (final entry in _stagedStatus.entries) {
      final person = everyone
          .where((item) => item.personId == entry.key)
          .firstOrNull;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.feature('Närvaron har sparats.'))),
        );
      }
      await widget.onReload();
    } catch (_) {
      if (mounted)
        _showError('Närvaron kunde inte sparas. Ladda om och försök igen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Bulk actions (behind the "..." menu) ──────────────────────────────
  // Inspired by the reference implementation's "Välj alla"/"Påminn alla"/
  // "Sätt alla deltog" — one tap instead of one tap per person.

  /// Adds every not-yet-called, not-yet-drafted player (not leaders — a
  /// coach calls up players to play; leaders are added individually)
  /// straight to the draft in a single save.
  Future<void> _selectAllPlayers() async {
    final toAdd = widget.squad.roster
        .where((p) => p.rolePackage == 'player' && !p.isCalled && !p.inDraft)
        .map((p) => p.personId);
    if (toAdd.isEmpty) return;
    final ids = _draftMemberIds..addAll(toAdd);
    setState(() => _busyBulk = true);
    try {
      await widget.calendar.saveSquadDraft(
        eventId: widget.event.id,
        memberIds: ids.toList(),
        source: 'manual',
        expectedRevision: widget.squad.state == 'draft'
            ? widget.squad.revision
            : null,
        idempotencyKey: _newUuid(),
      );
      await widget.onReload();
    } catch (_) {
      if (mounted)
        _showError('Ändringen kunde inte sparas. Ladda om och försök igen.');
    } finally {
      if (mounted) setState(() => _busyBulk = false);
    }
  }

  /// Reminds everyone whose callup is actually due one (mirrors
  /// EventRosterPerson.canRemindAt — pending, not expired, past the 6h
  /// cooldown) instead of everyone with a pending response.
  Future<void> _remindAllUnanswered() async {
    final now = DateTime.now();
    final eligible = [
      ...widget.squad.roster,
      ..._guestRoster,
    ].where((person) => person.canRemindAt(now)).toList();
    if (eligible.isEmpty) return;
    setState(() => _busyBulk = true);
    try {
      await Future.wait(
        eligible.map(
          (person) => widget.calendar.manageCallup(
            callupId: person.callupId!,
            action: 'remind',
            expectedRevision:
                widget.squad.callups
                    .where((callup) => callup.id == person.callupId)
                    .map((callup) => callup.revision)
                    .firstOrNull ??
                0,
            idempotencyKey: _newUuid(),
          ),
        ),
      );
      await widget.onReload();
    } catch (_) {
      if (mounted) {
        _showError(
          'Några påminnelser kunde inte skickas. Ladda om och försök igen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busyBulk = false);
    }
  }

  /// Stages "present" for everyone whose callup was accepted but has no
  /// attendance mark yet — never overwrites an existing mark. Saves
  /// immediately unless a late-correction reason is required, in which
  /// case it only stages so the leader can fill that in first.
  Future<void> _markAllAcceptedAsPresent() async {
    final candidates = [...widget.squad.roster, ..._guestRoster].where(
      (person) =>
          person.callupState == 'accepted' &&
          (person.attendanceStatus == null ||
              person.attendanceStatus == 'unknown'),
    );
    if (candidates.isEmpty) return;
    setState(() {
      for (final person in candidates) {
        _stagedStatus[person.personId] = 'present';
        _stagedMinutes.remove(person.personId);
      }
    });
    if (!(_resolvedPermissions?.lateWindow ?? false)) {
      await _saveAttendance();
    }
  }

  Future<void> _showBulkActionsSheet() async {
    final strings = AppStrings.of(context);
    final now = DateTime.now();
    final everyone = [...widget.squad.roster, ..._guestRoster];
    final selectableCount = widget.squad.roster
        .where(
          (person) =>
              person.rolePackage == 'player' &&
              !person.isCalled &&
              !person.inDraft,
        )
        .length;
    final remindableCount = everyone
        .where((person) => person.canRemindAt(now))
        .length;
    final attendanceCandidateCount = everyone
        .where(
          (person) =>
              person.callupState == 'accepted' &&
              (person.attendanceStatus == null ||
                  person.attendanceStatus == 'unknown'),
        )
        .length;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canManage)
              ListTile(
                leading: const Icon(Icons.library_add_check_outlined),
                title: Text(strings.selectAllPlayersLabel(selectableCount)),
                enabled: selectableCount > 0 && !_busyBulk,
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_selectAllPlayers());
                },
              ),
            if (!_eventEnded && widget.squad.can('remind_callup'))
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(strings.remindAllUnansweredLabel(remindableCount)),
                enabled: remindableCount > 0 && !_busyBulk,
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_remindAllUnanswered());
                },
              )
            else if (_eventEnded && _canRecordAttendance)
              ListTile(
                leading: const Icon(Icons.how_to_reg_outlined),
                title: Text(
                  strings.markAllPresentLabel(attendanceCandidateCount),
                ),
                enabled: attendanceCandidateCount > 0 && !_busyBulk,
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_markAllAcceptedAsPresent());
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).feature(message))),
    );
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
        roster
            .where((person) => person.isCalled && person.rolePackage == role)
            .toList()
          ..sort((a, b) {
            final byPriority = priority(a).compareTo(priority(b));
            return byPriority != 0 ? byPriority : a.name.compareTo(b.name);
          });
    List<EventRosterPerson> uncalled(String role) =>
        roster
            .where((person) => !person.isCalled && person.rolePackage == role)
            .toList()
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
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
                      ),
                      const SizedBox(width: 8),
                      // Bulk actions ("Välj alla"/"Påminn alla"/"Sätt alla
                      // deltog") — a coach otherwise has to repeat the same
                      // tap once per person on the roster.
                      IconButton.outlined(
                        tooltip: strings.feature('Fler åtgärder'),
                        onPressed: _busyBulk ? null : _showBulkActionsSheet,
                        icon: _busyBulk
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.more_vert),
                      ),
                    ],
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
                                  if (candidate.teamName != null)
                                    candidate.teamName!,
                                  if (candidate.rolePackage != null)
                                    strings.domainValue(candidate.rolePackage!),
                                ].join(' · '),
                                selected: _draftMemberIds.contains(
                                  candidate.personId,
                                ),
                                onTap: _busy
                                    ? null
                                    : () => _toggleDraftMember(
                                        candidate.personId,
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                if (_eventEnded &&
                    _canRecordAttendance &&
                    _stagedStatus.isNotEmpty) ...[
                  if (_resolvedPermissions?.lateWindow ?? false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _reasonController,
                        maxLength: 500,
                        decoration: InputDecoration(
                          labelText: strings.feature(
                            'Orsak till sen korrigering',
                          ),
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
        _rosterSection(strings.feature('Kallade spelare'), called('player')),
        _rosterSection(strings.feature('Kallade ledare'), called('leader')),
        _rosterSection(strings.feature('Okallade spelare'), uncalled('player')),
        _rosterSection(strings.feature('Okallade ledare'), uncalled('leader')),
        _rosterSection(strings.feature('Gästspelare'), _guestRoster),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _rosterSection(String title, List<EventRosterPerson> people) {
    if (people.isEmpty)
      return const SliverToBoxAdapter(child: SizedBox.shrink());
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
          itemBuilder: (context, index) => Padding(
            // A little breathing room between rows now that each row's
            // own padding is tighter.
            padding: const EdgeInsets.only(bottom: 2),
            child: _RosterRow(
              person: people[index],
              eventEnded: _eventEnded,
              canManage: _canManage,
              canRecordAttendance: _canRecordAttendance,
              canRemind: widget.squad.can('remind_callup'),
              canCancel: widget.squad.can('cancel_callup'),
              busy: _busy,
              stagedStatus: _stagedStatus[people[index].personId],
              onToggleDraft: () => _toggleDraftMember(people[index].personId),
              onManageCallup: (action) => _manageCallup(people[index], action),
              onRespond: (response) =>
                  _respondToCallup(people[index], response),
              onSetAttendance: (status) =>
                  _setAttendance(people[index], status),
            ),
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
    required this.canRemind,
    required this.canCancel,
    required this.busy,
    required this.stagedStatus,
    required this.onToggleDraft,
    required this.onManageCallup,
    required this.onRespond,
    required this.onSetAttendance,
  });

  final EventRosterPerson person;
  final bool eventEnded,
      canManage,
      canRecordAttendance,
      canRemind,
      canCancel,
      busy;
  final String? stagedStatus;
  final VoidCallback onToggleDraft;
  final ValueChanged<String> onManageCallup;
  final ValueChanged<String> onRespond;
  final ValueChanged<String> onSetAttendance;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final subtitle = [
      if (person.isGuest) strings.feature('Gäst') else person.teamName,
      strings.domainValue(person.rolePackage),
    ].join(' · ');

    final textTheme = Theme.of(context).textTheme;

    if (eventEnded) {
      if (!person.isCalled) {
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(person.name, style: textTheme.bodyMedium),
          subtitle: Text(subtitle, style: textTheme.bodySmall),
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
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(person.name, style: textTheme.bodyMedium),
        subtitle: Text(subtitle, style: textTheme.bodySmall),
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
      // Mirrors the server's own remind_callup_for_actor gate (pending,
      // not expired, 6h since the last reminder) so a doomed-to-fail tap
      // is never offered in the first place.
      final canRemindNow = canRemind && person.canRemindAt(DateTime.now());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(person.name, style: textTheme.bodyMedium),
            subtitle: Text(subtitle, style: textTheme.bodySmall),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CallupStateBadge(state: person.callupState ?? 'pending'),
                if (canRemindNow || canCancel)
                  PopupMenuButton<String>(
                    tooltip: strings.feature('Hantera kallelse'),
                    onSelected: busy ? null : onManageCallup,
                    itemBuilder: (_) => [
                      if (canRemindNow)
                        PopupMenuItem(
                          value: 'remind',
                          child: Text(strings.feature('Påminn')),
                        ),
                      if (canCancel)
                        PopupMenuItem(
                          value: 'cancel',
                          child: Text(strings.feature('Återkalla')),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          // Respond controls: the person's own callup ('self'), or —
          // same as remind/cancel above — anyone else's on the roster
          // for whoever can manage the squad ('manager').
          if (person.canRespond)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _CallupResponseButtons(
                busy: busy,
                saving: false,
                onRespond: onRespond,
              ),
            ),
        ],
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
/// Built on Material+InkWell (rather than ListTile) so the entire row is
/// unambiguously one tap target, not just the trailing icon.
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
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: selected ? colors.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.bodyMedium),
                    Text(subtitle, style: textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? colors.primary : colors.outlineVariant,
              ),
            ],
          ),
        ),
      ),
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
