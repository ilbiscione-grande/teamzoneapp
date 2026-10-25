part of '../../app/teamzone_app.dart';

/// A mark on the location pitch.
typedef _PitchMark = ({
  double x,
  double y,
  Color color,
  bool filled,

  /// The event the mark stands for, so a tap on it can explain it.
  String? id,
});

/// The pitch lying down, our goal to the left and our attack to the right,
/// as the old app marked where things happened: tap to place, with marks
/// for what is already placed. x runs from our goal line to theirs, y from
/// the left touchline. A mark with an event can be tapped for [tooltip],
/// shown upright by it.
class _LocationPitch extends StatelessWidget {
  const _LocationPitch({
    this.marks = const [],
    this.onTap,
    this.onTapMark,
    this.selectedId,
    this.tooltip,
  });
  final List<_PitchMark> marks;
  final ValueChanged<(double, double)>? onTap;
  final ValueChanged<String?>? onTapMark;
  final String? selectedId;
  final Widget? tooltip;

  @override
  Widget build(BuildContext context) {
    final selected = marks
        .where((m) => m.id != null && m.id == selectedId)
        .firstOrNull;
    return AspectRatio(
      aspectRatio: 105 / 68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LayoutBuilder(
          builder: (context, outer) => Stack(
            children: [
              // The standing pitch turned a quarter: its bottom (our goal)
              // left.
              Positioned.fill(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final w = box.maxWidth, h = box.maxHeight;
                      final dot = (w / 16).clamp(10.0, 18.0);
                      return GestureDetector(
                        key: const Key('location-pitch'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: onTap != null
                            ? (details) => onTap!((
                                (1 - details.localPosition.dy / h).clamp(
                                  0.0,
                                  1.0,
                                ),
                                (details.localPosition.dx / w).clamp(0.0, 1.0),
                              ))
                            : onTapMark == null
                            ? null
                            : (_) => onTapMark!(null),
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: CustomPaint(painter: _PitchPainter()),
                            ),
                            for (final mark in marks)
                              Positioned(
                                left: mark.y * w - dot / 2,
                                top: (1 - mark.x) * h - dot / 2,
                                width: dot,
                                height: dot,
                                child: GestureDetector(
                                  key: mark.id == null
                                      ? null
                                      : Key('pitch-mark-${mark.id}'),
                                  onTap: mark.id == null || onTapMark == null
                                      ? null
                                      : () => onTapMark!(mark.id),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: mark.filled
                                          ? mark.color
                                          : Colors.transparent,
                                      border: Border.all(
                                        color:
                                            mark.id != null &&
                                                mark.id == selectedId
                                            ? Colors.white
                                            : mark.filled
                                            ? Colors.white
                                            : mark.color,
                                        width:
                                            mark.id != null &&
                                                mark.id == selectedId
                                            ? 3.5
                                            : 2.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (selected != null && tooltip != null)
                _tooltipAt(
                  outer.biggest,
                  Offset(
                    selected.x * outer.maxWidth,
                    selected.y * outer.maxHeight,
                  ),
                  tooltip!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [tooltip] by a point on a pitch of [size]: under it, or over it near the
/// bottom, kept inside the pitch.
Widget _tooltipAt(Size size, Offset point, Widget tooltip) {
  final width = size.width < 300 ? size.width - 16 : 260.0;
  final below = point.dy < size.height - 70;
  return Positioned(
    left: (point.dx - width / 2).clamp(8.0, size.width - width - 8),
    top: below ? point.dy + 16 : null,
    bottom: below ? null : size.height - point.dy + 16,
    width: width,
    child: tooltip,
  );
}

/// What happened, in a small box by the event on the pitch, with a › to
/// show that a tap takes you to it in the event list.
class _FactTooltip extends StatelessWidget {
  const _FactTooltip({
    required this.fact,
    required this.text,
    required this.onTap,
  });
  final Map<String, dynamic> fact;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = TextStyle(color: colors.onInverseSurface, fontSize: 13);
    return Material(
      key: Key('fact-tooltip-${fact['id']}'),
      color: colors.inverseSurface,
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Icon(
                _liveIcon(fact['fact_type'] as String?),
                size: 16,
                color: colors.onInverseSurface,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "${(fact['minute'] as num?)?.toInt() ?? 0}′",
                style: style.copyWith(fontWeight: FontWeight.w700),
              ),
              Icon(Icons.chevron_right, color: colors.onInverseSurface),
            ],
          ),
        ),
      ),
    );
  }
}

/// Places one event: tap where it happened, tap again to move, or clear.
class _LocationField extends StatelessWidget {
  const _LocationField({required this.value, required this.onChanged});
  final (double, double)? value;
  final ValueChanged<(double, double)?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final place = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                place == null
                    ? 'Var på planen? Tryck för att markera (frivilligt)'
                    : 'Markerad på planen',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (place != null)
              TextButton(
                key: const Key('location-clear'),
                onPressed: () => onChanged(null),
                child: Text(AppStrings.of(context).feature('Rensa')),
              ),
          ],
        ),
        _LocationPitch(
          marks: [
            if (place != null)
              (
                x: place.$1,
                y: place.$2,
                color: colors.primary,
                filled: true,
                id: null,
              ),
          ],
          onTap: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Text(
                AppStrings.of(context).feature('Vårt mål'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                AppStrings.of(context).feature('Anfall →'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where a goal was scored, asked after the scorer; skipping keeps none.
class _GoalLocationDialog extends StatefulWidget {
  const _GoalLocationDialog({this.initial});
  final (double, double)? initial;

  @override
  State<_GoalLocationDialog> createState() => _GoalLocationDialogState();
}

class _GoalLocationDialogState extends State<_GoalLocationDialog> {
  late (double, double)? _place = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(AppStrings.of(context).feature('Var avslutades det?')),
    content: SizedBox(
      width: 420,
      child: _LocationField(
        value: _place,
        onChanged: (place) => setState(() => _place = place),
      ),
    ),
    actions: [
      TextButton(
        key: const Key('goal-location-skip'),
        onPressed: () => Navigator.pop(context, (null, true)),
        child: Text(AppStrings.of(context).feature('Hoppa över')),
      ),
      FilledButton(
        key: const Key('goal-location-save'),
        onPressed: _place == null
            ? null
            : () => Navigator.pop(context, (_place, true)),
        child: Text(AppStrings.of(context).feature('Spara')),
      ),
    ],
  );
}

/// The shot map: every placed shot and goal, ours or theirs, filled for a
/// goal or on target and hollow when it missed.
class _ShotMapCard extends StatefulWidget {
  const _ShotMapCard({
    required this.facts,
    required this.opponentName,
    this.showEmpty = false,
    this.side,
    this.selectedId,
    this.onTapMark,
    this.tooltipFor,
  });
  final List<Map<String, dynamic>> facts;
  final String opponentName;

  /// The event whose tooltip shows, tapping a mark to choose it (null to
  /// close), and the tooltip for an event.
  final String? selectedId;
  final ValueChanged<String?>? onTapMark;
  final Widget? Function(String id)? tooltipFor;

  /// Whose shots, chosen outside the card (beside the buttons, where the
  /// panel's row holds the choice); the card then has no header.
  final String? side;

  /// Shown before any shot is placed, as beside the buttons on a wide
  /// screen.
  final bool showEmpty;

  @override
  State<_ShotMapCard> createState() => _ShotMapCardState();
}

class _ShotMapCardState extends State<_ShotMapCard> {
  String _side = 'us';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = shotPoints(widget.facts);
    if (points.isEmpty && !widget.showEmpty) return const SizedBox.shrink();
    final side = widget.side ?? _side;
    final shown = points.where((p) => side == 'all' || p.side == side).toList();
    Color color(ShotPoint p) => p.outcome == 'goal'
        ? const Color(0xFFF2B705)
        : p.side == 'us'
        ? theme.colorScheme.primary
        : const Color(0xFFD84343);
    int count(String outcome) =>
        shown.where((p) => p.outcome == outcome).length;
    return Card(
      key: const Key('live-shot-map'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.side == null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.of(context).feature('Skottkarta'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  _ShotSideDropdown(
                    value: _side,
                    opponentName: widget.opponentName,
                    onChanged: (value) => setState(() => _side = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            _LocationPitch(
              marks: [
                for (final p in shown)
                  (
                    x: p.x,
                    y: p.y,
                    color: color(p),
                    filled: const ['goal', 'on_target'].contains(p.outcome),
                    id: p.id,
                  ),
              ],
              onTapMark: widget.onTapMark,
              selectedId: widget.selectedId,
              tooltip: widget.selectedId == null
                  ? null
                  : widget.tooltipFor?.call(widget.selectedId!),
            ),
            const SizedBox(height: 6),
            Text(
              points.isEmpty
                  ? AppStrings.of(context).feature(
                      'Markera avslut och mål på planen så syns de här.',
                    )
                  : AppStrings.of(context).formatFeature(
                      '{shots} avslut · {goals} mål · {target} på mål · {missed} utanför · {blocked} blockerade',
                      {
                        'shots': shown.length,
                        'goals': count('goal'),
                        'target': count('on_target'),
                        'missed': count('missed') + count('woodwork'),
                        'blocked': count('blocked'),
                      },
                    ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Whose shots the map shows: ours, theirs or all.
class _ShotSideDropdown extends StatelessWidget {
  const _ShotSideDropdown({
    required this.value,
    required this.opponentName,
    required this.onChanged,
  });
  final String value, opponentName;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: DropdownButton<String>(
      isExpanded: true,
      key: const Key('shot-map-side'),
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem(
          value: 'us',
          child: Text(AppStrings.of(context).feature('Vi')),
        ),
        DropdownMenuItem(
          value: 'opponent',
          child: Text(opponentName, overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem(
          value: 'all',
          child: Text(AppStrings.of(context).feature('Alla')),
        ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
}
