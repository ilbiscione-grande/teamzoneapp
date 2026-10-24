part of '../../app/teamzone_app.dart';

/// Who plays: our team's name, the opponent and home or away.
typedef _MatchSides = ({String team, String? opponent, String? homeAway});

/// Live in the Match module, the upgraded Matchläge: the same match as the
/// event's Matchläge (Match Space v2's workspace, clock, frozen squad and
/// facts), with the old app's buttons for every kind of event, who is on
/// the pitch from the line-up and the substitutions, and the substitution
/// plan to tick off.
class _MatchLiveView extends StatefulWidget {
  const _MatchLiveView({
    super.key,
    required this.eventId,
    required this.calendar,
    required this.match,
    required this.sides,
    this.onPhase,
    this.onCompact,
  });
  final String eventId;
  final CalendarServices calendar;
  final MatchServices match;
  final _MatchSides sides;

  /// From Planläge's header: change to another phase.
  final ValueChanged<_MatchPhase>? onPhase;

  /// Whether Live shows Planläge, which draws its own header, so the page
  /// can leave out its app bar.
  final ValueChanged<bool>? onCompact;

  @override
  State<_MatchLiveView> createState() => _MatchLiveViewState();
}

class _MatchLiveViewState extends State<_MatchLiveView>
    with _LiveCounterState, WidgetsBindingObserver {
  MatchSnapshot? _snapshot;
  MatchLineup? _lineup;
  final _roles = <String, String>{};
  bool _loaded = false, _busy = false;
  String? _error;
  Future<void> Function()? _retry;
  late final Timer _ticker;
  StreamSubscription<void>? _live;
  Timer? _liveDebounce;

  @override
  String get _eventId => widget.eventId;
  @override
  List<Map<String, dynamic>> get _facts => _snapshot?.facts ?? const [];
  String get _state => _snapshot?.state ?? 'planning';
  bool get _canManage => _snapshot?.canManage ?? (_lineup?.canEdit ?? false);
  String get _opponentName {
    final name = widget.sides.opponent?.trim();
    return name == null || name.isEmpty ? 'Motståndare' : name;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_snapshot?.isRunning ?? false)) setState(() {});
    });
    _live = widget.calendar.preparation.watchEventLive(_eventId).listen((_) {
      _liveDebounce?.cancel();
      _liveDebounce = Timer(const Duration(milliseconds: 300), () {
        unawaited(_refresh());
        unawaited(_loadCounters());
      });
    });
    unawaited(_loadLineup());
    unawaited(_loadCounters());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.cancel();
    _liveDebounce?.cancel();
    unawaited(_live?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _loadLineup() async {
    try {
      final lineup = await widget.calendar.matchPlans.getLineup(_eventId);
      final squad = lineup?.canEdit == true
          ? await widget.calendar
                .getEventSquad(_eventId)
                .then<SquadDetails?>((value) => value, onError: (_) => null)
          : null;
      if (!mounted) return;
      setState(() {
        _lineup = lineup;
        for (final person in [
          ...?squad?.roster,
          if (squad != null) ..._guestRosterFor(squad),
        ]) {
          _roles[person.personId] = person.rolePackage;
        }
      });
    } catch (error) {
      AppErrors.caught('match_live_view._loadLineup', error);
    }
  }

  @override
  Future<void> _refresh() async {
    try {
      final value = await widget.match.getSnapshot(_eventId);
      if (mounted) {
        setState(() {
          _snapshot = value;
          _loaded = true;
        });
      }
    } catch (error) {
      AppErrors.caught('match_live_view._refresh', error);
      if (mounted) setState(() => _loaded = true);
    }
  }

  /// Runs commands whose ids the caller fixed, so a retry resends them.
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
      final text = error.toString().toLowerCase();
      final denied =
          text.contains('42501') ||
          text.contains('not_found') ||
          text.contains('permission denied');
      setState(() {
        _busy = false;
        _error = denied
            ? 'Du saknar behörighet att ändra matchen.'
            : 'Ändringen gick inte igenom. Matchen kan ha ändrats av en annan ledare.';
        _retry = denied ? null : () => _run(action);
      });
      unawaited(_refresh());
      return false;
    }
  }

  // --- Who plays ------------------------------------------------------------

  List<MatchRosterMember> get _players =>
      (_snapshot?.roster ?? const <MatchRosterMember>[])
          .where(
            (member) =>
                _roles[member.personId] != 'leader' &&
                _roles[member.personId] != 'club_functionary',
          )
          .toList();

  List<String> get _starters => [
    for (final starter in _lineup?.starters ?? const <LineupStarter>[])
      starter.personId,
  ];

  List<String> get _onPitch => onPitch(_starters, _snapshot?.facts ?? const []);

  String _name(String? id) {
    if (id == null) return 'Okänd';
    return _snapshot?.people[id] ??
        _snapshot?.roster
            .where((member) => member.personId == id)
            .map((member) => member.name)
            .firstOrNull ??
        _lineup?.players
            .where((player) => player.personId == id)
            .map((player) => player.name)
            .firstOrNull ??
        'Okänd spelare';
  }

  @override
  int get _minuteNow => max(1, _snapshot?.currentMinute ?? 1);

  /// Line-up players missing from the frozen squad (a squad frozen before
  /// the line-up was set, or without callups), who cannot be chosen yet.
  List<String> get _missingFromSquad {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.rosterRevision == 0) return const [];
    if (snapshot.state == 'completed') return const [];
    final frozen = snapshot.roster.map((m) => m.personId).toSet();
    return [
      ..._starters,
      for (final sub in _lineup?.substitutes ?? const <LineupPlayer>[])
        sub.personId,
    ].where((id) => !frozen.contains(id)).toList();
  }

  Future<void> _updateSquad() {
    final key = _newUuid();
    return _run(
      () => widget.match.freezeRoster(key, _eventId, 'manual_correction'),
    );
  }

  // --- Clock ----------------------------------------------------------------

  Future<void> _primaryAction() async {
    final snapshot = _snapshot;
    final key = _newUuid();
    if (snapshot == null || snapshot.state == 'planning') {
      final freezeKey = _newUuid();
      final needsFreeze = (snapshot?.rosterRevision ?? 0) == 0;
      await _run(() async {
        if (needsFreeze) {
          await widget.match.freezeRoster(freezeKey, _eventId, 'initial');
        }
        await widget.match.transition(key, _eventId, 'start');
      });
      return;
    }
    if (snapshot.state != 'live') return;
    await _run(
      () => !snapshot.isPaused
          ? widget.match.transition(key, _eventId, 'pause')
          : snapshot.currentPeriodEnded
          ? widget.match.transitionPeriod(key, _eventId, 'resume')
          : widget.match.transition(key, _eventId, 'resume'),
    );
  }

  Future<void> _endPeriod() {
    final key = _newUuid();
    return _run(() => widget.match.transitionPeriod(key, _eventId, 'end'));
  }

  Future<void> _finish() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Slutsignal?'),
        content: Text(
          'Matchen avslutas ${snapshot.scoreUs}–${snapshot.scoreOpponent}. '
          'Händelser kan fortfarande rättas efteråt.',
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
    await _run(
      () => widget.match.complete(key, _eventId, max(total, _minuteNow - 1)),
    );
  }

  // --- Events ---------------------------------------------------------------

  Future<void> _goal(String side) async {
    if (_state != 'live') return;
    final key = _newUuid();
    if (side == 'opponent') {
      final minute = _minuteNow;
      final ok = await _run(
        () => widget.match.recordGoal(key, _eventId, side, minute),
      );
      if (ok && mounted) _undoSnack('Mål $_opponentName $minute′', key);
      return;
    }
    final pitch = _onPitch.toSet();
    final players = [..._players]
      ..sort(
        (a, b) => (pitch.contains(a.personId) ? 0 : 1).compareTo(
          pitch.contains(b.personId) ? 0 : 1,
        ),
      );
    final choice = await showModalBottomSheet<_GoalChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GoalSheet(players: players, initialMinute: _minuteNow),
    );
    if (choice == null || !mounted) return;
    final placed = await showDialog<((double, double)?, bool)>(
      context: context,
      builder: (_) => const _GoalLocationDialog(),
    );
    if (!mounted) return;
    final place = placed?.$1;
    await _run(
      () => place == null
          ? widget.match.recordGoal(
              key,
              _eventId,
              'us',
              choice.minute,
              scorerId: choice.scorerId,
              assistId: choice.assistId,
            )
          : widget.match.recordEvent(
              key,
              _eventId,
              type: 'goal',
              minute: choice.minute,
              side: 'us',
              playerId: choice.scorerId,
              secondaryId: choice.assistId,
              detail: {'location': locationDetail(place.$1, place.$2)},
            ),
    );
  }

  /// Places (or moves) a goal on the pitch, keeping everything else.
  Future<void> _placeGoal(Map<String, dynamic> fact) async {
    final placed = await showDialog<((double, double)?, bool)>(
      context: context,
      builder: (_) => _GoalLocationDialog(initial: factLocation(fact)),
    );
    final place = placed?.$1;
    if (place == null || !mounted) return;
    final key = _newUuid();
    await _run(
      () => widget.match.updateEvent(
        key,
        fact['id'] as String,
        minute: (fact['minute'] as num? ?? 0).toInt(),
        side: fact['side'] as String?,
        playerId: fact['club_person_id'] as String?,
        secondaryId: fact['secondary_club_person_id'] as String?,
        detail: {
          for (final entry in ((fact['detail'] as Map?) ?? const {}).entries)
            '${entry.key}': entry.value,
          'location': locationDetail(place.$1, place.$2),
        },
      ),
    );
  }

  void _undoSnack(String text, String commandKey) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: SnackBarAction(
            label: 'Ångra',
            onPressed: () {
              final fact = _snapshot?.activeFacts
                  .where((fact) => fact['source_command_id'] == commandKey)
                  .firstOrNull;
              if (fact == null) return;
              final key = _newUuid();
              unawaited(
                _run(() => widget.match.voidEvent(key, fact['id'] as String)),
              );
            },
          ),
        ),
      );
  }

  Future<void> _log(
    LiveEventKind kind, {
    Map<String, dynamic>? fact,
    PlannedSubstitution? planned,
  }) async {
    if (_state != 'live' && fact == null) return;
    final result = await showModalBottomSheet<_LiveEventResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LiveEventSheet(
        kind: kind,
        players: _players,
        onPitch: _onPitch,
        minute: _minuteNow,
        opponentName: _opponentName,
        fact: fact,
        planned: planned ?? _nextPlanned(kind),
        name: _name,
      ),
    );
    if (result == null || !mounted) return;
    final key = _newUuid();
    if (result.delete && fact != null) {
      await _run(() => widget.match.voidEvent(key, fact['id'] as String));
      return;
    }
    final ok = await _run(
      () => fact == null
          ? widget.match.recordEvent(
              key,
              _eventId,
              type: kind.type,
              minute: result.minute,
              side: result.side,
              playerId: result.playerId,
              secondaryId: result.secondaryId,
              detail: result.detail,
            )
          : widget.match.updateEvent(
              key,
              fact['id'] as String,
              minute: result.minute,
              side: result.side,
              playerId: result.playerId,
              secondaryId: result.secondaryId,
              detail: result.detail,
            ),
    );
    if (ok && mounted && fact == null) {
      _undoSnack('${kind.label} ${result.minute}′', key);
    }
  }

  /// The next planned substitution not yet made, offered when Byte opens.
  PlannedSubstitution? _nextPlanned(LiveEventKind kind) {
    if (kind.type != 'substitution') return null;
    final done = donePlannedSubstitutions(_snapshot?.facts ?? const []);
    final pitch = _onPitch.toSet();
    return _lineup?.plan
        .where(
          (sub) =>
              !done.contains(sub.id) &&
              pitch.contains(sub.outId) &&
              !pitch.contains(sub.inId),
        )
        .firstOrNull;
  }

  Future<void> _note() async {
    final note = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _MatchNoteDialog(initialMinute: _minuteNow),
    );
    if (note == null || !mounted) return;
    final key = _newUuid();
    await _run(() => widget.match.recordNote(key, _eventId, note.$1, note.$2));
  }

  Future<void> _openFact(Map<String, dynamic> fact) async {
    if (!_canManage) return;
    final kind = liveEventKind(fact['fact_type'] as String?);
    if (kind != null) return _log(kind, fact: fact);
    if (fact['fact_type'] == 'goal') {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('live-goal-correct'),
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rätta målet'),
                onTap: () => Navigator.pop(sheet, 'correct'),
              ),
              ListTile(
                key: const Key('live-goal-place'),
                leading: const Icon(Icons.place_outlined),
                title: Text(
                  factLocation(fact) == null
                      ? 'Markera på planen'
                      : 'Flytta på planen',
                ),
                onTap: () => Navigator.pop(sheet, 'place'),
              ),
            ],
          ),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'place') return _placeGoal(fact);
    }
    if (fact['fact_type'] == 'goal' || fact['fact_type'] == 'note') {
      final edit = await showModalBottomSheet<_FactEdit>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _FactEditSheet(
          fact: fact,
          players: _players,
          teamName: fact['side'] == 'opponent'
              ? _opponentName
              : widget.sides.team,
          personName: _name,
          canDelete: true,
        ),
      );
      if (edit == null || !mounted) return;
      final key = _newUuid();
      await _run(
        () => edit.delete
            ? widget.match.voidEvent(key, fact['id'] as String)
            : widget.match.correctEvent(
                key,
                fact['id'] as String,
                minute: edit.minute,
                scorerId: edit.scorerId,
                assistId: edit.assistId,
                text: edit.text,
              ),
      );
    }
  }

  List<Widget> _banners(bool manage) => [
    if (_error != null)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: MaterialBanner(
          content: Text(_error!),
          actions: [
            if (_retry != null)
              TextButton(
                onPressed: () => _retry!(),
                child: const Text('Försök igen'),
              ),
            TextButton(
              onPressed: () => setState(() => _error = null),
              child: const Text('Stäng'),
            ),
          ],
        ),
      ),
    if (manage && _missingFromSquad.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: MaterialBanner(
          key: const Key('live-squad-outdated'),
          leading: const Icon(Icons.group_add_outlined),
          content: Text(
            '${_missingFromSquad.length} spelare i uppställningen finns inte '
            'i matchtruppen och kan inte väljas.',
          ),
          actions: [
            TextButton(
              key: const Key('live-squad-update'),
              onPressed: _busy ? null : _updateSquad,
              child: const Text('Uppdatera matchtruppen'),
            ),
          ],
        ),
      ),
  ];

  /// Planläge or the event buttons; a phone starts in Planläge, upright or
  /// lying, a tablet or desktop with the buttons.
  bool? _pitchChoice;

  /// Beside the buttons: the events instead of the shot map, and whose
  /// shots the map shows.
  bool _sideEvents = false;
  String _shotSide = 'us';

  /// The event whose tooltip shows on the pitch, and the one the event
  /// list shows highlighted after a tap on a tooltip.
  String? _tipId, _highlightId;

  Widget? _tooltipFor(String id) {
    final fact = activeFacts(
      _snapshot?.facts ?? const [],
    ).where((f) => f['id'] == id).firstOrNull;
    if (fact == null) return null;
    return _FactTooltip(
      fact: fact,
      text: _factText(fact, _name, _opponentName),
      onTap: () => _showInList(id),
    );
  }

  /// From a tooltip: the event in the list, highlighted.
  void _showInList(String id) {
    setState(() {
      _tipId = null;
      _highlightId = id;
      _sideEvents = true;
    });
    if (_pitchMode(context)) unawaited(_showEvents());
  }

  bool? _reportedCompact;
  bool _pitchMode(BuildContext context) =>
      _pitchChoice ?? MediaQuery.sizeOf(context).shortestSide < 600;

  /// A tap on the pitch in Planläge: the event at that place.
  Future<void> _logAt((double, double) place) async {
    if (_state != 'live') return;
    final result = await showModalBottomSheet<_PitchEventResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PitchEventSheet(
        place: place,
        players: _players,
        onPitch: _onPitch,
        minute: _minuteNow,
        opponentName: _opponentName,
      ),
    );
    if (result == null || !mounted) return;
    final key = _newUuid();
    final ok = await _run(
      () => widget.match.recordEvent(
        key,
        _eventId,
        type: result.type,
        minute: result.minute,
        side: result.side,
        playerId: result.playerId,
        secondaryId: result.secondaryId,
        detail: result.detail,
      ),
    );
    if (ok && mounted) {
      final label = result.type == 'goal'
          ? 'Mål'
          : liveEventKind(result.type)?.label ?? 'Händelse';
      _undoSnack('$label ${result.minute}′', key);
    }
  }

  Future<void> _showCounters() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => StatefulBuilder(
      builder: (sheet, setSheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _LiveCounters(
            counters: _counters,
            onDelta: (key, delta) async {
              final sent = _count(key, delta);
              setSheet(() {});
              await sent;
              if (sheet.mounted) setSheet(() {});
            },
            onEnter: (key) async {
              await _enter(key);
              if (sheet.mounted) setSheet(() {});
            },
          ),
        ),
      ),
    ),
  );

  Future<void> _showEvents() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _LiveTimeline(
          facts: _snapshot?.facts ?? const [],
          name: _name,
          opponentName: _opponentName,
          highlightId: _highlightId,
          onTap: _canManage
              ? (fact) {
                  Navigator.pop(sheet);
                  unawaited(_openFact(fact));
                }
              : null,
        ),
      ),
    ),
  );

  /// A long press on the pitch: the event there, or a choice of those
  /// sharing the place.
  Future<void> _openPlaced(List<Map<String, dynamic>> facts) async {
    if (facts.isEmpty) return;
    final chosen = await showModalBottomSheet<(Map<String, dynamic>, bool)>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _LiveTimeline(
            facts: facts,
            name: _name,
            opponentName: _opponentName,
            title: facts.length == 1
                ? 'Händelsen här'
                : '${facts.length} händelser här',
            onTap: (fact) => Navigator.pop(sheet, (fact, false)),
            onMove: (fact) => Navigator.pop(sheet, (fact, true)),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen.$2) {
      setState(() => _moving = chosen.$1);
    } else {
      await _openFact(chosen.$1);
    }
  }

  /// The event being moved in Planläge, placed by the next tap.
  Map<String, dynamic>? _moving;

  Future<void> _moveTo((double, double) place) async {
    final fact = _moving;
    setState(() => _moving = null);
    if (fact == null) return;
    final key = _newUuid();
    await _run(
      () => widget.match.updateEvent(
        key,
        fact['id'] as String,
        minute: (fact['minute'] as num? ?? 0).toInt(),
        side: fact['side'] as String?,
        playerId: fact['club_person_id'] as String?,
        secondaryId: fact['secondary_club_person_id'] as String?,
        detail: {
          for (final entry in ((fact['detail'] as Map?) ?? const {}).entries)
            '${entry.key}': entry.value,
          'location': locationDetail(place.$1, place.$2),
        },
      ),
    );
  }

  /// Planläge: the score and clock, then the pitch over the rest of the
  /// screen, with substitutions, notes, counters and events below it.
  Widget _pitchLayout(MatchSnapshot? snapshot, bool manage) {
    final facts = snapshot?.facts ?? const <Map<String, dynamic>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LiveHeaderBar(
          snapshot: snapshot,
          sides: widget.sides,
          opponentName: _opponentName,
          busy: _busy,
          onPrimary: _primaryAction,
          onEndPeriod: _endPeriod,
          onFinish: _finish,
          onPhase: widget.onPhase,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._banners(manage),
                Expanded(
                  child: _LivePitchMode(
                    facts: facts,
                    onTapPitch: _logAt,
                    onPressFacts: _openPlaced,
                    selectedId: _tipId,
                    onTapMark: (fact) =>
                        setState(() => _tipId = fact?['id'] as String?),
                    tooltip: _tipId == null ? null : _tooltipFor(_tipId!),
                    onMoveTo: _moving == null ? null : _moveTo,
                    onCancelMove: () => setState(() => _moving = null),
                    actions: [
                      _PitchAction(
                        key: const Key('live-pitch-substitution'),
                        icon: _liveIcon('substitution'),
                        label: 'Byte',
                        onTap: () => _log(liveEventKinds.first),
                      ),
                      _PitchAction(
                        key: const Key('live-pitch-note'),
                        icon: _liveIcon('note'),
                        label: 'Anteckning',
                        onTap: _note,
                      ),
                      if (_counters.isNotEmpty)
                        _PitchAction(
                          key: const Key('live-pitch-counters'),
                          icon: Icons.exposure_plus_1,
                          label: 'Räknare',
                          onTap: _showCounters,
                        ),
                      _PitchAction(
                        key: const Key('live-pitch-events'),
                        icon: Icons.list_alt,
                        label: 'Händelser',
                        onTap: _showEvents,
                      ),
                      _PitchAction(
                        key: const Key('live-layout-buttons'),
                        icon: Icons.grid_view,
                        label: 'Knappar',
                        onTap: () => setState(() => _pitchChoice = false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final snapshot = _snapshot;
    final facts = snapshot?.facts ?? const <Map<String, dynamic>>[];
    final live = _state == 'live';
    final manage = _canManage;
    // On a tablet or desktop the shot map stands beside the event buttons.
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final buttons = manage && live;
    // On a lying tablet the score moves up into one header bar, as in
    // Planläge, to give the buttons and the shot map the height.
    final size = MediaQuery.sizeOf(context);
    final headerBar = buttons && wide && size.width > size.height;
    final pitchMode = buttons && _pitchMode(context);
    final compact = pitchMode || headerBar;
    if (compact != _reportedCompact) {
      _reportedCompact = compact;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onCompact?.call(compact),
      );
    }
    if (pitchMode) return _pitchLayout(snapshot, manage);
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (!headerBar)
          _LiveScoreboard(
            snapshot: snapshot,
            sides: widget.sides,
            opponentName: _opponentName,
            busy: _busy,
            manage: manage,
            onPrimary: _primaryAction,
            onEndPeriod: _endPeriod,
            onFinish: _finish,
            onGoal: live && manage ? _goal : null,
            inline: wide,
          ),
        ..._banners(manage),
        if (manage)
          _LiveToolbar(
            onMyView: _openMyView,
            onOwnButtons: (_buttons?.canEdit ?? false) ? _editButtons : null,
            onPitchMode: buttons
                ? () => setState(() => _pitchChoice = true)
                : null,
            error: _counterError,
            trailing: wide && buttons
                ? _LiveSideControls(
                    events: _sideEvents,
                    side: _shotSide,
                    opponentName: _opponentName,
                    onEvents: (value) => setState(() => _sideEvents = value),
                    onSide: (value) => setState(() => _shotSide = value),
                  )
                : null,
          ),
        if (buttons) ...[
          const SizedBox(height: 4),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  // The counters under the buttons, beside the shot map.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LiveActionGrid(
                        columns: 3,
                        view: _view,
                        tally: eventTally(facts, 'us'),
                        onKind: (kind) => _log(kind),
                        onNote: _note,
                      ),
                      if (_counters.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _LiveCounters(
                          counters: _counters,
                          onDelta: _count,
                          onEnter: _enter,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _sideEvents
                      ? _LiveTimeline(
                          facts: facts,
                          name: _name,
                          opponentName: _opponentName,
                          highlightId: _highlightId,
                          onTap: manage ? _openFact : null,
                        )
                      : _ShotMapCard(
                          facts: facts,
                          opponentName: _opponentName,
                          showEmpty: true,
                          side: _shotSide,
                          selectedId: _tipId,
                          onTapMark: (id) => setState(() => _tipId = id),
                          tooltipFor: _tooltipFor,
                        ),
                ),
              ],
            )
          else
            _LiveActionGrid(
              view: _view,
              tally: eventTally(facts, 'us'),
              onKind: (kind) => _log(kind),
              onNote: _note,
            ),
        ],
        if (buttons && !wide && _counters.isNotEmpty) ...[
          const SizedBox(height: 12),
          _LiveCounters(counters: _counters, onDelta: _count, onEnter: _enter),
        ],
        if (_lineup != null && _starters.isNotEmpty) ...[
          const SizedBox(height: 12),
          _OnPitchCard(
            onPitch: _onPitch,
            bench: [
              for (final player in _players)
                if (!_onPitch.contains(player.personId)) player.personId,
            ],
            name: _name,
            numbers: {
              for (final player in _lineup!.players)
                if (player.number != null) player.personId: player.number!,
            },
          ),
        ],
        if (manage && (_lineup?.plan.isNotEmpty ?? false)) ...[
          const SizedBox(height: 12),
          _LivePlanCard(
            plan: _lineup!.plan,
            done: donePlannedSubstitutions(facts),
            name: _name,
            onMake: live
                ? (sub) => _log(liveEventKinds.first, planned: sub)
                : null,
          ),
        ],
        if (shotPoints(facts).isNotEmpty && !(wide && buttons)) ...[
          const SizedBox(height: 12),
          _ShotMapCard(
            facts: facts,
            opponentName: _opponentName,
            selectedId: _tipId,
            onTapMark: (id) => setState(() => _tipId = id),
            tooltipFor: _tooltipFor,
          ),
        ],
        if (!(wide && buttons)) ...[
          const SizedBox(height: 12),
          _LiveTimeline(
            facts: facts,
            name: _name,
            opponentName: _opponentName,
            highlightId: _highlightId,
            onTap: manage ? _openFact : null,
          ),
        ],
      ],
    );
    if (!headerBar) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LiveHeaderBar(
          snapshot: snapshot,
          sides: widget.sides,
          opponentName: _opponentName,
          busy: _busy,
          onPrimary: _primaryAction,
          onEndPeriod: _endPeriod,
          onFinish: _finish,
          onPhase: widget.onPhase,
          onGoal: _goal,
        ),
        Expanded(child: list),
      ],
    );
  }
}
