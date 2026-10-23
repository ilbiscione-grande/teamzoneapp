part of '../../app/teamzone_app.dart';

/// A mark on the location pitch.
typedef _PitchMark = ({double x, double y, Color color, bool filled});

/// The pitch lying down, our goal to the left and our attack to the right,
/// as the old app marked where things happened: tap to place, with marks
/// for what is already placed. x runs from our goal line to theirs, y from
/// the left touchline.
class _LocationPitch extends StatelessWidget {
  const _LocationPitch({this.marks = const [], this.onTap});
  final List<_PitchMark> marks;
  final ValueChanged<(double, double)>? onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 105 / 68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        // The standing pitch turned a quarter: its bottom (our goal) left.
        child: RotatedBox(
          quarterTurns: 1,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              final dot = (w / 16).clamp(10.0, 18.0);
              return GestureDetector(
                key: const Key('location-pitch'),
                behavior: HitTestBehavior.opaque,
                onTapUp: onTap == null
                    ? null
                    : (details) => onTap!((
                        (1 - details.localPosition.dy / h).clamp(0.0, 1.0),
                        (details.localPosition.dx / w).clamp(0.0, 1.0),
                      )),
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
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: mark.filled
                                ? mark.color
                                : Colors.transparent,
                            border: Border.all(
                              color: mark.filled ? Colors.white : mark.color,
                              width: 2.5,
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
                child: const Text('Rensa'),
              ),
          ],
        ),
        _LocationPitch(
          marks: [
            if (place != null)
              (x: place.$1, y: place.$2, color: colors.primary, filled: true),
          ],
          onTap: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Text('Vårt mål', style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              Text('Anfall →', style: Theme.of(context).textTheme.labelSmall),
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
    title: const Text('Var avslutades det?'),
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
        child: const Text('Hoppa över'),
      ),
      FilledButton(
        key: const Key('goal-location-save'),
        onPressed: _place == null
            ? null
            : () => Navigator.pop(context, (_place, true)),
        child: const Text('Spara'),
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
  });
  final List<Map<String, dynamic>> facts;
  final String opponentName;

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
    final shown = points
        .where((p) => _side == 'all' || p.side == _side)
        .toList();
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
            Row(
              children: [
                Expanded(
                  child: Text('Skottkarta', style: theme.textTheme.titleSmall),
                ),
                SegmentedButton<String>(
                  key: const Key('shot-map-side'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    const ButtonSegment(value: 'us', label: Text('Vi')),
                    ButtonSegment(
                      value: 'opponent',
                      label: Text(
                        widget.opponentName.length > 10
                            ? 'De'
                            : widget.opponentName,
                      ),
                    ),
                    const ButtonSegment(value: 'all', label: Text('Alla')),
                  ],
                  selected: {_side},
                  onSelectionChanged: (value) =>
                      setState(() => _side = value.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LocationPitch(
              marks: [
                for (final p in shown)
                  (
                    x: p.x,
                    y: p.y,
                    color: color(p),
                    filled: const ['goal', 'on_target'].contains(p.outcome),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              points.isEmpty
                  ? 'Markera avslut och mål på planen så syns de här.'
                  : '${shown.length} avslut · ${count('goal')} mål · '
                        '${count('on_target')} på mål · ${count('missed') + count('woodwork')} utanför · '
                        '${count('blocked')} blockerade',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
