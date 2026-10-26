part of '../../app/teamzone_app.dart';

enum _MatchPhase { preparation, live, analysis }

/// One match in the module, as in the old app's match workspace: a match
/// header to swipe (or step) to the previous and next match, with the
/// phases Förberedelse, Live and Efteranalys in it. A played match opens
/// in Efteranalys. Opened from an event in TeamZone it shows that match
/// alone.
class _MatchPage extends StatefulWidget {
  const _MatchPage({
    required this.eventId,
    required this.title,
    required this.calendar,
    required this.match,
    required this.sides,
    this.matches = const [],
    this.live = false,
  });
  final String eventId, title;
  final CalendarServices calendar;
  final MatchServices match;

  /// Who plays the match opened; a stepped-to match brings its own opponent.
  final _MatchSides sides;

  /// Opens in Live, as from the event's Matchläge.
  final bool live;

  /// The matches to step between, in date order; empty for one match.
  final List<ModuleMatch> matches;

  @override
  State<_MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<_MatchPage> {
  late int _index = widget.matches.indexWhere(
    (match) => match.eventId == widget.eventId,
  );

  /// Live in Planläge draws its own single header bar.
  bool _compactLive = false;

  late _MatchPhase _phase = widget.live ? _MatchPhase.live : _phaseFor(_match);

  ModuleMatch? get _match => _index < 0 ? null : widget.matches[_index];

  /// Played: Efteranalys; about to start or under way: Live; else
  /// Förberedelse.
  static _MatchPhase _phaseFor(ModuleMatch? match) {
    if (match == null) return _MatchPhase.preparation;
    final now = DateTime.now();
    if (match.startsAt.isBefore(now.subtract(const Duration(hours: 3)))) {
      return _MatchPhase.analysis;
    }
    if (match.startsAt.isBefore(now.add(const Duration(minutes: 30)))) {
      return _MatchPhase.live;
    }
    return _MatchPhase.preparation;
  }

  void _setPhase(_MatchPhase phase) => setState(() {
    _phase = phase;
    _compactLive = false;
  });

  void _step(int delta) {
    final next = _index + delta;
    if (_index < 0 || next < 0 || next >= widget.matches.length) return;
    setState(() {
      _index = next;
      _phase = _phaseFor(_match);
    });
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    final eventId = match?.eventId ?? widget.eventId;
    final compact = _phase == _MatchPhase.live && _compactLive;
    return Scaffold(
      appBar: compact
          ? null
          : _MatchAppBar(
              match: match,
              title: widget.title,
              sides: widget.sides,
              phase: _phase,
              onPhase: _setPhase,
              onPrevious: _index > 0 ? () => _step(-1) : null,
              onNext: _index >= 0 && _index < widget.matches.length - 1
                  ? () => _step(1)
                  : null,
            ),
      body: switch (_phase) {
        _MatchPhase.preparation => _MatchPreparation(
          key: ValueKey('match-preparation-$eventId'),
          eventId: eventId,
          calendar: widget.calendar,
        ),
        _MatchPhase.live => _MatchLiveView(
          key: ValueKey('match-live-$eventId'),
          eventId: eventId,
          calendar: widget.calendar,
          match: widget.match,
          onPhase: _setPhase,
          onCompact: (value) {
            if (value != _compactLive) setState(() => _compactLive = value);
          },
          sides: match == null
              ? widget.sides
              : (
                  team: widget.sides.team,
                  opponent: match.opponentName,
                  homeAway: match.homeAway,
                ),
        ),
        _MatchPhase.analysis => _MatchAnalysisView(
          key: ValueKey('match-analysis-$eventId'),
          eventId: eventId,
          calendar: widget.calendar,
          match: widget.match,
          sides: match == null
              ? widget.sides
              : (
                  team: widget.sides.team,
                  opponent: match.opponentName,
                  homeAway: match.homeAway,
                ),
        ),
      },
    );
  }
}

/// The match in the app bar, to keep the screen for the match itself:
/// against whom and when, swiped or stepped to the neighbouring matches,
/// with the phases Förberedelse, Live and Efteranalys below it.
class _MatchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _MatchAppBar({
    required this.match,
    required this.title,
    required this.sides,
    required this.phase,
    required this.onPhase,
    this.onPrevious,
    this.onNext,
  });
  final ModuleMatch? match;
  final String title;
  final _MatchSides sides;
  final _MatchPhase phase;
  final ValueChanged<_MatchPhase> onPhase;
  final VoidCallback? onPrevious, onNext;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 64);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final match = this.match;
    final opponent = match?.opponentName ?? sides.opponent;
    final name = opponent?.trim().isNotEmpty == true
        ? '${strings.feature('Mot')} ${opponent!.trim()}'
        : match?.title ?? title;
    final place = switch (match?.homeAway ?? sides.homeAway) {
      'home' => strings.feature('Hemma'),
      'away' => strings.feature('Borta'),
      _ => null,
    };
    final when = match == null
        ? null
        : '${MaterialLocalizations.of(context).formatMediumDate(match.startsAt)} '
              '${TimeOfDay.fromDateTime(match.startsAt).format(context)}';
    return AppBar(
      key: const Key('module-match-header'),
      backgroundColor: colors.primary,
      foregroundColor: Colors.white,
      titleSpacing: 0,
      title: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 200) onPrevious?.call();
          if (velocity < -200) onNext?.call();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              place == null ? name : '$name ($place)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (when != null)
              Text(
                when,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
      ),
      actions: [
        if (match != null) ...[
          IconButton(
            tooltip: strings.feature('Föregående match'),
            disabledColor: Colors.white30,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: strings.feature('Nästa match'),
            disabledColor: Colors.white30,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: SegmentedButton<_MatchPhase>(
              key: const Key('module-match-phase'),
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.standard,
                textStyle: WidgetStatePropertyAll(
                  Theme.of(context).textTheme.labelLarge,
                ),
                minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? colors.primary
                      : Colors.white,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.white
                      : Colors.transparent,
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: Colors.white54),
                ),
              ),
              segments: [
                ButtonSegment(
                  value: _MatchPhase.preparation,
                  label: Text(
                    strings.feature('Förberedelse'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: phase == _MatchPhase.preparation
                          ? colors.primary
                          : Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                ButtonSegment(
                  value: _MatchPhase.live,
                  label: Text(
                    strings.feature('Live'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: phase == _MatchPhase.live
                          ? colors.primary
                          : Colors.white,
                    ),
                  ),
                ),
                ButtonSegment(
                  value: _MatchPhase.analysis,
                  label: Text(
                    strings.feature('Efteranalys'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: phase == _MatchPhase.analysis
                          ? colors.primary
                          : Colors.white,
                    ),
                  ),
                ),
              ],
              selected: {phase},
              onSelectionChanged: (value) => onPhase(value.first),
            ),
          ),
        ),
      ),
    );
  }
}

/// Förberedelse: the line-up on the pitch and the match plan, as the old
/// app's preparation had the starting XI beside the notes.
class _MatchPreparation extends StatefulWidget {
  const _MatchPreparation({
    super.key,
    required this.eventId,
    required this.calendar,
  });
  final String eventId;
  final CalendarServices calendar;

  @override
  State<_MatchPreparation> createState() => _MatchPreparationState();
}

class _MatchPreparationState extends State<_MatchPreparation> {
  bool _plan = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<bool>(
            key: const Key('match-preparation-part'),
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.groups_outlined),
                label: Text(strings.feature('Uppställning')),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.description_outlined),
                label: Text(strings.feature('Matchplan')),
              ),
            ],
            selected: {_plan},
            onSelectionChanged: (value) => setState(() => _plan = value.first),
          ),
        ),
        Expanded(
          // Both stay alive, so switching keeps what is not saved yet.
          child: IndexedStack(
            index: _plan ? 1 : 0,
            children: [
              _MatchLineupEditor(
                eventId: widget.eventId,
                calendar: widget.calendar,
              ),
              _MatchPlanEditor(
                eventId: widget.eventId,
                calendar: widget.calendar,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
