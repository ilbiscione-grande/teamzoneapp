part of '../../app/teamzone_app.dart';

/// Enkelt Matchläge: the match-day view for one match event. It is a thin
/// client of the Match Space v2 contract — score, clock, periods, squad and
/// events are all read from the server snapshot and changed only through
/// idempotent commands, so a future Matchmodul builds on the same data.
///
/// Nothing here is shown as saved before the server confirmed it. A failed
/// command keeps its command id, and "Försök igen" resends exactly that
/// command, so a lost response can never create a duplicate goal.
class _MatchModePage extends StatefulWidget {
  const _MatchModePage({
    required this.event,
    required this.squad,
    required this.match,
    required this.live,
    required this.readOnly,
  });

  final EventDetails event;
  final SquadDetails squad;
  final MatchServices match;
  final EventPreparationServices live;

  /// The active team context may not run the match (or Match Space v2 is
  /// switched off): show the same data without controls.
  final bool readOnly;

  @override
  State<_MatchModePage> createState() => _MatchModePageState();
}

class _MatchModePageState extends State<_MatchModePage>
    with WidgetsBindingObserver {
  MatchSnapshot? _snapshot;
  bool _loaded = false, _loadFailed = false, _busy = false;
  bool _squadExpanded = false;
  String? _error;
  Future<void> Function()? _retry;
  late final Timer _ticker;
  StreamSubscription<void>? _liveSubscription;
  Timer? _liveDebounce;

  // KPI goals from Förberedelser. Counted goals get +/− during the match;
  // taps waiting for the server are shown as pending, never as saved.
  EventFollowup? _followup;
  final _pendingTicks = <String, int>{};

  // Before the first command there is no snapshot; the event's own
  // capability ('match_live' is the match-day permission) decides until then.
  bool get _canManage =>
      !widget.readOnly &&
      (_snapshot?.canManage ?? widget.event.can('match_live'));
  String get _state => _snapshot?.state ?? 'planning';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_snapshot?.isRunning ?? false)) setState(() {});
    });
    _liveSubscription = widget.live.watchEventLive(widget.event.id).listen((_) {
      _liveDebounce?.cancel();
      _liveDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_refresh()),
      );
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.cancel();
    _liveDebounce?.cancel();
    unawaited(_liveSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The clock is derived from server timestamps, so coming back after
    // minutes away only needs a fresh snapshot, not a background timer.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    unawaited(_refreshKpis());
    try {
      final value = await widget.match.getSnapshot(widget.event.id);
      if (!mounted) return;
      setState(() {
        _snapshot = value;
        _loaded = true;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _refreshKpis() async {
    try {
      final value = await widget.live.getFollowup(widget.event.id);
      if (mounted) setState(() => _followup = value);
    } catch (_) {
      // Goals are optional here; the match works without them.
    }
  }

  List<EventKpi> get _manualKpis =>
      (_followup?.kpis ?? const <EventKpi>[]).where((k) => k.isManual).toList();

  Future<void> _tick(EventKpi kpi, int delta) async {
    final key = _newUuid();
    final minute = _minuteNow;
    Future<void> send() async {
      setState(() {
        _pendingTicks.update(kpi.id, (v) => v + delta, ifAbsent: () => delta);
        _error = null;
        _retry = null;
      });
      try {
        await widget.live.recordKpiTick(
          commandId: key,
          eventId: widget.event.id,
          targetId: kpi.id,
          delta: delta,
          minute: minute,
        );
        await _refreshKpis();
      } catch (error) {
        if (mounted) {
          setState(() {
            _error = _isPermissionDenied(error)
                ? 'Du saknar behörighet att ändra matchen.'
                : '${kpi.label} kunde inte sparas.';
            _retry = _isPermissionDenied(error) ? null : send;
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            final left = (_pendingTicks[kpi.id] ?? 0) - delta;
            if (left == 0) {
              _pendingTicks.remove(kpi.id);
            } else {
              _pendingTicks[kpi.id] = left;
            }
          });
        }
      }
    }

    await send();
  }

  Future<void> _enterKpiValue(EventKpi kpi) async {
    final result = await showDialog<(bool, double?)>(
      context: context,
      builder: (_) => _KpiValueDialog(kpi: kpi),
    );
    if (result == null || !result.$1 || !mounted) return;
    try {
      await widget.live.recordKpiValue(kpi.id, result.$2, kpi.revision);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '${kpi.label} kunde inte sparas.');
      }
    }
    await _refreshKpis();
  }

  bool _isRejection(Object error) {
    if (error is PostgrestException) return true;
    return error is MeasuredCommandException &&
        error.code != 'gateway_unavailable';
  }

  bool _isPermissionDenied(Object error) {
    final value = error.toString().toLowerCase();
    return value.contains('42501') ||
        value.contains('not_found') ||
        value.contains('permission denied');
  }

  /// Runs one or more commands whose ids were fixed by the caller, so a
  /// retry resends the identical commands.
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
      _retry = null;
    });
    try {
      await action();
      await _refresh();
      if (mounted) setState(() => _busy = false);
      return true;
    } catch (error) {
      if (!mounted) return false;
      final denied = _isPermissionDenied(error);
      final rejected = !denied && _isRejection(error);
      setState(() {
        _busy = false;
        _error = denied
            ? 'Du saknar behörighet att ändra matchen.'
            : rejected
            ? 'Ändringen godtogs inte. Matchen kan ha ändrats av en annan ledare.'
            : 'Ändringen kunde inte bekräftas. Kontrollera anslutningen.';
        _retry = denied ? null : () => _run(action);
      });
      // Show the true server state rather than an assumed one.
      unawaited(_refresh());
      return false;
    }
  }

  // --- Derived data ---------------------------------------------------------

  String get _ourName =>
      widget.event.teams
          .where((team) => team['relation'] == 'primary')
          .map((team) => team['name'])
          .whereType<String>()
          .firstOrNull ??
      'Vårt lag';

  String get _opponentName {
    final name = widget.event.opponentName?.trim();
    return name == null || name.isEmpty ? 'Motståndare' : name;
  }

  /// Home team on the left, as on a scoreboard.
  bool get _weAreLeft => widget.event.homeAway != 'away';

  List<EventRosterPerson> get _allPeople => [
    ...widget.squad.roster,
    ..._guestRosterFor(widget.squad),
  ];

  bool _isLeader(String personId) {
    final role = _allPeople
        .where((person) => person.personId == personId)
        .map((person) => person.rolePackage)
        .firstOrNull;
    return role == 'leader' || role == 'club_functionary';
  }

  /// What Deltagare currently says is coming: accepted callups plus
  /// registered attendance. The server freezes exactly this set.
  List<EventRosterPerson> get _expectedSquad => _allPeople
      .where(
        (person) =>
            person.callupState == 'accepted' ||
            person.attendanceStatus == 'present' ||
            person.attendanceStatus == 'late' ||
            person.attendanceStatus == 'partial',
      )
      .toList();

  bool get _squadFrozen => (_snapshot?.rosterRevision ?? 0) > 0;

  List<(String, String)> get _squad => _squadFrozen
      ? [for (final member in _snapshot!.roster) (member.personId, member.name)]
      : [for (final person in _expectedSquad) (person.personId, person.name)];

  bool get _squadOutdated {
    if (!_squadFrozen) return false;
    final frozen = _snapshot!.roster.map((m) => m.personId).toSet();
    final expected = _expectedSquad.map((p) => p.personId).toSet();
    return frozen.length != expected.length || !frozen.containsAll(expected);
  }

  List<MatchRosterMember> get _scorerCandidates =>
      (_snapshot?.roster ?? const <MatchRosterMember>[])
          .where((member) => !_isLeader(member.personId))
          .toList();

  String _personName(String? id) {
    if (id == null) return 'Okänd målskytt';
    return _snapshot?.people[id] ??
        _snapshot?.roster
            .where((member) => member.personId == id)
            .map((member) => member.name)
            .firstOrNull ??
        'Okänd spelare';
  }

  String _periodName(int period, int count) => count == 2
      ? '$period:a halvlek'
      : count == 1
      ? 'Matchen'
      : 'Period $period';

  String get _clockCaption {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.state == 'planning') return 'Ej startad';
    if (snapshot.state == 'completed') return 'Slutresultat';
    final count = snapshot.periodMinutes.length;
    if (snapshot.currentPeriodEnded) {
      return count == 2 && snapshot.currentPeriod == 1
          ? 'Halvtid'
          : 'Paus efter period ${snapshot.currentPeriod}';
    }
    final name = _periodName(snapshot.currentPeriod, count);
    return snapshot.isPaused ? '$name · pausad' : name;
  }

  String get _clockText {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.state == 'planning') return '00:00';
    final elapsed = snapshot.elapsedNow();
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  int get _minuteNow => max(1, _snapshot?.currentMinute ?? 1);

  // --- Commands --------------------------------------------------------------

  Future<void> _start() {
    final freezeKey = _newUuid(), startKey = _newUuid();
    final needsFreeze = !_squadFrozen;
    return _run(() async {
      if (needsFreeze) {
        await widget.match.freezeRoster(freezeKey, widget.event.id, 'initial');
      }
      await widget.match.transition(startKey, widget.event.id, 'start');
    });
  }

  Future<void> _primaryAction() async {
    final snapshot = _snapshot;
    final key = _newUuid();
    if (snapshot == null || snapshot.state == 'planning') return _start();
    if (snapshot.state != 'live') return;
    if (!snapshot.isPaused) {
      await _run(() => widget.match.transition(key, widget.event.id, 'pause'));
    } else if (snapshot.currentPeriodEnded) {
      await _run(
        () => widget.match.transitionPeriod(key, widget.event.id, 'resume'),
      );
    } else {
      await _run(() => widget.match.transition(key, widget.event.id, 'resume'));
    }
  }

  Future<void> _addGoal(String side) async {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.state != 'live') return;
    if (side == 'opponent') {
      final key = _newUuid();
      final minute = _minuteNow;
      final ok = await _run(
        () => widget.match.recordGoal(key, widget.event.id, side, minute),
      );
      if (ok && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Mål $_opponentName $minute′'),
              action: SnackBarAction(
                label: 'Ångra',
                onPressed: () => _undoCommand(key),
              ),
            ),
          );
      }
      return;
    }
    final choice = await showModalBottomSheet<_GoalChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _GoalSheet(players: _scorerCandidates, initialMinute: _minuteNow),
    );
    if (choice == null || !mounted) return;
    final key = _newUuid();
    await _run(
      () => widget.match.recordGoal(
        key,
        widget.event.id,
        'us',
        choice.minute,
        scorerId: choice.scorerId,
        assistId: choice.assistId,
      ),
    );
  }

  Future<void> _undoCommand(String commandKey) async {
    final fact = _snapshot?.activeFacts
        .where((fact) => fact['source_command_id'] == commandKey)
        .firstOrNull;
    if (fact == null) return;
    final key = _newUuid();
    await _run(() => widget.match.voidEvent(key, fact['id'] as String));
  }

  /// "−" removes the latest goal for that side, so the score and the
  /// registered goals can never disagree. Only a score without goal facts
  /// (e.g. entered as a direct result) falls back to a logged adjustment.
  Future<void> _removeGoal(String side) async {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.state != 'live') return;
    final goals =
        snapshot.activeFacts
            .where(
              (fact) => fact['fact_type'] == 'goal' && fact['side'] == side,
            )
            .toList()
          ..sort(
            (a, b) => ((a['minute'] as num? ?? 0).compareTo(
              b['minute'] as num? ?? 0,
            )),
          );
    final score = side == 'us' ? snapshot.scoreUs : snapshot.scoreOpponent;
    if (goals.isEmpty && score == 0) return;
    final latest = goals.lastOrNull;
    final description = latest == null
        ? 'Resultatet för ${side == 'us' ? _ourName : _opponentName} minskas med 1.'
        : 'Målet ${latest['minute']}′ ${side == 'us' ? _personName(latest['club_person_id'] as String?) : _opponentName} tas bort.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ta bort mål?'),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final key = _newUuid();
    await _run(
      () => latest == null
          ? widget.match.adjustScore(key, widget.event.id, side, -1, _minuteNow)
          : widget.match.voidEvent(key, latest['id'] as String),
    );
  }

  Future<void> _addEvent() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Lägg till händelse',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (final (value, icon, label) in [
              ('us', Icons.sports_soccer, 'Mål – $_ourName'),
              ('opponent', Icons.sports_soccer, 'Mål – $_opponentName'),
              ('note', Icons.notes, 'Anteckning'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'note') {
      final note = await showDialog<(int, String)>(
        context: context,
        builder: (_) => _MatchNoteDialog(initialMinute: _minuteNow),
      );
      if (note == null || !mounted) return;
      final key = _newUuid();
      await _run(
        () => widget.match.recordNote(key, widget.event.id, note.$1, note.$2),
      );
    } else {
      await _addGoal(choice);
    }
  }

  Future<void> _editFact(Map<String, dynamic> fact) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final result = await showModalBottomSheet<_FactEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FactEditSheet(
        fact: fact,
        players: _scorerCandidates,
        teamName: fact['side'] == 'us' ? _ourName : _opponentName,
        personName: _personName,
        canDelete: snapshot.state == 'live',
      ),
    );
    if (result == null || !mounted) return;
    final key = _newUuid();
    final id = fact['id'] as String;
    await _run(
      () => result.delete
          ? widget.match.voidEvent(key, id)
          : widget.match.correctEvent(
              key,
              id,
              minute: result.minute,
              scorerId: result.scorerId,
              assistId: result.assistId,
              text: result.text,
            ),
    );
  }

  Future<void> _endPeriod() {
    final key = _newUuid();
    return _run(
      () => widget.match.transitionPeriod(key, widget.event.id, 'end'),
    );
  }

  Future<void> _finish() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Slutsignal?'),
        content: Text(
          'Matchen avslutas med $_ourName ${snapshot.scoreUs}–${snapshot.scoreOpponent} $_opponentName. '
          'Målskyttar och minuter kan fortfarande rättas efteråt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Avsluta match'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final key = _newUuid();
    final total = snapshot.periodMinutes.fold<int>(0, (sum, v) => sum + v);
    final minute = max(total, _minuteNow - 1);
    await _run(() => widget.match.complete(key, widget.event.id, minute));
  }

  Future<void> _correctClock() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final seconds = await showDialog<int>(
      context: context,
      builder: (_) => _ClockCorrectionDialog(
        initialSeconds: snapshot.elapsedNow().inSeconds,
      ),
    );
    if (seconds == null || !mounted) return;
    final key = _newUuid();
    await _run(() => widget.match.adjustClock(key, widget.event.id, seconds));
  }

  Future<void> _changeFormat() async {
    final snapshot = _snapshot;
    final periods = await showDialog<List<int>>(
      context: context,
      builder: (_) => _MatchFormatDialog(
        initial: snapshot?.periodMinutes ?? const [45, 45],
        minimumPeriods: snapshot?.state == 'live' ? snapshot!.currentPeriod : 1,
      ),
    );
    if (periods == null || !mounted) return;
    final key = _newUuid();
    await _run(
      () => widget.match.configurePeriods(key, widget.event.id, periods),
    );
  }

  Future<void> _updateSquad() {
    final key = _newUuid();
    return _run(
      () => widget.match.freezeRoster(
        key,
        widget.event.id,
        _squadFrozen ? 'late_callup' : 'initial',
      ),
    );
  }

  // --- UI ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final start = widget.event.startsAt.toLocal();
    final subtitle = [
      localizations.formatMediumDate(start),
      localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start)),
      if (widget.event.locationName != null) widget.event.locationName!,
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            const Text('Matchläge'),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_canManage && _state != 'completed')
            PopupMenuButton<VoidCallback>(
              tooltip: 'Matchinställningar',
              icon: const Icon(Icons.settings_outlined),
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _changeFormat,
                  child: const Text('Matchformat'),
                ),
                if (_state == 'live')
                  PopupMenuItem(
                    value: _correctClock,
                    child: const Text('Korrigera tid'),
                  ),
                PopupMenuItem(
                  value: _updateSquad,
                  child: const Text('Uppdatera trupp från Deltagare'),
                ),
                PopupMenuItem(
                  value: _refresh,
                  child: const Text('Synkronisera'),
                ),
              ],
            )
          else
            IconButton(
              tooltip: 'Synkronisera',
              onPressed: _refresh,
              icon: const Icon(Icons.sync),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed && _snapshot == null
          ? Center(
              child: _StateCard(
                icon: Icons.sync_problem,
                title: 'Matchen kunde inte laddas',
                message: AppStrings.of(context).safeError,
                action: FilledButton(
                  onPressed: _refresh,
                  child: Text(AppStrings.of(context).retry),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      _scoreboard(),
                      _clockBox(),
                      if (_canManage) _primaryButton(),
                      if (_canManage && _state == 'live') _scoreButtons(),
                      if (_error != null) _errorBanner(),
                      if (!_canManage && _snapshot == null)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Matchen har inte startats.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (_manualKpis.isNotEmpty) _kpiSection(),
                      _eventsSection(),
                      _squadSection(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _crest(String name) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .1),
        shape: BoxShape.circle,
      ),
      child: Text(
        _initialsOf(name),
        style: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _scoreboard() {
    final snapshot = _snapshot;
    final us = snapshot?.scoreUs ?? 0, them = snapshot?.scoreOpponent ?? 0;
    final left = _weAreLeft ? (_ourName, us) : (_opponentName, them);
    final right = _weAreLeft ? (_opponentName, them) : (_ourName, us);
    Widget team((String, int) side, {required bool alignEnd}) => Expanded(
      child: Column(
        children: [
          Text(
            side.$1,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
            children: [
              _crest(side.$1),
              const SizedBox(width: 14),
              Text(
                '${side.$2}',
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: 'Ställning: ${left.$1} ${left.$2}, ${right.$1} ${right.$2}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              team(left, alignEnd: false),
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text('–', style: TextStyle(fontSize: 32)),
              ),
              team(right, alignEnd: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clockBox() {
    final colors = Theme.of(context).colorScheme;
    final snapshot = _snapshot;
    final menu = _canManage && snapshot?.state == 'live';
    final caption = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_clockCaption, style: const TextStyle(fontSize: 14)),
        if (menu) const Icon(Icons.expand_more, size: 18),
      ],
    );
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        constraints: const BoxConstraints(minWidth: 184),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (menu)
              PopupMenuButton<VoidCallback>(
                tooltip: 'Period och tid',
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  if (!snapshot!.isPaused &&
                      snapshot.currentPeriod < snapshot.periodMinutes.length)
                    PopupMenuItem(
                      value: _endPeriod,
                      child: Text(
                        'Avsluta ${_periodName(snapshot.currentPeriod, snapshot.periodMinutes.length).toLowerCase()}',
                      ),
                    ),
                  PopupMenuItem(
                    value: _finish,
                    child: const Text('Slutsignal'),
                  ),
                  PopupMenuItem(
                    value: _correctClock,
                    child: const Text('Korrigera tid'),
                  ),
                  PopupMenuItem(
                    value: _changeFormat,
                    child: const Text('Matchformat'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: caption,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: caption,
              ),
            Semantics(
              label: 'Matchtid $_clockText',
              liveRegion: false,
              child: ExcludeSemantics(
                child: Text(
                  _clockText,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            if (snapshot != null && snapshot.state != 'planning')
              Text(
                snapshot.periodMinutes.length == 1
                    ? '1 × ${snapshot.periodMinutes.first} min'
                    : snapshot.periodMinutes.toSet().length == 1
                    ? '${snapshot.periodMinutes.length} × ${snapshot.periodMinutes.first} min'
                    : snapshot.periodMinutes.join(' + '),
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton() {
    final snapshot = _snapshot;
    final (IconData, String)? spec = switch (snapshot) {
      null => (Icons.play_arrow, 'Starta match'),
      MatchSnapshot(state: 'planning') => (Icons.play_arrow, 'Starta match'),
      MatchSnapshot(state: 'live', isPaused: false) => (Icons.pause, 'Pausa'),
      MatchSnapshot(
        state: 'live',
        currentPeriodEnded: true,
        :final currentPeriod,
        :final periodMinutes,
      ) =>
        (
          Icons.play_arrow,
          'Starta ${_periodName(currentPeriod + 1, periodMinutes.length).toLowerCase()}',
        ),
      MatchSnapshot(state: 'live') => (Icons.play_arrow, 'Fortsätt'),
      _ => null,
    };
    if (spec == null) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FilledButton.icon(
          key: const ValueKey('match-primary-action'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(160, 46),
            shape: const StadiumBorder(),
          ),
          onPressed: _busy ? null : _primaryAction,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(spec.$1),
          label: Text(spec.$2),
        ),
      ),
    );
  }

  Widget _scoreButtons() {
    Widget pair(String side, String name) => Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _scoreButton(
                Icons.remove,
                'Ta bort mål för $name',
                () => _removeGoal(side),
              ),
              const SizedBox(width: 10),
              _scoreButton(Icons.add, 'Mål för $name', () => _addGoal(side)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
    final left = _weAreLeft ? ('us', _ourName) : ('opponent', _opponentName);
    final right = _weAreLeft ? ('opponent', _opponentName) : ('us', _ourName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: IntrinsicHeight(
        child: Row(
          children: [
            pair(left.$1, left.$2),
            const VerticalDivider(width: 1),
            pair(right.$1, right.$2),
          ],
        ),
      ),
    );
  }

  Widget _scoreButton(IconData icon, String tooltip, VoidCallback onPressed) {
    final colors = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size(60, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: colors.primary.withValues(alpha: .08),
        foregroundColor: colors.primary,
      ),
      onPressed: _busy ? null : onPressed,
      icon: Icon(icon, size: 28),
    );
  }

  Widget _errorBanner() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 20,
                  color: colors.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
                if (_retry != null)
                  TextButton(
                    onPressed: _busy ? null : _retry,
                    child: const Text('Försök igen'),
                  ),
                IconButton(
                  tooltip: 'Stäng',
                  onPressed: () => setState(() {
                    _error = null;
                    _retry = null;
                  }),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? trailing}) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
              ),
            ),
          ),
          if (trailing != null)
            Text(trailing, style: const TextStyle(fontSize: 13)),
        ],
      ),
    ),
  );

  Widget _kpiSection() {
    final colors = Theme.of(context).colorScheme;
    final live = _canManage && _state == 'live';
    final canEnter =
        !widget.readOnly &&
        _state == 'completed' &&
        (_followup?.canRecordValues ?? false);
    return Column(
      key: const ValueKey('match-kpis'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        _sectionHeader('Nyckeltal'),
        for (final kpi in _manualKpis)
          () {
            final pending = _pendingTicks[kpi.id] ?? 0;
            final counter = kpi.valueType == 'count';
            final value = counter ? (kpi.actual ?? 0) + pending : kpi.actual;
            return ListTile(
              key: ValueKey('match-kpi-${kpi.id}'),
              dense: true,
              title: Text(kpi.label),
              subtitle: Text(
                'Mål: ${_kpiGoalText(kpi)}'
                '${!counter && kpi.actual == null && _state != 'completed' ? ' · fylls i efteråt' : ''}',
              ),
              onTap: canEnter ? () => _enterKpiValue(kpi) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (live && counter)
                    IconButton(
                      tooltip: 'Minska ${kpi.label}',
                      onPressed: (value ?? 0) > 0 ? () => _tick(kpi, -1) : null,
                      icon: const Icon(Icons.remove),
                    ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      counter
                          ? (value ?? 0).toInt().toString()
                          : _kpiValueText(kpi.valueType, value),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: pending != 0 ? colors.onSurfaceVariant : null,
                      ),
                    ),
                  ),
                  if (live && counter)
                    IconButton.filledTonal(
                      tooltip: 'Öka ${kpi.label}',
                      onPressed: () => _tick(kpi, 1),
                      icon: const Icon(Icons.add),
                    ),
                  if (canEnter) const Icon(Icons.edit_outlined, size: 18),
                ],
              ),
            );
          }(),
      ],
    );
  }

  Widget _eventsSection() {
    final snapshot = _snapshot;
    final facts = (snapshot?.activeFacts ?? const <Map<String, dynamic>>[])
        .where(
          (fact) =>
              fact['fact_type'] != 'kpi' && fact['fact_type'] != 'half_time',
        )
        .toList()
        .reversed
        .toList();
    final scoring = facts
        .where(
          (fact) => fact['fact_type'] == 'goal' || fact['fact_type'] == 'note',
        )
        .length;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        _sectionHeader(
          'Matchhändelser',
          trailing: scoring == 0 ? null : '$scoring',
        ),
        if (facts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Inga händelser ännu.',
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ),
        for (final fact in facts) _factRow(fact),
        if (_canManage && _state == 'live')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Material(
              color: colors.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _busy ? null : _addEvent,
                child: SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.add, size: 18, color: colors.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Lägg till händelse',
                        style: TextStyle(color: colors.primary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _factRow(Map<String, dynamic> fact) {
    final colors = Theme.of(context).colorScheme;
    final type = fact['fact_type'] as String? ?? '';
    final side = fact['side'] as String?;
    final minute = (fact['minute'] as num? ?? 0).toInt();
    final detail = (fact['detail'] as Map?) ?? const {};
    final count = _snapshot?.periodMinutes.length ?? 2;
    if (type == 'period_end' || type == 'full_time') {
      final period = (detail['period'] as num?)?.toInt() ?? 0;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                type == 'full_time'
                    ? 'Slutsignal'
                    : count == 2 && period == 1
                    ? 'Halvtid'
                    : 'Slut period $period',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
      );
    }
    final (IconData icon, String title, String? subtitle) = switch (type) {
      'goal' when side == 'us' => (
        Icons.sports_soccer,
        _personName(fact['club_person_id'] as String?),
        fact['secondary_club_person_id'] == null
            ? null
            : 'Assist: ${_personName(fact['secondary_club_person_id'] as String?)}',
      ),
      'goal' => (Icons.sports_soccer, _opponentName, null),
      'note' => (Icons.notes, detail['text'] as String? ?? '', null),
      'score_adjustment' => (
        Icons.exposure,
        'Resultatjustering ${side == 'us' ? _ourName : _opponentName}',
        '${(detail['delta'] as num? ?? 0) > 0 ? '+' : ''}${detail['delta']}',
      ),
      _ => (Icons.bolt, type.replaceAll('_', ' '), null),
    };
    final editable =
        _canManage &&
        (type == 'goal' || type == 'note') &&
        (_state == 'live' || _state == 'completed');
    return Semantics(
      label:
          '$minute minuter, ${type == 'goal'
              ? 'mål'
              : type == 'note'
              ? 'anteckning'
              : ''} $title${subtitle == null ? '' : ', $subtitle'}',
      excludeSemantics: true,
      button: editable,
      child: InkWell(
        onTap: editable ? () => _editFact(fact) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: editable ? 0 : 16),
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 10),
                SizedBox(
                  width: 34,
                  child: Text(
                    '$minute′',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (editable)
                  IconButton(
                    tooltip: 'Redigera händelse',
                    onPressed: _busy ? null : () => _editFact(fact),
                    icon: const Icon(Icons.more_vert, size: 20),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _squadSection() {
    final colors = Theme.of(context).colorScheme;
    final squad = _squad;
    final leaders = squad.where((entry) => _isLeader(entry.$1)).length;
    final players = squad.length - leaders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Semantics(
          button: true,
          expanded: _squadExpanded,
          child: InkWell(
            onTap: () => setState(() => _squadExpanded = !_squadExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Text(
                    'TRUPP (${squad.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$players spelare · $leaders ledare',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Icon(
                    _squadExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!_squadFrozen && squad.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'Från Deltagare. Truppen låses när matchen startar.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        if (squad.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'Ingen har tackat ja eller registrerats som närvarande. Mål kan ändå registreras med okänd målskytt.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        if (_squadOutdated && _canManage && _state != 'completed')
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _updateSquad,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Deltagare har ändrats – uppdatera trupp'),
              ),
            ),
          ),
        if (_squadExpanded)
          for (final (id, name) in squad)
            SizedBox(
              height: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: colors.primary.withValues(alpha: .14),
                      child: Text(
                        _initialsOf(name),
                        style: TextStyle(fontSize: 11, color: colors.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isLeader(id))
                      Text(
                        'Ledare',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _GoalChoice {
  const _GoalChoice({required this.minute, this.scorerId, this.assistId});
  final int minute;
  final String? scorerId, assistId;
}

/// "Vem gjorde målet?" then an optional assist: tapping a name advances,
/// so a goal takes three taps (+, scorer, assist or "Ingen assist").
class _GoalSheet extends StatefulWidget {
  const _GoalSheet({required this.players, required this.initialMinute});
  final List<MatchRosterMember> players;
  final int initialMinute;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late int _minute = widget.initialMinute;
  String _query = '';
  bool _choosingAssist = false;
  String? _scorerId;

  Future<void> _editMinute() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _MinuteDialog(initial: _minute),
    );
    if (value != null) setState(() => _minute = value);
  }

  void _pick(String? id) {
    if (!_choosingAssist) {
      if (id == null) {
        Navigator.pop(context, _GoalChoice(minute: _minute));
        return;
      }
      setState(() {
        _scorerId = id;
        _choosingAssist = true;
        _query = '';
      });
      return;
    }
    Navigator.pop(
      context,
      _GoalChoice(minute: _minute, scorerId: _scorerId, assistId: id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = _query.toLowerCase();
    final people = widget.players
        .where((player) => player.personId != _scorerId)
        .where(
          (player) =>
              query.isEmpty || player.name.toLowerCase().contains(query),
        )
        .toList();
    final scorerName = widget.players
        .where((player) => player.personId == _scorerId)
        .map((player) => player.name)
        .firstOrNull;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _choosingAssist ? 'Assist?' : 'Vem gjorde målet?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Ändra minut',
                      child: ActionChip(
                        avatar: const Icon(Icons.timer_outlined, size: 16),
                        label: Text('$_minute′'),
                        onPressed: _editMinute,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Stäng',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (scorerName != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Målskytt: $scorerName',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              if (widget.players.length > 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: TextField(
                    key: ValueKey(_choosingAssist),
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Sök spelare…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final player in people)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: colors.primary.withValues(
                            alpha: .14,
                          ),
                          child: Text(
                            _initialsOf(player.name),
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        title: Text(
                          player.name,
                          style: const TextStyle(fontSize: 15),
                        ),
                        onTap: () => _pick(player.personId),
                      ),
                    if (people.isEmpty && widget.players.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Matchtruppen saknar spelare.'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () => _pick(null),
                  child: Text(
                    _choosingAssist ? 'Ingen assist' : 'Okänd målskytt',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactEdit {
  const _FactEdit({
    this.minute = 0,
    this.scorerId,
    this.assistId,
    this.text,
    this.delete = false,
  });
  final int minute;
  final String? scorerId, assistId, text;
  final bool delete;
}

class _FactEditSheet extends StatefulWidget {
  const _FactEditSheet({
    required this.fact,
    required this.players,
    required this.teamName,
    required this.personName,
    required this.canDelete,
  });
  final Map<String, dynamic> fact;
  final List<MatchRosterMember> players;
  final String teamName;
  final String Function(String?) personName;
  final bool canDelete;

  @override
  State<_FactEditSheet> createState() => _FactEditSheetState();
}

class _FactEditSheetState extends State<_FactEditSheet> {
  late final _minute = TextEditingController(
    text: '${(widget.fact['minute'] as num? ?? 0).toInt()}',
  );
  late final _text = TextEditingController(
    text: ((widget.fact['detail'] as Map?)?['text'] as String?) ?? '',
  );
  late String? _scorer = widget.fact['club_person_id'] as String?;
  late String? _assist = widget.fact['secondary_club_person_id'] as String?;

  bool get _isNote => widget.fact['fact_type'] == 'note';
  bool get _isOurGoal =>
      widget.fact['fact_type'] == 'goal' && widget.fact['side'] == 'us';

  @override
  void dispose() {
    _minute.dispose();
    _text.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String?>> _options(String emptyLabel, String? current) {
    final ids = {
      for (final player in widget.players) player.personId: player.name,
    };
    // A scorer who left a later squad revision still shows by name.
    if (current != null) {
      ids.putIfAbsent(current, () => widget.personName(current));
    }
    return [
      DropdownMenuItem(value: null, child: Text(emptyLabel)),
      for (final entry in ids.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final minute = int.tryParse(_minute.text.trim());
    final valid =
        minute != null &&
        minute >= 0 &&
        minute <= 300 &&
        (!_isNote || _text.text.trim().isNotEmpty) &&
        (_scorer == null || _scorer != _assist);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isNote
                    ? 'Redigera anteckning'
                    : 'Redigera mål – ${widget.teamName}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _minute,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Minut',
                  suffixText: '′',
                  isDense: true,
                ),
              ),
              if (_isOurGoal) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _scorer,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Målskytt',
                    isDense: true,
                  ),
                  items: _options('Okänd målskytt', _scorer),
                  onChanged: (value) => setState(() => _scorer = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _assist,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Assist',
                    isDense: true,
                  ),
                  items: _options('Ingen assist', _assist),
                  onChanged: (value) => setState(() => _assist = value),
                ),
              ],
              if (_isNote) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Anteckning',
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Wraps onto two lines instead of overflowing at large text.
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                children: [
                  if (widget.canDelete)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, const _FactEdit(delete: true)),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Ta bort'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Avbryt'),
                  ),
                  FilledButton(
                    onPressed: valid
                        ? () => Navigator.pop(
                            context,
                            _FactEdit(
                              minute: minute,
                              scorerId: _isOurGoal ? _scorer : null,
                              assistId: _isOurGoal ? _assist : null,
                              text: _isNote ? _text.text.trim() : null,
                            ),
                          )
                        : null,
                    child: const Text('Spara'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MinuteDialog extends StatefulWidget {
  const _MinuteDialog({required this.initial});
  final int initial;

  @override
  State<_MinuteDialog> createState() => _MinuteDialogState();
}

class _MinuteDialogState extends State<_MinuteDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(_controller.text.trim());
    final valid = value != null && value >= 0 && value <= 300;
    return AlertDialog(
      title: const Text('Matchminut'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(suffixText: '′'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, value) : null,
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _MatchNoteDialog extends StatefulWidget {
  const _MatchNoteDialog({required this.initialMinute});
  final int initialMinute;

  @override
  State<_MatchNoteDialog> createState() => _MatchNoteDialogState();
}

class _MatchNoteDialogState extends State<_MatchNoteDialog> {
  late final _minute = TextEditingController(text: '${widget.initialMinute}');
  final _text = TextEditingController();

  @override
  void dispose() {
    _minute.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minute = int.tryParse(_minute.text.trim());
    final valid =
        minute != null &&
        minute >= 0 &&
        minute <= 300 &&
        _text.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Anteckning'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _minute,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Minut',
              suffixText: '′',
            ),
          ),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Text'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, (minute, _text.text.trim()))
              : null,
          child: const Text('Spara'),
        ),
      ],
    );
  }
}

class _ClockCorrectionDialog extends StatefulWidget {
  const _ClockCorrectionDialog({required this.initialSeconds});
  final int initialSeconds;

  @override
  State<_ClockCorrectionDialog> createState() => _ClockCorrectionDialogState();
}

class _ClockCorrectionDialogState extends State<_ClockCorrectionDialog> {
  late final _minutes = TextEditingController(
    text: '${widget.initialSeconds ~/ 60}',
  );
  late final _seconds = TextEditingController(
    text: '${widget.initialSeconds % 60}',
  );

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = int.tryParse(_minutes.text.trim());
    final seconds = int.tryParse(_seconds.text.trim());
    final valid =
        minutes != null &&
        seconds != null &&
        seconds < 60 &&
        minutes * 60 + seconds <= 43200;
    Widget field(TextEditingController controller, String label) => Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      ),
    );
    return AlertDialog(
      title: const Text('Korrigera tid'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ange rätt matchtid just nu. Redan registrerade händelser behåller sina minuter.',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              field(_minutes, 'Minuter'),
              const SizedBox(width: 12),
              field(_seconds, 'Sekunder'),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, minutes * 60 + seconds)
              : null,
          child: const Text('Spara'),
        ),
      ],
    );
  }
}

class _MatchFormatDialog extends StatefulWidget {
  const _MatchFormatDialog({
    required this.initial,
    required this.minimumPeriods,
  });
  final List<int> initial;
  final int minimumPeriods;

  @override
  State<_MatchFormatDialog> createState() => _MatchFormatDialogState();
}

class _MatchFormatDialogState extends State<_MatchFormatDialog> {
  static const _presets = [
    (2, 45),
    (2, 40),
    (2, 35),
    (2, 30),
    (2, 25),
    (2, 20),
    (3, 30),
    (3, 20),
    (3, 15),
    (4, 15),
    (1, 25),
  ];
  late int _periods = widget.initial.length;
  late final _minutes = TextEditingController(
    text: '${widget.initial.isEmpty ? 45 : widget.initial.first}',
  );

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = int.tryParse(_minutes.text.trim());
    final valid =
        minutes != null &&
        minutes >= 1 &&
        minutes <= 120 &&
        _periods >= widget.minimumPeriods;
    return AlertDialog(
      title: const Text('Matchformat'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (count, length) in _presets)
                  if (count >= widget.minimumPeriods)
                    ChoiceChip(
                      label: Text('$count × $length'),
                      selected: _periods == count && minutes == length,
                      onSelected: (_) => setState(() {
                        _periods = count;
                        _minutes.text = '$length';
                      }),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _periods,
                    decoration: const InputDecoration(labelText: 'Perioder'),
                    items: [
                      for (var n = widget.minimumPeriods; n <= 8; n++)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (value) =>
                        setState(() => _periods = value ?? _periods),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Minuter per period',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: valid
              ? () =>
                    Navigator.pop(context, List<int>.filled(_periods, minutes))
              : null,
          child: const Text('Spara'),
        ),
      ],
    );
  }
}
