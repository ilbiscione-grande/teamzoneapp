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
    this.matches = const [],
  });
  final String eventId, title;
  final CalendarServices calendar;

  /// The matches to step between, in date order; empty for one match.
  final List<ModuleMatch> matches;

  @override
  State<_MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<_MatchPage> {
  late int _index = widget.matches.indexWhere(
    (match) => match.eventId == widget.eventId,
  );
  late _MatchPhase _phase = _phaseFor(_match);

  ModuleMatch? get _match => _index < 0 ? null : widget.matches[_index];

  static _MatchPhase _phaseFor(ModuleMatch? match) =>
      match != null &&
          match.startsAt.isBefore(
            DateTime.now().subtract(const Duration(hours: 3)),
          )
      ? _MatchPhase.analysis
      : _MatchPhase.preparation;

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
    final strings = AppStrings.of(context);
    final match = _match;
    final eventId = match?.eventId ?? widget.eventId;
    Widget later(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(strings.feature(text), textAlign: TextAlign.center),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(strings.feature('Match'))),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _MatchHeader(
              match: match,
              title: widget.title,
              phase: _phase,
              onPhase: (phase) => setState(() => _phase = phase),
              onPrevious: _index > 0 ? () => _step(-1) : null,
              onNext: _index >= 0 && _index < widget.matches.length - 1
                  ? () => _step(1)
                  : null,
            ),
          ),
          Expanded(
            child: switch (_phase) {
              _MatchPhase.preparation => _MatchPreparation(
                key: ValueKey('match-preparation-$eventId'),
                eventId: eventId,
                calendar: widget.calendar,
              ),
              _MatchPhase.live => later(
                'Live i Matchmodulen kommer i nästa steg. Tills dess loggar du '
                'matchen i Matchläge under aktiviteten.',
              ),
              _MatchPhase.analysis => later(
                'Efteranalysen med speltid, statistik och händelser på planen '
                'kommer när livedelen är klar.',
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// The match header: when and against whom, swiped or stepped to the
/// neighbouring matches, with the phases below.
class _MatchHeader extends StatelessWidget {
  const _MatchHeader({
    required this.match,
    required this.title,
    required this.phase,
    required this.onPhase,
    this.onPrevious,
    this.onNext,
  });
  final ModuleMatch? match;
  final String title;
  final _MatchPhase phase;
  final ValueChanged<_MatchPhase> onPhase;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final match = this.match;
    final name = match?.opponentName?.isNotEmpty == true
        ? '${strings.feature('Mot')} ${match!.opponentName}'
        : match?.title ?? title;
    final place = switch (match?.homeAway) {
      'home' => strings.feature('Hemma'),
      'away' => strings.feature('Borta'),
      _ => null,
    };
    final when = match == null
        ? null
        : '${MaterialLocalizations.of(context).formatFullDate(match.startsAt)} '
              '${TimeOfDay.fromDateTime(match.startsAt).format(context)}';
    const white = TextStyle(color: Colors.white);
    Widget arrow(IconData icon, VoidCallback? onTap, String tip) => IconButton(
      tooltip: strings.feature(tip),
      color: Colors.white,
      disabledColor: Colors.white24,
      onPressed: onTap,
      icon: Icon(icon),
    );
    return DecoratedBox(
      key: const Key('module-match-header'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            colors.primary,
            Color.lerp(colors.primary, Colors.black, 0.4)!,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity > 200) onPrevious?.call();
                if (velocity < -200) onNext?.call();
              },
              child: Row(
                children: [
                  if (match != null)
                    arrow(Icons.chevron_left, onPrevious, 'Föregående match'),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: match == null ? 12 : 0,
                      ),
                      child: Column(
                        children: [
                          if (when != null)
                            Text(
                              when,
                              textAlign: TextAlign.center,
                              style: white.copyWith(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          Text(
                            place == null ? name : '$name ($place)',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: white.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (match != null)
                    arrow(Icons.chevron_right, onNext, 'Nästa match'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SegmentedButton<_MatchPhase>(
                key: const Key('module-match-phase'),
                showSelectedIcon: false,
                style: ButtonStyle(
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
                    label: Text(strings.feature('Förberedelse')),
                  ),
                  ButtonSegment(
                    value: _MatchPhase.live,
                    label: Text(strings.feature('Live')),
                  ),
                  ButtonSegment(
                    value: _MatchPhase.analysis,
                    label: Text(strings.feature('Efteranalys')),
                  ),
                ],
                selected: {phase},
                onSelectionChanged: (value) => onPhase(value.first),
              ),
            ),
          ],
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
