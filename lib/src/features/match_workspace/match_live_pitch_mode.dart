part of '../../app/teamzone_app.dart';

/// Planläge, Live on a phone: the pitch over most of the screen, standing
/// up with our goal at the bottom. A double tap where something happened opens
/// the event, with the place already set; what is placed shows on the
/// pitch and opens again with a long press (a choice when several share
/// the place); a double tap on it adds another. Substitutions, notes, counters and
/// the event list sit in a row below.
class _LivePitchMode extends StatelessWidget {
  const _LivePitchMode({
    required this.facts,
    required this.onTapPitch,
    required this.onPressFacts,
    required this.actions,
    this.onMoveTo,
    this.onCancelMove,
  });
  final List<Map<String, dynamic>> facts;
  final ValueChanged<(double, double)>? onTapPitch;

  /// A long press on a mark: the events placed there (or very near).
  final ValueChanged<List<Map<String, dynamic>>>? onPressFacts;
  final List<Widget> actions;

  /// Moving an event: a single tap puts it there; [onCancelMove] stops.
  final ValueChanged<(double, double)>? onMoveTo;
  final VoidCallback? onCancelMove;

  @override
  Widget build(BuildContext context) {
    final placed = [
      for (final fact in activeFacts(facts))
        if (factLocation(fact) case (final x, final y)) (fact, x, y),
    ];
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 68 / 105,
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth, h = box.maxHeight;
                  const mark = 26.0;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: GestureDetector(
                      key: const Key('live-pitch'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: onMoveTo == null
                          ? null
                          : (details) => onMoveTo!((
                              (1 - details.localPosition.dy / h).clamp(
                                0.0,
                                1.0,
                              ),
                              (details.localPosition.dx / w).clamp(0.0, 1.0),
                            )),
                      // A double tap adds, so a stray touch does not.
                      onDoubleTapDown: onTapPitch == null || onMoveTo != null
                          ? null
                          : (details) => onTapPitch!((
                              (1 - details.localPosition.dy / h).clamp(
                                0.0,
                                1.0,
                              ),
                              (details.localPosition.dx / w).clamp(0.0, 1.0),
                            )),
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: CustomPaint(painter: _PitchPainter()),
                          ),
                          Positioned(
                            top: 6,
                            left: 0,
                            right: 0,
                            child: Text(
                              'Anfall ↑',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (onMoveTo != null)
                            Positioned(
                              top: 24,
                              left: 12,
                              right: 12,
                              child: Material(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.all(10),
                                        child: Text(
                                          'Tryck där händelsen ska ligga',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      key: const Key('live-move-cancel'),
                                      onPressed: onCancelMove,
                                      child: const Text(
                                        'Avbryt',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (onTapPitch != null && placed.isEmpty)
                            Center(
                              child: Text(
                                'Dubbeltryck där det händer',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          for (final (fact, x, y) in placed)
                            Positioned(
                              left: y * w - mark / 2,
                              top: (1 - x) * h - mark / 2,
                              width: mark,
                              height: mark,
                              // Only a long press: a double tap goes to the
                              // pitch and adds another event at the place.
                              child: GestureDetector(
                                key: Key('live-pitch-fact-${fact['id']}'),
                                onLongPress: onPressFacts == null
                                    ? null
                                    : () => onPressFacts!([
                                        for (final (other, ox, oy) in placed)
                                          if ((ox - x).abs() < 0.03 &&
                                              (oy - y).abs() < 0.04)
                                            other,
                                      ]),
                                child: _FactMark(fact: fact),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [for (final action in actions) Expanded(child: action)]),
      ],
    );
  }
}

/// A placed event on the pitch: its icon, ours in the module's colour,
/// theirs red, a goal gold.
class _FactMark extends StatelessWidget {
  const _FactMark({required this.fact});
  final Map<String, dynamic> fact;

  @override
  Widget build(BuildContext context) {
    final goal = fact['fact_type'] == 'goal';
    final ours = fact['side'] != 'opponent';
    final color = goal
        ? const Color(0xFFF2B705)
        : ours
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFFD84343);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
      ),
      child: Icon(
        _liveIcon(fact['fact_type'] as String?),
        size: 14,
        color: goal ? Colors.black87 : Colors.white,
      ),
    );
  }
}

/// A goal as Planläge registers it: scorer and assist, with the place.
const _goalKind = LiveEventKind(
  type: 'goal',
  label: 'Mål',
  secondaryLabel: 'Assist',
  locatable: true,
);

/// The kinds a tap on the pitch can be: those with a place, and goals.
List<LiveEventKind> get _pitchKinds => [
  liveEventKinds.firstWhere((kind) => kind.type == 'shot'),
  _goalKind,
  for (final kind in liveEventKinds)
    if (kind.type != 'shot' && kind.type != 'substitution') kind,
];

class _PitchEventResult {
  const _PitchEventResult({
    required this.type,
    required this.minute,
    required this.side,
    this.playerId,
    this.secondaryId,
    this.detail = const {},
  });
  final String type, side;
  final int minute;
  final String? playerId, secondaryId;
  final Map<String, Object?> detail;
}

/// The event at the place tapped: what kind (a shot to begin with, by our
/// half or theirs whose it likely is), the minute, the result, who (with
/// an assist for a goal) and a note.
class _PitchEventSheet extends StatefulWidget {
  const _PitchEventSheet({
    required this.place,
    required this.players,
    required this.onPitch,
    required this.minute,
    required this.opponentName,
  });
  final (double, double) place;
  final List<MatchRosterMember> players;
  final List<String> onPitch;
  final int minute;
  final String opponentName;

  @override
  State<_PitchEventSheet> createState() => _PitchEventSheetState();
}

class _PitchEventSheetState extends State<_PitchEventSheet> {
  LiveEventKind _kind = _pitchKinds.first;
  // Their half is where we attack, ours where they do.
  late String _side = widget.place.$1 >= 0.5 ? 'us' : 'opponent';
  late int _minute = widget.minute;
  late String? _result = _kind.defaultResult;
  String? _player, _secondary;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Players on the pitch first.
  List<MatchRosterMember> get _players {
    final pitch = widget.onPitch.toSet();
    return [...widget.players]..sort(
      (a, b) => (pitch.contains(a.personId) ? 0 : 1).compareTo(
        pitch.contains(b.personId) ? 0 : 1,
      ),
    );
  }

  Widget _picker(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String?>(
    key: Key('pitch-sheet-$label'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('Ingen vald')),
      for (final player in _players)
        DropdownMenuItem<String?>(
          value: player.personId,
          child: Text(player.name),
        ),
    ],
    onChanged: onChanged,
  );

  void _save() {
    final us = _side == 'us';
    final comment = _comment.text.trim();
    Navigator.pop(
      context,
      _PitchEventResult(
        type: _kind.type,
        minute: _minute,
        side: _side,
        playerId: us ? _player : null,
        secondaryId: us && _kind.type == 'goal' ? _secondary : null,
        detail: {
          if (_result != null && _kind.results.isNotEmpty)
            _kind.resultKey: _result,
          if (comment.isNotEmpty) 'comment': comment,
          'location': locationDetail(widget.place.$1, widget.place.$2),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final us = _side == 'us';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
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
                      'Ny händelse',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'En minut tidigare',
                    onPressed: _minute > 0
                        ? () => setState(() => _minute--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text("$_minute′", style: theme.textTheme.titleMedium),
                  IconButton(
                    tooltip: 'En minut senare',
                    onPressed: () => setState(() => _minute++),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kind in _pitchKinds)
                    ChoiceChip(
                      key: Key('pitch-sheet-kind-${kind.type}'),
                      avatar: Icon(_liveIcon(kind.type), size: 16),
                      label: Text(kind.label),
                      selected: _kind.type == kind.type,
                      onSelected: (_) => setState(() {
                        _kind = kind;
                        _result = kind.defaultResult;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                key: const Key('pitch-sheet-side'),
                segments: [
                  const ButtonSegment(value: 'us', label: Text('Vi')),
                  ButtonSegment(
                    value: 'opponent',
                    label: Text(
                      widget.opponentName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_side},
                onSelectionChanged: (value) =>
                    setState(() => _side = value.first),
              ),
              if (_kind.results.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (value, label) in _kind.results)
                      ChoiceChip(
                        key: Key('pitch-sheet-result-$value'),
                        label: Text(label),
                        selected: _result == value,
                        onSelected: (_) => setState(() => _result = value),
                      ),
                  ],
                ),
              ],
              if (us) ...[
                const SizedBox(height: 10),
                _picker(
                  _kind.type == 'goal'
                      ? 'Målskytt'
                      : _kind.type == 'save'
                      ? 'Målvakt'
                      : 'Spelare',
                  _player,
                  (id) => setState(() => _player = id),
                ),
                if (_kind.type == 'goal') ...[
                  const SizedBox(height: 8),
                  _picker(
                    'Assist',
                    _secondary,
                    (id) => setState(() => _secondary = id),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              TextField(
                key: const Key('pitch-sheet-comment'),
                controller: _comment,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Anteckning (frivilligt)',
                  isDense: true,
                ),
              ),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Avbryt'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('pitch-sheet-save'),
                    onPressed:
                        _kind.type == 'goal' &&
                            us &&
                            _player != null &&
                            _player == _secondary
                        ? null
                        : _save,
                    child: const Text('Registrera'),
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

/// One action below the pitch: an icon with a short word under it.
class _PitchAction extends StatelessWidget {
  const _PitchAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Planläge's one header, in place of the page's app bar and the
/// scoreboard: back, the score with the clock and period, pause or resume,
/// the period menu and the other phases.
class _LiveHeaderBar extends StatelessWidget {
  const _LiveHeaderBar({
    required this.snapshot,
    required this.sides,
    required this.opponentName,
    required this.busy,
    required this.onPrimary,
    required this.onEndPeriod,
    required this.onFinish,
    this.onPhase,
  });
  final MatchSnapshot? snapshot;
  final _MatchSides sides;
  final String opponentName;
  final bool busy;
  final VoidCallback onPrimary, onEndPeriod, onFinish;
  final ValueChanged<_MatchPhase>? onPhase;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = snapshot;
    final us = '${sides.team} ${value?.scoreUs ?? 0}';
    final them = '${value?.scoreOpponent ?? 0} $opponentName';
    final score = sides.homeAway == 'away'
        ? '$opponentName ${value?.scoreOpponent ?? 0}–${value?.scoreUs ?? 0} ${sides.team}'
        : '$us–$them';
    final primary = _LiveScoreboard.primaryOf(value);
    final live = value?.state == 'live';
    return Material(
      key: const Key('live-header'),
      color: colors.primary,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 68,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Row(
              children: [
                const BackButton(color: Colors.white),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        score,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_LiveScoreboard.clockOf(value)} · ${_LiveScoreboard.captionOf(value)}',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                if (primary != null)
                  IconButton(
                    key: const Key('live-primary'),
                    tooltip: primary.$2,
                    onPressed: busy ? null : onPrimary,
                    icon: Icon(primary.$1),
                  ),
                if (live || onPhase != null)
                  PopupMenuButton<VoidCallback>(
                    key: const Key('live-header-menu'),
                    tooltip: 'Matchen och vyer',
                    iconColor: Colors.white,
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      if (live) ...[
                        const _MenuHeading('Matchen'),
                        if (!value!.isPaused &&
                            value.currentPeriod < value.periodMinutes.length)
                          PopupMenuItem(
                            value: onEndPeriod,
                            child: Text(
                              'Avsluta ${_LiveScoreboard._period(value.currentPeriod, value.periodMinutes.length).toLowerCase()}',
                            ),
                          ),
                        PopupMenuItem(
                          value: onFinish,
                          child: const Text('Slutsignal'),
                        ),
                      ],
                      if (live && onPhase != null) const PopupMenuDivider(),
                      if (onPhase != null) ...[
                        const _MenuHeading('Gå till'),
                        PopupMenuItem(
                          key: const Key('live-header-preparation'),
                          value: () => onPhase!(_MatchPhase.preparation),
                          child: const Text('Förberedelse'),
                        ),
                        PopupMenuItem(
                          key: const Key('live-header-analysis'),
                          value: () => onPhase!(_MatchPhase.analysis),
                          child: const Text('Efteranalys'),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section's heading in a popup menu, not choosable.
class _MenuHeading extends PopupMenuEntry<VoidCallback> {
  const _MenuHeading(this.text);
  final String text;

  @override
  double get height => 32;

  @override
  bool represents(VoidCallback? value) => false;

  @override
  State<_MenuHeading> createState() => _MenuHeadingState();
}

class _MenuHeadingState extends State<_MenuHeading> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Text(
        widget.text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
