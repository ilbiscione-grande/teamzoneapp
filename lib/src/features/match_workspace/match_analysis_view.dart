part of '../../app/teamzone_app.dart';

/// Efteranalys in the Match module, as the old app's match analysis: the
/// result and both teams' numbers, the events on the pitch, minutes and
/// numbers per player, the KPI goals' outcome with the own buttons, the
/// written report and the event list. All of it is the match's own facts,
/// line-up and follow-up; the report is the event's match report.
class _MatchAnalysisView extends StatefulWidget {
  const _MatchAnalysisView({
    super.key,
    required this.eventId,
    required this.calendar,
    required this.match,
    required this.sides,
  });
  final String eventId;
  final CalendarServices calendar;
  final MatchServices match;
  final _MatchSides sides;

  @override
  State<_MatchAnalysisView> createState() => _MatchAnalysisViewState();
}

class _MatchAnalysisViewState extends State<_MatchAnalysisView> {
  MatchSnapshot? _snapshot;
  MatchLineup? _lineup;
  EventFollowup? _followup;
  MatchButtons? _buttons;
  WrittenMatchReport? _report;
  bool _loaded = false;

  /// The pitch's filters, the event whose tooltip shows and the one the
  /// list shows highlighted.
  String _side = 'all';
  int _period = 0;
  Set<String>? _types;
  String? _tipId, _highlightId;

  /// Each draft from the events words it anew.
  int _reportVariant = 0;

  String get _eventId => widget.eventId;
  String get _opponentName {
    final name = widget.sides.opponent?.trim();
    return name == null || name.isEmpty ? 'Motståndare' : name;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<T?> _quiet<T>(Future<T?> future) =>
      future.then<T?>((value) => value, onError: (_) => null);

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      _quiet(widget.match.getSnapshot(_eventId)),
      _quiet(widget.calendar.matchPlans.getLineup(_eventId)),
      _quiet(widget.calendar.preparation.getFollowup(_eventId)),
      _quiet(widget.calendar.matchPlans.getButtons(_eventId)),
      _quiet(widget.match.getReport(_eventId)),
    ]);
    if (!mounted) return;
    setState(() {
      _snapshot = results[0] as MatchSnapshot?;
      _lineup = results[1] as MatchLineup?;
      _followup = results[2] as EventFollowup?;
      _buttons = results[3] as MatchButtons?;
      _report = results[4] as WrittenMatchReport?;
      _loaded = true;
    });
  }

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
        _lineup?.starters
            .where((starter) => starter.personId == id)
            .map((starter) => starter.name)
            .firstOrNull ??
        'Okänd spelare';
  }

  int? _number(String id) =>
      _lineup?.players
          .where((player) => player.personId == id)
          .map((player) => player.number)
          .firstOrNull ??
      _lineup?.starters
          .where((starter) => starter.personId == id)
          .map((starter) => starter.number)
          .firstOrNull;

  List<Map<String, dynamic>> get _facts => _snapshot?.facts ?? const [];

  Widget? _tooltipFor(String id) {
    final fact = activeFacts(_facts).where((f) => f['id'] == id).firstOrNull;
    if (fact == null) return null;
    return _FactTooltip(
      fact: fact,
      text: _factText(fact, _name, _opponentName),
      onTap: () => setState(() {
        _tipId = null;
        _highlightId = id;
      }),
    );
  }

  /// The report to write: as it is, or with [body] (a draft from the
  /// events) to read and change before it is saved.
  Future<void> _writeReport({String? body}) async {
    final report = _report;
    if (report == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WrittenReportDialog(
        eventId: _eventId,
        match: widget.match,
        report: body == null
            ? report
            : WrittenMatchReport(
                body: body,
                published: report.published,
                revision: report.revision,
                canEdit: report.canEdit,
                canPublish: report.canPublish,
              ),
      ),
    );
    if (saved == true && mounted) {
      final fresh = await _quiet(widget.match.getReport(_eventId));
      if (mounted) setState(() => _report = fresh ?? _report);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.state == 'planning') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Efteranalysen fylls i när matchen har spelats i Live.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final facts = _facts;
    final end = matchEndMinute(
      state: snapshot.state,
      facts: facts,
      periodMinutes: snapshot.periodMinutes,
      current: snapshot.currentMinute,
    );
    final starters = [
      for (final starter in _lineup?.starters ?? const <LineupStarter>[])
        starter.personId,
    ];
    final summary = _AnalysisSummary(
      sides: widget.sides,
      opponentName: _opponentName,
      scoreUs: snapshot.scoreUs,
      scoreOpponent: snapshot.scoreOpponent,
      completed: snapshot.state == 'completed',
      us: teamTotals(facts, 'us'),
      them: teamTotals(facts, 'opponent'),
    );
    final pitch = _AnalysisPitch(
      facts: facts,
      periodMinutes: snapshot.periodMinutes,
      opponentName: _opponentName,
      side: _side,
      period: _period,
      types: _types,
      onSide: (value) => setState(() => _side = value),
      onPeriod: (value) => setState(() => _period = value),
      onTypes: (value) => setState(() => _types = value),
      selectedId: _tipId,
      onTapMark: (id) => setState(() => _tipId = id),
      tooltipFor: _tooltipFor,
    );
    final players = _AnalysisPlayers(
      stats: playerStats(starters: starters, facts: facts, end: end),
      name: _name,
      number: _number,
      end: end,
    );
    final kpis = _AnalysisKpis(
      kpis: _followup?.kpis ?? const [],
      buttons: _buttons?.buttons ?? const [],
      counts: buttonCounts(facts),
    );
    final report = _AnalysisReport(
      report: _report,
      onWrite: _report?.canEdit == true ? () => _writeReport() : null,
      onGenerate: _report?.canEdit == true
          ? () => _writeReport(
              body: generatedMatchReport(
                team: widget.sides.team,
                opponent: _opponentName,
                homeAway: widget.sides.homeAway,
                scoreUs: snapshot.scoreUs,
                scoreOpponent: snapshot.scoreOpponent,
                completed: snapshot.state == 'completed',
                facts: facts,
                periodMinutes: snapshot.periodMinutes,
                name: _name,
                variant: _reportVariant++,
                kpis: [
                  for (final kpi in _followup?.kpis ?? const <EventKpi>[])
                    (
                      label: kpi.label,
                      value: kpi.actual == null
                          ? 'ej ifyllt'
                          : _kpiValueText(kpi.valueType, kpi.actual),
                      goal: _kpiGoalText(kpi),
                      achieved: switch (kpi.status) {
                        'achieved' => true,
                        'missed' => false,
                        _ => null,
                      },
                    ),
                ],
              ),
            )
          : null,
    );
    final events = _LiveTimeline(
      facts: facts,
      name: _name,
      opponentName: _opponentName,
      highlightId: _highlightId,
    );
    const gap = SizedBox(height: 12);
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, box) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: box.maxWidth >= 900
              ? [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(children: [summary, gap, pitch]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [players, gap, kpis, gap, report],
                        ),
                      ),
                    ],
                  ),
                  gap,
                  events,
                ]
              : [
                  summary,
                  gap,
                  pitch,
                  gap,
                  players,
                  gap,
                  kpis,
                  gap,
                  report,
                  gap,
                  events,
                ],
        ),
      ),
    );
  }
}
