part of '../../app/teamzone_app.dart';

/// Live's counters and Min vy: the KPI goals from Förberedelse (counted
/// through the event's follow-up, as in the built-in match mode), the
/// team's own buttons, and which buttons this leader sees.
mixin _LiveCounterState on State<_MatchLiveView> {
  MatchButtons? _buttons;
  EventFollowup? _followup;
  final _pending = <String, int>{};
  String? _counterError;

  String get _eventId;
  int get _minuteNow;
  List<Map<String, dynamic>> get _facts;
  Future<void> _refresh();

  Set<String>? get _view => _buttons?.myView;

  List<EventKpi> get _kpis => (_followup?.kpis ?? const <EventKpi>[])
      .where((kpi) => kpi.isManual)
      .toList();

  Future<void> _loadCounters() async {
    final buttons = await widget.calendar.matchPlans
        .getButtons(_eventId)
        .then<MatchButtons?>((value) => value, onError: (_) => null);
    final followup = await widget.calendar.preparation
        .getFollowup(_eventId)
        .then<EventFollowup?>((value) => value, onError: (_) => null);
    if (!mounted) return;
    setState(() {
      _buttons = buttons ?? _buttons;
      _followup = followup ?? _followup;
    });
  }

  /// The counters Min vy shows: KPI goals first, then own buttons.
  List<_LiveCounter> get _counters {
    final counts = buttonCounts(_facts);
    return [
      for (final kpi in _kpis)
        if (shownInView(_view, kpiKey(kpi.id)))
          (
            key: kpiKey(kpi.id),
            label: kpi.label,
            value: kpi.actual,
            goal: 'Mål: ${_kpiGoalText(kpi)}',
            pending: _pending[kpiKey(kpi.id)] ?? 0,
            counted: kpi.valueType == 'count',
          ),
      for (final button in _buttons?.buttons ?? const <MatchButton>[])
        if (shownInView(_view, buttonKey(button.id)))
          (
            key: buttonKey(button.id),
            label: button.label,
            value: counts[button.id] ?? 0,
            goal: null,
            pending: _pending[buttonKey(button.id)] ?? 0,
            counted: true,
          ),
    ];
  }

  /// A tap on −/+: shown as pending until the server has it.
  Future<void> _count(String key, int delta) async {
    final commandId = _newUuid();
    final minute = _minuteNow;
    setState(() {
      _pending.update(key, (v) => v + delta, ifAbsent: () => delta);
      _counterError = null;
    });
    try {
      if (key.startsWith('kpi:')) {
        await widget.calendar.preparation.recordKpiTick(
          commandId: commandId,
          eventId: _eventId,
          targetId: key.substring(4),
          delta: delta,
          minute: minute,
        );
        final followup = await widget.calendar.preparation.getFollowup(
          _eventId,
        );
        if (mounted) setState(() => _followup = followup);
      } else {
        await widget.calendar.matchPlans.recordButton(
          commandId,
          _eventId,
          key.substring(7),
          delta,
          minute,
        );
        await _refresh();
      }
    } catch (error) {
      AppErrors.caught('match_live_counter_state._count', error);
      if (mounted) {
        setState(() => _counterError = 'Räknaren kunde inte sparas.');
      }
    } finally {
      if (mounted) {
        setState(() {
          final left = (_pending[key] ?? 0) - delta;
          left == 0 ? _pending.remove(key) : _pending[key] = left;
        });
      }
    }
  }

  /// A KPI goal that is not counted gets its value entered.
  Future<void> _enter(String key) async {
    final kpi = _kpis.where((k) => kpiKey(k.id) == key).firstOrNull;
    if (kpi == null) return;
    final result = await showDialog<(bool, double?)>(
      context: context,
      builder: (_) => _KpiValueDialog(kpi: kpi),
    );
    if (result == null || !result.$1 || !mounted) return;
    try {
      await widget.calendar.preparation.recordKpiValue(
        kpi.id,
        result.$2,
        kpi.revision,
      );
    } catch (error) {
      AppErrors.caught('match_live_counter_state._enter', error);
      if (mounted) {
        setState(() => _counterError = '${kpi.label} kunde inte sparas.');
      }
    }
    await _loadCounters();
  }

  Future<void> _openMyView() async {
    final chosen = await showDialog<(Set<String>?,)>(
      context: context,
      builder: (_) => _MyViewDialog(
        initial: _view,
        options: [
          (
            'Händelser',
            [
              for (final kind in liveEventKinds) (kind.type, kind.label),
              (noteKey, 'Anteckning'),
            ],
          ),
          ('Matchmål', [for (final kpi in _kpis) (kpiKey(kpi.id), kpi.label)]),
          (
            'Egna knappar',
            [
              for (final button in _buttons?.buttons ?? const <MatchButton>[])
                (buttonKey(button.id), button.label),
            ],
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await widget.calendar.matchPlans.saveMyView(_eventId, chosen.$1);
    } catch (error) {
      AppErrors.caught('match_live_counter_state._openMyView', error);
      if (mounted) setState(() => _counterError = 'Min vy kunde inte sparas.');
    }
    await _loadCounters();
  }

  Future<void> _editButtons() async {
    final buttons = _buttons;
    if (buttons == null) return;
    final edited = await showDialog<List<MatchButton>>(
      context: context,
      builder: (_) => _OwnButtonsDialog(initial: buttons.buttons),
    );
    if (edited == null || !mounted) return;
    try {
      await widget.calendar.matchPlans.saveButtons(
        _eventId,
        edited,
        buttons.revision,
      );
    } catch (error) {
      AppErrors.caught('match_live_counter_state._editButtons', error);
      if (mounted) {
        setState(
          () => _counterError = error is MatchPlanConflict
              ? 'Knapparna har ändrats av någon annan. De senaste visas nu.'
              : 'Knapparna kunde inte sparas.',
        );
      }
    }
    await _loadCounters();
  }
}
