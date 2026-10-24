part of '../../app/teamzone_app.dart';

/// The score, the clock and its controls, and a goal button per side: the
/// old app's clock card in the module's colours.
class _LiveScoreboard extends StatelessWidget {
  const _LiveScoreboard({
    required this.snapshot,
    required this.sides,
    required this.opponentName,
    required this.busy,
    required this.manage,
    required this.onPrimary,
    required this.onEndPeriod,
    required this.onFinish,
    this.onGoal,
    this.inline = false,
  });
  final MatchSnapshot? snapshot;
  final _MatchSides sides;
  final String opponentName;
  final bool busy, manage;
  final VoidCallback onPrimary, onEndPeriod, onFinish;
  final ValueChanged<String>? onGoal;

  /// Play and the period menu to the right of the clock (tablet and
  /// desktop) rather than under it.
  final bool inline;

  static String _period(int period, int count) => count == 2
      ? '$period:a halvlek'
      : count == 1
      ? 'Matchen'
      : 'Period $period';

  String get _caption => captionOf(snapshot);
  String get _clock => clockOf(snapshot);
  (IconData, String)? get _primary => primaryOf(snapshot);

  static String captionOf(MatchSnapshot? value) {
    if (value == null || value.state == 'planning') return 'Ej startad';
    if (value.state == 'completed') return 'Slutresultat';
    final count = value.periodMinutes.length;
    if (value.currentPeriodEnded) {
      return count == 2 && value.currentPeriod == 1
          ? 'Halvtid'
          : 'Paus efter period ${value.currentPeriod}';
    }
    final name = _period(value.currentPeriod, count);
    return value.isPaused ? '$name · pausad' : name;
  }

  static String clockOf(MatchSnapshot? value) {
    if (value == null || value.state == 'planning') return '00:00';
    final elapsed = value.elapsedNow();
    return '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
        '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  static (IconData, String)? primaryOf(MatchSnapshot? value) => switch (value) {
    null ||
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
        'Starta ${_period(currentPeriod + 1, periodMinutes.length).toLowerCase()}',
      ),
    MatchSnapshot(state: 'live') => (Icons.play_arrow, 'Fortsätt'),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = snapshot;
    final weLeft = sides.homeAway != 'away';
    final us = (sides.team, value?.scoreUs ?? 0, 'us');
    final them = (opponentName, value?.scoreOpponent ?? 0, 'opponent');
    final left = weLeft ? us : them, right = weLeft ? them : us;
    const white = TextStyle(color: Colors.white);
    Widget side((String, int, String) team) => Expanded(
      child: Column(
        children: [
          Text(
            team.$1,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: white.copyWith(fontWeight: FontWeight.w700),
          ),
          // The goal button beside the score, to keep the board low.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${team.$2}',
                style: white.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (onGoal != null) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: Key('live-goal-${team.$3}'),
                  tooltip: 'Mål ${team.$1}',
                  onPressed: busy ? null : () => onGoal!(team.$3),
                  icon: const Icon(Icons.sports_soccer),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    final primary = _primary;
    final live = value?.state == 'live';
    final clock = Text(
      _clock,
      style: white.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final controls = manage && (primary != null || live)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (primary != null)
                _LivePrimaryButton(
                  icon: primary.$1,
                  label: primary.$2,
                  compact: live,
                  busy: busy,
                  onPressed: onPrimary,
                ),
              if (live)
                PopupMenuButton<VoidCallback>(
                  key: const Key('live-period-menu'),
                  icon: const Icon(Icons.sports),
                  tooltip: 'Period och slutsignal',
                  iconColor: Colors.white,
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    if (!value!.isPaused &&
                        value.currentPeriod < value.periodMinutes.length)
                      PopupMenuItem(
                        value: onEndPeriod,
                        child: Text(
                          'Avsluta ${_period(value.currentPeriod, value.periodMinutes.length).toLowerCase()}',
                        ),
                      ),
                    PopupMenuItem(
                      value: onFinish,
                      child: const Text('Slutsignal'),
                    ),
                  ],
                ),
            ],
          )
        : null;
    return DecoratedBox(
      key: const Key('live-scoreboard'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, Colors.black, 0.5)!,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                side(left),
                Column(
                  children: [
                    Text(
                      _caption,
                      style: white.copyWith(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    if (inline)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          clock,
                          if (controls != null) ...[
                            const SizedBox(width: 8),
                            controls,
                          ],
                        ],
                      )
                    else ...[
                      clock,
                      ?controls,
                    ],
                  ],
                ),
                side(right),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Start, pause, resume or the next period: beside the menu between the
/// scores, an icon alone while the match runs.
class _LivePrimaryButton extends StatelessWidget {
  const _LivePrimaryButton({
    required this.icon,
    required this.label,
    required this.compact,
    required this.busy,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final bool compact, busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: colors.primary,
      shape: const StadiumBorder(),
      padding: compact ? const EdgeInsets.all(8) : null,
      minimumSize: compact ? const Size(40, 40) : const Size(0, 40),
    );
    final glyph = busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);
    return Tooltip(
      message: label,
      child: compact
          ? FilledButton(
              key: const Key('live-primary'),
              style: style,
              onPressed: busy ? null : onPressed,
              child: glyph,
            )
          : FilledButton.icon(
              key: const Key('live-primary'),
              style: style,
              onPressed: busy ? null : onPressed,
              icon: glyph,
              label: Text(label),
            ),
    );
  }
}

IconData _liveIcon(String? type) => switch (type) {
  'substitution' => Icons.swap_horiz_rounded,
  'goal' => Icons.sports_soccer,
  'card' => Icons.style_outlined,
  'injury' => Icons.healing_outlined,
  'corner' => Icons.flag_outlined,
  'free_kick' => Icons.sports_outlined,
  'penalty' => Icons.adjust_outlined,
  'save' => Icons.pan_tool_outlined,
  'shot' => Icons.gps_fixed,
  'note' => Icons.notes,
  'kpi' => Icons.bolt_rounded,
  _ => Icons.timer_outlined,
};

/// The old app's quick-action grid: one button per kind of event with how
/// many we have so far, and a note.
class _LiveActionGrid extends StatelessWidget {
  const _LiveActionGrid({
    this.columns,
    required this.view,
    required this.tally,
    required this.onKind,
    required this.onNote,
  });

  /// Buttons per row; by the width when not given.
  final int? columns;

  /// Min vy: the keys shown, null for all.
  final Set<String>? view;
  final Map<String, int> tally;
  final ValueChanged<LiveEventKind> onKind;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget button(
      String key,
      IconData icon,
      String label,
      VoidCallback tap,
      int? count,
    ) => Material(
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('live-action-$key'),
        borderRadius: BorderRadius.circular(14),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colors.onSecondaryContainer),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSecondaryContainer,
                ),
              ),
              if (count != null && count > 0)
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSecondaryContainer.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final columns = this.columns ?? (box.maxWidth >= 560 ? 5 : 3);
        final buttons = [
          for (final kind in liveEventKinds)
            if (shownInView(view, kind.type))
              button(
                kind.type,
                _liveIcon(kind.type),
                kind.label,
                () => onKind(kind),
                tally[kind.type],
              ),
          if (shownInView(view, noteKey))
            button('note', _liveIcon('note'), 'Anteckning', onNote, null),
        ];
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.35,
          children: buttons,
        );
      },
    );
  }
}

/// Who is on the pitch now and who is on the bench.
class _OnPitchCard extends StatelessWidget {
  const _OnPitchCard({
    required this.onPitch,
    required this.bench,
    required this.name,
    required this.numbers,
  });
  final List<String> onPitch, bench;
  final String Function(String?) name;
  final Map<String, int> numbers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chip(String id, {required bool playing}) => Chip(
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(
        backgroundColor: playing
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        foregroundColor: playing
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        child: Text(
          '${numbers[id] ?? '–'}',
          style: const TextStyle(fontSize: 11),
        ),
      ),
      label: Text(name(id).split(' ').first),
    );
    return Card(
      key: const Key('live-on-pitch'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'På planen (${onPitch.length})',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final id in onPitch) chip(id, playing: true)],
            ),
            if (bench.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Bänken (${bench.length})',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final id in bench) chip(id, playing: false)],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The substitution plan from Förberedelse, ticked off as the substitutions
/// are made.
class _LivePlanCard extends StatelessWidget {
  const _LivePlanCard({
    required this.plan,
    required this.done,
    required this.name,
    this.onMake,
  });
  final List<PlannedSubstitution> plan;
  final Set<String> done;
  final String Function(String?) name;
  final ValueChanged<PlannedSubstitution>? onMake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('live-plan'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bytesplan (${done.length}/${plan.length})',
              style: theme.textTheme.titleSmall,
            ),
            for (final sub in plan)
              CheckboxListTile(
                key: Key('live-plan-${sub.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: done.contains(sub.id),
                onChanged: done.contains(sub.id) || onMake == null
                    ? null
                    : (_) => onMake!(sub),
                title: Text(
                  '${sub.minute == null ? '' : "${sub.minute}′ "}'
                  '${name(sub.outId)} ut · ${name(sub.inId)} in',
                  style: done.contains(sub.id)
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : null,
                ),
                subtitle: sub.note.isEmpty ? null : Text(sub.note),
              ),
          ],
        ),
      ),
    );
  }
}

/// Everything registered, latest first; tap to correct or remove it.
class _LiveTimeline extends StatelessWidget {
  const _LiveTimeline({
    required this.facts,
    required this.name,
    required this.opponentName,
    this.onTap,
    this.onMove,
    this.title = 'Händelser',
    this.highlightId,
  });
  final List<Map<String, dynamic>> facts;
  final String Function(String?) name;
  final String opponentName, title;
  final ValueChanged<Map<String, dynamic>>? onTap;

  /// Moves a placed event on the pitch.
  final ValueChanged<Map<String, dynamic>>? onMove;

  /// The event to show and scroll to, as from its tooltip on the pitch.
  final String? highlightId;

  String _text(Map<String, dynamic> fact) =>
      _factText(fact, name, opponentName);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = activeFacts(facts).toList().reversed.toList();
    return Card(
      key: const Key('live-timeline'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Inget registrerat än.'),
              ),
            for (final fact in shown)
              _RevealIf(
                reveal: highlightId != null && fact['id'] == highlightId,
                child: ListTile(
                  key: Key('live-fact-${fact['id']}'),
                  dense: true,
                  selected: highlightId != null && fact['id'] == highlightId,
                  selectedTileColor: theme.colorScheme.primaryContainer,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: fact['side'] == 'opponent'
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.primaryContainer,
                    child: Icon(
                      _liveIcon(fact['fact_type'] as String?),
                      size: 16,
                    ),
                  ),
                  title: Text(_text(fact)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("${(fact['minute'] as num?)?.toInt() ?? 0}′"),
                      if (onMove != null && factLocation(fact) != null)
                        IconButton(
                          key: Key('live-fact-move-${fact['id']}'),
                          tooltip: 'Flytta på planen',
                          onPressed: () => onMove!(fact),
                          icon: const Icon(Icons.open_with),
                        ),
                    ],
                  ),
                  onTap:
                      onTap == null ||
                          const [
                            'period_end',
                            'half_time',
                            'full_time',
                            'score_adjustment',
                          ].contains(fact['fact_type'])
                      ? null
                      : () => onTap!(fact),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Scrolls its child into view when first shown with [reveal].
class _RevealIf extends StatefulWidget {
  const _RevealIf({required this.reveal, required this.child});
  final bool reveal;
  final Widget child;

  @override
  State<_RevealIf> createState() => _RevealIfState();
}

class _RevealIfState extends State<_RevealIf> {
  @override
  void initState() {
    super.initState();
    if (widget.reveal) _reveal();
  }

  @override
  void didUpdateWidget(_RevealIf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reveal && !oldWidget.reveal) _reveal();
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 250),
        ),
      );
    }
  });

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Beside the buttons on a tablet or desktop, in the toolbar's row: the
/// shot map or the events, and whose shots the map shows.
class _LiveSideControls extends StatelessWidget {
  const _LiveSideControls({
    required this.events,
    required this.side,
    required this.opponentName,
    required this.onEvents,
    required this.onSide,
  });
  final bool events;
  final String side, opponentName;
  final ValueChanged<bool> onEvents;
  final ValueChanged<String> onSide;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SegmentedButton<bool>(
        key: const Key('live-side-panel'),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.gps_fixed, size: 18),
            label: Text('Skottkarta'),
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.list_alt, size: 18),
            label: Text('Händelser'),
          ),
        ],
        selected: {events},
        onSelectionChanged: (value) => onEvents(value.first),
      ),
      if (!events) ...[
        const SizedBox(width: 12),
        _ShotSideDropdown(
          value: side,
          opponentName: opponentName,
          onChanged: onSide,
        ),
      ],
    ],
  );
}

/// Above the buttons: Min vy, and the team's own buttons for those who
/// prepare the match.
class _LiveToolbar extends StatelessWidget {
  const _LiveToolbar({
    required this.onMyView,
    this.onOwnButtons,
    this.onPitchMode,
    this.error,
    this.trailing,
    this.publicLabel,
    this.onPublicLive,
  });
  final VoidCallback onMyView;
  final VoidCallback? onOwnButtons, onPitchMode, onPublicLive;

  /// Whether the match is reported live on the team's page, to change it.
  final String? publicLabel;
  final String? error;

  /// At the row's end, as the shot map's choices beside the buttons.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(child: _buttons(context)),
        ?trailing,
      ],
    ),
  );

  Widget _buttons(BuildContext context) => Wrap(
    spacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton.icon(
        key: const Key('live-my-view'),
        onPressed: onMyView,
        icon: const Icon(Icons.tune, size: 18),
        label: const Text('Min vy'),
      ),
      if (onOwnButtons != null)
        TextButton.icon(
          key: const Key('live-own-buttons'),
          onPressed: onOwnButtons,
          icon: const Icon(Icons.add_box_outlined, size: 18),
          label: const Text('Egna knappar'),
        ),
      if (onPitchMode != null)
        TextButton.icon(
          key: const Key('live-layout-pitch'),
          onPressed: onPitchMode,
          icon: const Icon(Icons.sports_soccer, size: 18),
          label: const Text('Planläge'),
        ),
      if (onPublicLive != null)
        TextButton.icon(
          key: const Key('live-public'),
          onPressed: onPublicLive,
          icon: const Icon(Icons.podcasts, size: 18),
          label: Text(publicLabel ?? 'Publikt'),
        ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

/// What an event was, in words, as the list and the pitch's tooltip say it.
String _factText(
  Map<String, dynamic> fact,
  String Function(String?) name,
  String opponentName,
) {
  final type = fact['fact_type'] as String?;
  final detail = (fact['detail'] as Map?) ?? const {};
  final player = fact['club_person_id'] as String?;
  final second = fact['secondary_club_person_id'] as String?;
  final them = fact['side'] == 'opponent';
  final kind = liveEventKind(type);
  String? result() {
    final value = detail[kind?.resultKey ?? 'result'];
    return kind?.results
        .where((r) => r.$1 == value)
        .map((r) => r.$2)
        .firstOrNull;
  }

  final who = them ? opponentName : (player == null ? null : name(player));
  return switch (type) {
    'goal' =>
      them
          ? 'Mål $opponentName'
          : 'Mål ${player == null ? '' : name(player)}'
                '${second == null ? '' : ' (assist ${name(second)})'}',
    'substitution' => '${name(player)} ut · ${name(second)} in',
    'note' => detail['text'] as String? ?? 'Anteckning',
    'period_end' => 'Periodslut',
    'half_time' => 'Halvtid',
    'full_time' => 'Slutsignal',
    'score_adjustment' => 'Ställningen ändrad',
    'kpi' => detail['label'] as String? ?? 'Räknare (matchmål)',
    _ => [
      kind?.label ?? type ?? '',
      ?who,
      ?result(),
      if (detail['comment'] case final String comment when comment.isNotEmpty)
        comment,
    ].join(' · '),
  };
}
