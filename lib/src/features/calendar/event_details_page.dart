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
    required this.roster,
    required this.match,
    required this.matchSpaceV2,
    required this.onNavigate,
    this.initialParticipants = false,
    this.initialPreparation = false,
    this.onChanged,
    super.key,
  });

  final String eventId;
  final bool initialParticipants;
  final bool initialPreparation;
  final VoidCallback? onChanged;
  final TeamZoneContext contextValue;
  final CalendarServices calendar;
  final RosterServices roster;
  final MatchServices match;
  final bool matchSpaceV2;
  final ValueChanged<String> onNavigate;

  @override
  State<_EventDetailsPage> createState() => _EventDetailsPageState();
}

/// One entry in the event's "⋮" menu. The body owns the actions (they
/// depend on its live event state); the page's app bar only shows them.
typedef _EventMenuAction = ({
  String key,
  IconData icon,
  String label,
  VoidCallback onTap,
  bool? checked,
});

class _EventDetailsPageState extends State<_EventDetailsPage> {
  Future<(EventDetails, SquadDetails)>? _load;
  final _menu = ValueNotifier<List<_EventMenuAction>>(const []);

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

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
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_title != null)
              Text(_title!, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${widget.contextValue.clubName} · ${widget.contextValue.teamName ?? "Aktivitet"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<List<_EventMenuAction>>(
            valueListenable: _menu,
            builder: (context, actions, _) => actions.isEmpty
                ? const SizedBox.shrink()
                : PopupMenuButton<_EventMenuAction>(
                    key: const Key('event-actions-menu'),
                    tooltip: strings.feature('Åtgärder för eventet'),
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) => action.onTap(),
                    itemBuilder: (_) => [
                      for (final action in actions)
                        action.checked == null
                            ? PopupMenuItem(
                                key: ValueKey('event-action-${action.key}'),
                                value: action,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(action.icon),
                                  title: Text(action.label),
                                ),
                              )
                            : CheckedPopupMenuItem(
                                key: ValueKey('event-action-${action.key}'),
                                value: action,
                                checked: action.checked!,
                                child: Text(action.label),
                              ),
                    ],
                  ),
          ),
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
            initialParticipants: widget.initialParticipants,
            initialPreparation: widget.initialPreparation,
            onChanged: widget.onChanged,
            initialEvent: event,
            initialSquad: squad,
            eventId: widget.eventId,
            contextValue: widget.contextValue,
            calendar: widget.calendar,
            roster: widget.roster,
            match: widget.match,
            matchSpaceV2: widget.matchSpaceV2,
            onDeleted: _goBackToCalendar,
            onTitleChanged: _updateTitle,
            menu: _menu,
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
    required this.roster,
    required this.match,
    required this.matchSpaceV2,
    required this.onDeleted,
    required this.onTitleChanged,
    required this.menu,
    this.initialParticipants = false,
    this.initialPreparation = false,
    this.onChanged,
    super.key,
  });

  final EventDetails initialEvent;
  final bool initialParticipants;
  final bool initialPreparation;
  final VoidCallback? onChanged;
  final SquadDetails initialSquad;
  final String eventId;
  final TeamZoneContext contextValue;
  final CalendarServices calendar;
  final RosterServices roster;
  final MatchServices match;
  final bool matchSpaceV2;
  final VoidCallback onDeleted;
  final ValueChanged<String> onTitleChanged;
  final ValueNotifier<List<_EventMenuAction>> menu;

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
    initialIndex: widget.initialPreparation
        ? 2
        : widget.initialParticipants
        ? 1
        : 0,
    vsync: this,
  )..addListener(_handleTabIndexChanged);

  MatchSnapshot? _matchSnapshot;
  WrittenMatchReport? _report;
  bool _matchLoaded = false;
  String _menuSignature = '';
  bool _savingCallupRequirement = false;
  ({bool value, int revision, String key})? _callupRequirementCommand;

  Future<void> _setCallupsRequired(bool value) async {
    if (_savingCallupRequirement) return;
    final previous = _callupRequirementCommand;
    final command = previous != null && previous.value == value
        ? previous
        : (value: value, revision: event.revision, key: _newUuid());
    _callupRequirementCommand = command;
    setState(() => _savingCallupRequirement = true);
    try {
      await widget.calendar.reviseEvent(
        eventId: event.id,
        scope: 'one',
        patch: {'callups_required': command.value},
        expectedRevision: command.revision,
        idempotencyKey: command.key,
      );
      _callupRequirementCommand = null;
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kallelsebehovet kunde inte sparas. Försök igen eller öppna aktiviteten på nytt.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCallupRequirement = false);
    }
  }

  Map<String, dynamic>? get _activeTeamRelation {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) return null;
    return event.teams.cast<Map<String, dynamic>?>().firstWhere(
      (team) => team?['team_id'] == teamId,
      orElse: () => null,
    );
  }

  bool get _activeContextIsPrimary =>
      _activeTeamRelation?['relation'] == 'primary';

  Set<String> get _activeSharedCapabilities =>
      (_activeTeamRelation?['capabilities'] as List? ?? const [])
          .whereType<String>()
          .toSet();

  // A user's stronger role in another team must not leak into the event
  // while a shared recipient team is the active context.
  bool get _contextCanManageRoster =>
      event.archivedAt == null &&
      (widget.contextValue.teamId == null ||
          _activeContextIsPrimary ||
          _activeSharedCapabilities.contains('manage_roster') ||
          _activeSharedCapabilities.contains('co_manage'));

  bool get _contextCanCoManage =>
      event.archivedAt == null &&
      (widget.contextValue.teamId == null ||
          _activeContextIsPrimary ||
          _activeSharedCapabilities.contains('co_manage'));

  bool get _contextCanRestoreArchive =>
      event.archivedAt != null &&
      (widget.contextValue.teamId == null || _activeContextIsPrimary);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onTitleChanged(event.title),
    );
    unawaited(_loadMatch());
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
        widget.onChanged?.call();
        await _loadMatch();
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

  EventRosterPerson? get _myCallup =>
      [...squad.roster, ..._guestRosterFor(squad)]
          .where((person) => person.isCalled && person.responseRole == 'self')
          .firstOrNull;

  Future<void> _refreshParticipants() async {
    final updated = await widget.calendar.getEventSquad(widget.eventId);
    if (mounted) {
      setState(() {
        squad = updated;
      });
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    _publishMenu(strings);
    final resultHeader = _resultHeader();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?resultHeader,
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
              final scale = 0.82 + 0.18 * expanded;
              return Padding(
                padding: EdgeInsets.fromLTRB(20, 8 + 4 * expanded, 20, 0),
                // Transform.scale only shrinks the paint; heightFactor
                // shrinks the layout too, so the gap to the tab row stays
                // constant and the tabs move up with the circles.
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: scale,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
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
                  onReload: _refreshParticipants,
                  roster: widget.roster,
                  clubId: widget.contextValue.clubId,
                  allowManage: _contextCanManageRoster,
                  allowAttendance: _contextCanManageRoster,
                ),
                _PreparationTab(
                  key: const ValueKey('event-preparation'),
                  event: event,
                  people: [...squad.roster, ..._guestRosterFor(squad)],
                  services: widget.calendar.preparation,
                  onChanged: widget.onChanged,
                  allowEdit: _contextCanCoManage,
                  onOpenMatchMode:
                      event.preparationActions.contains(
                        EventPreparationAction.matchSpace,
                      )
                      ? _showMatchSpace
                      : null,
                ),
                _FollowupTab(
                  key: const ValueKey('event-followup-tab'),
                  event: event,
                  services: widget.calendar.preparation,
                  allowRecord: _contextCanCoManage || _contextCanManageRoster,
                  onOpenParticipants: () => _tabController.animateTo(1),
                  onOpenMatchMode:
                      event.preparationActions.contains(
                        EventPreparationAction.matchSpace,
                      )
                      ? _showMatchSpace
                      : null,
                ),
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
    final ownerTeam = event.teams.cast<Map<String, dynamic>?>().firstWhere(
      (team) => team?['relation'] == 'primary',
      orElse: () => null,
    );
    final sharedTeams = event.teams.where(
      (team) => team['relation'] != 'primary',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (event.archivedAt != null) ...[
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(strings.feature('Eventet är arkiverat')),
              subtitle: Text(
                [
                  if (event.archiveReason != null) event.archiveReason!,
                  strings.feature(
                    'Eventet är skrivskyddat men historiken finns kvar.',
                  ),
                ].join('\n'),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (event.state == 'cancelled') ...[
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.event_busy),
              title: Text(strings.feature('Eventet är inställt')),
              subtitle: Text(
                strings.feature(
                  'Information och historik finns kvar, men eventet genomförs inte.',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
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
            subtitle:
                [event.locationPitch, event.locationSurface]
                    .whereType<String>()
                    .where((part) => part.trim().isNotEmpty)
                    .isEmpty
                ? null
                : Text(
                    [event.locationPitch, event.locationSurface]
                        .whereType<String>()
                        .where((part) => part.trim().isNotEmpty)
                        .join(' · '),
                  ),
          ),
        if (event.assemblyMinutesBefore != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.group_outlined),
            title: Text(strings.feature('Samling')),
            subtitle: Text(
              '${_formatMoment(context, event.startsAt.toLocal().subtract(Duration(minutes: event.assemblyMinutesBefore!)))} · ${event.assemblyMinutesBefore} min före start',
            ),
          ),
        ..._typedInfoTiles(context, event),
        if (!event.callupsRequired)
          ListTile(
            key: const Key('event-callups-not-required'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.unsubscribe_outlined),
            title: const Text('Kallelse behövs inte'),
            subtitle: const Text(
              'Assistenten påminner inte om saknade kallelser. Ändras i menyn ⋮.',
            ),
          ),
        if (_report case final report? when report.body.isNotEmpty)
          ListTile(
            key: const Key('event-match-report'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.article_outlined),
            title: const Text('Matchrapport'),
            subtitle: Text(
              '${report.body}\n${report.published ? 'Publiceras tillsammans med synligt slutresultat' : 'Internt utkast'}',
            ),
          ),
        if (ownerTeam != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shield_outlined),
            title: Text(ownerTeam['name'] as String? ?? ''),
            subtitle: Text(strings.feature('Ägande lag')),
          ),
        for (final team in sharedTeams)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.group_outlined),
            title: Text(team['name'] as String? ?? ''),
            subtitle: Text(strings.feature('Delat med detta lag')),
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
            if (_contextCanRestoreArchive)
              FilledButton.tonalIcon(
                onPressed: _restoreArchive,
                icon: const Icon(Icons.unarchive_outlined),
                label: Text(strings.feature('Återställ från arkiv')),
              ),
            if (_contextCanCoManage &&
                event.can('cancel') &&
                event.state == 'draft')
              FilledButton.tonalIcon(
                onPressed: () => _transition('scheduled'),
                icon: const Icon(Icons.publish_outlined),
                label: Text(strings.feature('Publicera event')),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _typedInfoTiles(BuildContext context, EventDetails event) {
    final strings = AppStrings.of(context);
    final rows = <(IconData, String, String?)>[];
    switch (event.type) {
      case 'training':
        rows.addAll([
          (
            Icons.flag_outlined,
            strings.feature('Träningstema'),
            event.trainingTheme,
          ),
          (
            Icons.center_focus_strong_outlined,
            strings.feature('Fokus'),
            event.trainingFocus,
          ),
          (
            Icons.assignment_outlined,
            strings.feature('Träningsplan'),
            event.trainingPlan,
          ),
        ]);
      case 'match':
        rows.addAll([
          (
            Icons.sports_soccer,
            strings.feature('Motståndare'),
            event.opponentName,
          ),
          (
            Icons.stadium_outlined,
            strings.feature('Matchplats'),
            event.homeAway == null
                ? null
                : strings.feature(event.homeAway == 'home' ? 'Hemma' : 'Borta'),
          ),
          (
            Icons.notes_outlined,
            strings.feature('Matchanteckningar'),
            event.matchNotes,
          ),
        ]);
      case 'meeting':
        rows.addAll([
          (
            Icons.lightbulb_outline,
            strings.feature('Syfte'),
            event.meetingPurpose,
          ),
          (
            Icons.format_list_bulleted,
            strings.feature('Mötesagenda'),
            event.meetingAgenda,
          ),
        ]);
    }
    return [
      for (final row in rows)
        if (row.$3 != null && row.$3!.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(row.$1),
            title: Text(row.$2),
            subtitle: Text(row.$3!),
          ),
    ];
  }

  String _formatMoment(BuildContext context, DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(value)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
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
          'location_pitch': value.locationPitch,
          'location_surface': value.locationSurface,
          'audience_types': value.audiences,
          'assembly_minutes_before': value.assemblyMinutesBefore,
          'training_theme': value.trainingTheme,
          'training_focus': value.trainingFocus,
          'training_plan': value.trainingPlan,
          'opponent_name': value.opponentName,
          'home_away': value.homeAway,
          'match_notes': value.matchNotes,
          'meeting_purpose': value.meetingPurpose,
          'meeting_agenda': value.meetingAgenda,
        },
        expectedRevision: event.revision,
        idempotencyKey: _newUuid(),
      );
      if (mounted) unawaited(_refresh());
    } catch (_) {
      if (mounted) {
        _showError(
          'Eventet ändrades av någon annan. Ladda om och försök igen.',
        );
      }
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
      if (mounted) {
        _showError(
          'Eventet ändrades av någon annan. Ladda om och försök igen.',
        );
      }
    }
  }

  Future<void> _deleteDraft() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.feature('Ta bort eventet?')),
        content: Text(
          strings.feature(
            'Eventet tas bort helt. Det går bara när inga kallelser har skickats. Åtgärden går inte att ångra.',
          ),
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
        SnackBar(content: Text(strings.feature('Eventet har tagits bort.'))),
      );
      widget.onDeleted();
    } catch (_) {
      if (mounted) {
        _showError(
          'Eventet kan inte tas bort. Det kan ha ändrats eller fått kallelser.',
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
    disposeAfterDialog([controller]);
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

  Future<void> _restoreArchive() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.feature('Återställ från arkiv')),
        content: Text(
          strings.feature(
            'Eventet återgår till kalendern med samma status som före arkiveringen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.feature('Återställ')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.calendar.restoreArchivedEvent(
        eventId: event.id,
        expectedRevision: event.revision,
        idempotencyKey: _newUuid(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.feature('Eventet har återställts.'))),
      );
      widget.onDeleted();
    } catch (_) {
      if (mounted) _showError('Eventet kunde inte återställas.');
    }
  }

  Future<void> _showMatchSpace() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MatchModePage(
          event: event,
          squad: squad,
          match: widget.match,
          live: widget.calendar.preparation,
          readOnly: !widget.matchSpaceV2 || !_contextCanCoManage,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  // --- Match result and report (header and ⋮ menu) -------------------------

  Future<void> _loadMatch() async {
    if (event.type != 'match') return;
    try {
      final snapshot = await widget.match.getSnapshot(event.id);
      WrittenMatchReport? report;
      if (snapshot?.state == 'completed') {
        try {
          report = await widget.match.getReport(event.id);
        } catch (_) {
          report = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _matchSnapshot = snapshot;
        _report = report;
        _matchLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _matchLoaded = false);
    }
  }

  bool get _canRegisterResult =>
      event.type == 'match' &&
      _matchLoaded &&
      _contextCanCoManage &&
      event.can('match_live') &&
      event.archivedAt == null &&
      ['scheduled', 'completed'].contains(event.state) &&
      !event.startsAt.isAfter(DateTime.now());

  Future<void> _editResult() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RegisterResultDialog(
        event: event,
        match: widget.match,
        snapshot: _matchSnapshot,
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Slutresultatet är sparat. Matchen är avslutad.'),
      ),
    );
    await _refresh();
  }

  Future<void> _editReport(WrittenMatchReport report) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WrittenReportDialog(
        eventId: event.id,
        match: widget.match,
        report: report,
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Matchrapporten är sparad.')));
    await _refresh();
  }

  void _explainArchive() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(context).feature(
            'Eventet måste vara inställt eller genomfört innan det kan arkiveras.',
          ),
        ),
      ),
    );
  }

  List<_EventMenuAction> _menuActions(AppStrings strings) {
    final completed = _matchSnapshot?.state == 'completed';
    final report = _report;
    return [
      if (_contextCanCoManage && event.can('revise'))
        (
          key: 'edit',
          icon: Icons.edit_outlined,
          label: strings.feature('Redigera'),
          onTap: _revise,
          checked: null,
        ),
      if (_canRegisterResult)
        (
          key: 'result',
          icon: Icons.scoreboard_outlined,
          label: completed ? 'Ändra resultat' : 'Registrera resultat',
          onTap: _editResult,
          checked: null,
        ),
      if (completed &&
          report != null &&
          report.canEdit &&
          _contextCanCoManage &&
          event.can('match_live'))
        (
          key: 'report',
          icon: Icons.edit_note,
          label: report.body.isEmpty
              ? 'Skriv matchrapport'
              : 'Redigera matchrapport',
          onTap: () => _editReport(_report ?? report),
          checked: null,
        ),
      // attendance-export:hook (temporary laget.se export)
      if (_contextCanCoManage &&
          AttendanceExportFeature.canOfferEventExport(
            event: event,
            contextValue: widget.contextValue,
            canManageAttendance: squad.can('record_attendance'),
          ))
        (
          key: 'export-laget-se',
          icon: Icons.upload_file_outlined,
          label: 'Exportera närvaro → laget.se',
          onTap: () => AttendanceExportFeature.openEventExport(
            context,
            calendar: widget.calendar,
            eventId: event.id,
            teamId: widget.contextValue.teamId!,
          ),
          checked: null,
        ),
      if ((widget.contextValue.teamId == null || _activeContextIsPrimary) &&
          event.can('manage_sharing'))
        (
          key: 'share',
          icon: Icons.share_outlined,
          label: strings.feature('Dela med andra lag'),
          onTap: _showSharing,
          checked: null,
        ),
      if (_contextCanCoManage &&
          event.can('revise') &&
          event.archivedAt == null &&
          event.state != 'cancelled')
        (
          key: 'callups-required',
          icon: Icons.mark_email_unread_outlined,
          label: 'Kallelse behövs',
          onTap: () {
            if (!_savingCallupRequirement) {
              _setCallupsRequired(!event.callupsRequired);
            }
          },
          checked: event.callupsRequired,
        ),
      if (_contextCanCoManage &&
          event.can('cancel') &&
          event.state == 'cancelled')
        (
          key: 'restore',
          icon: Icons.restore,
          label: strings.feature('Återställ event'),
          onTap: () => _transition('scheduled'),
          checked: null,
        ),
      if (_contextCanCoManage &&
          event.can('cancel') &&
          event.state != 'cancelled')
        (
          key: 'cancel',
          icon: Icons.event_busy,
          label: strings.feature('Ställ in'),
          onTap: () => _transition('cancelled'),
          checked: null,
        ),
      if (_contextCanCoManage && event.can('delete'))
        (
          key: 'delete',
          icon: Icons.delete_outline,
          label: strings.feature('Ta bort event'),
          onTap: _deleteDraft,
          checked: null,
        ),
      if (_contextCanCoManage && (event.can('archive') || event.can('cancel')))
        (
          key: 'archive',
          icon: Icons.archive_outlined,
          label: strings.feature('Arkivera event'),
          onTap: () => event.can('archive') ? _archive() : _explainArchive(),
          checked: null,
        ),
    ];
  }

  /// Hands the current actions to the app bar's ⋮ menu after the frame,
  /// only when something visible changed.
  void _publishMenu(AppStrings strings) {
    final actions = _menuActions(strings);
    final signature = actions
        .map((a) => '${a.key}:${a.label}:${a.checked}')
        .join('|');
    if (signature == _menuSignature) {
      // Same entries; still refresh the callbacks without notifying.
      return;
    }
    _menuSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.menu.value = actions;
    });
  }

  /// The score under the title: large on Info, small on the other tabs,
  /// absent until the match has a result.
  Widget? _resultHeader() {
    final snapshot = _matchSnapshot;
    if (event.type != 'match' ||
        snapshot == null ||
        !{'live', 'completed'}.contains(snapshot.state)) {
      return null;
    }
    final ours =
        event.teams
            .where((team) => team['relation'] == 'primary')
            .map((team) => team['name'])
            .whereType<String>()
            .firstOrNull ??
        'Vårt lag';
    final opponent = event.opponentName?.trim().isNotEmpty == true
        ? event.opponentName!.trim()
        : 'Motståndare';
    final home = event.homeAway != 'away';
    final left = home ? ours : opponent, right = home ? opponent : ours;
    final leftScore = home ? snapshot.scoreUs : snapshot.scoreOpponent;
    final rightScore = home ? snapshot.scoreOpponent : snapshot.scoreUs;
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      key: const Key('event-result-header'),
      animation: _tabController.animation!,
      builder: (context, _) {
        final expanded = (1 - _tabController.animation!.value.clamp(0.0, 1.0))
            .clamp(0.0, 1.0);
        final nameStyle = TextStyle(
          fontSize: 12 + 3 * expanded,
          fontWeight: FontWeight.w600,
        );
        return Semantics(
          label:
              '${snapshot.state == 'completed' ? 'Slutresultat' : 'Pågår'}: $left $leftScore, $right $rightScore',
          child: ExcludeSemantics(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 4 + 6 * expanded, 20, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          left,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$leftScore–$rightScore',
                          style: TextStyle(
                            fontSize: 18 + 14 * expanded,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                      ),
                    ],
                  ),
                  if (expanded > .5)
                    Text(
                      snapshot.state == 'completed' ? 'Slutresultat' : 'Pågår',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

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
    final ownerName = event.teams
        .where((team) => team['relation'] == 'primary')
        .map((team) => team['name'])
        .whereType<String>()
        .firstOrNull;
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
                    children: [
                      Text(
                        strings.feature(
                          'Du kan dela eventet med flera lag samtidigt.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (ownerName != null) ...[
                        Card(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: ListTile(
                            leading: const Icon(Icons.shield_outlined),
                            title: Text(ownerName),
                            subtitle: Text(
                              strings.feature(
                                'Ägande lag – eventet administreras härifrån',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.feature('Lag som eventet kan delas med'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                      ],
                      ...settings.teams.map((team) {
                        final level = levels[team.teamId]!;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  team.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(
                                    strings.feature('Dela med laget'),
                                  ),
                                  subtitle: level == 'none'
                                      ? null
                                      : Text(
                                          strings.feature('Standard: Kan se'),
                                        ),
                                  value: level != 'none',
                                  onChanged: saving
                                      ? null
                                      : (selected) => setDialogState(() {
                                          levels[team.teamId] = selected == true
                                              ? 'view'
                                              : 'none';
                                          if (selected != true) {
                                            audiences[team.teamId]!.clear();
                                          }
                                        }),
                                ),
                                if (level != 'none') ...[
                                  DropdownButtonFormField<String>(
                                    initialValue: level,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: strings.feature('Rättighet'),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'view',
                                        child: Text(strings.feature('Kan se')),
                                      ),
                                      DropdownMenuItem(
                                        value: 'manage_roster',
                                        child: Text(
                                          strings.feature(
                                            'Kan hantera deltagare',
                                          ),
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
                                            levels[team.teamId] =
                                                value ?? 'view';
                                          }),
                                  ),
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
                                                : (selected) => setDialogState(
                                                    () {
                                                      selected
                                                          ? audiences[team
                                                                    .teamId]!
                                                                .add(entry.key)
                                                          : audiences[team
                                                                    .teamId]!
                                                                .remove(
                                                                  entry.key,
                                                                );
                                                    },
                                                  ),
                                          );
                                        }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
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
                        if (mounted) {
                          _showError(
                            'Delningen kunde inte sparas. Ladda om och försök igen.',
                          );
                        }
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
              declineReasonCode: callup.declineReasonCode,
              declineReasonText: callup.declineReasonText,
            );
  }
  for (final attendance in squad.attendance) {
    if (rosterIds.contains(attendance.personId)) continue;
    final existing =
        guests[attendance.personId] ??
        EventRosterPerson(
          personId: attendance.personId,
          name: attendance.name,
          teamId: '',
          teamName: '',
          rolePackage: 'player',
          inDraft: false,
          isGuest: true,
        );
    guests[attendance.personId] = existing.copyWith(
      attendanceStatus: attendance.status,
      attendanceMinutes: attendance.minutes,
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
    final sv = strings.isSwedish;
    final circles = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusCircle(
          count: draft,
          label: strings.feature('Utkast'),
          description: sv
              ? '$draft i urvalet som inte har kallats än'
              : '$draft selected but not called yet',
          color: Colors.blueGrey,
          showLabel: showLabels,
        ),
        _StatusCircle(
          count: called,
          label: strings.feature('Kallade'),
          description: sv
              ? '$called har fått kallelse'
              : '$called have been called',
          color: Colors.indigo,
          showLabel: showLabels,
        ),
        _StatusCircle(
          count: accepted,
          label: strings.domainValue('accepted'),
          description: sv
              ? '$accepted har tackat ja'
              : '$accepted have accepted',
          color: Colors.green,
          showLabel: showLabels,
        ),
        _StatusCircle(
          count: unanswered,
          label: strings.feature('Obesvarade'),
          description: sv
              ? '$unanswered har inte svarat på kallelsen'
              : '$unanswered have not answered',
          color: Colors.amber.shade800,
          showLabel: showLabels,
        ),
        _StatusCircle(
          count: declined,
          label: strings.domainValue('declined'),
          description: sv
              ? '$declined har tackat nej'
              : '$declined have declined',
          color: Colors.red,
          showLabel: showLabels,
        ),
        if (_hasEnded)
          _StatusCircle(
            count: attended,
            label: strings.feature('Deltog'),
            description: sv
                ? '$attended registrerade som närvarande (även sena och delvis)'
                : '$attended registered as attended (incl. late and partial)',
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
    required this.description,
    required this.color,
    required this.showLabel,
  });
  final int count;
  final String label, description;
  final Color color;
  final bool showLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 14),
    // Hover on desktop and web, a tap on phones (long-press is hard to
    // discover there); the label leads, the description explains.
    child: Tooltip(
      message: '$label: $description',
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String? _localizedDeclineReason(AppStrings strings, EventRosterPerson person) {
  if (person.callupState != 'declined') return null;
  final label = switch (person.declineReasonCode) {
    'illness' => strings.feature('Sjukdom'),
    'injury' => strings.feature('Skada'),
    'unavailable' => strings.feature('Inte tillgänglig'),
    'transport' => strings.feature('Transport'),
    'other' => strings.feature('Annat'),
    _ => null,
  };
  if (label == null) return null;
  final detail = person.declineReasonText?.trim();
  return detail == null || detail.isEmpty ? label : '$label – $detail';
}
