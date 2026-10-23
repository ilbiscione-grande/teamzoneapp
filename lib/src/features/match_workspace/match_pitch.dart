part of '../../app/teamzone_app.dart';

/// One marker on the pitch: a formation slot and who plays there.
typedef _PitchSpot = ({FormationSlot slot, Offset place, LineupPlayer? player});

/// The line-up on a pitch standing up, the own goal at the bottom, as the
/// old app's starting XI board: tap a marker to choose its player, drag it
/// to move it. Read-only it shows who plays where.
class _LineupPitch extends StatelessWidget {
  const _LineupPitch({
    required this.spots,
    required this.edit,
    this.onTap,
    this.onMoved,
  });
  final List<_PitchSpot> spots;
  final bool edit;
  final ValueChanged<FormationSlot>? onTap;

  /// The slot moved to a place (x, y in pitch terms, 0..1).
  final void Function(FormationSlot slot, Offset place)? onMoved;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AspectRatio(
          aspectRatio: 68 / 105,
          child: LayoutBuilder(
            builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              final marker = (size.width / 7).clamp(34.0, 52.0);
              Offset toScreen(Offset place) =>
                  Offset(place.dy * size.width, (1 - place.dx) * size.height);
              Offset toPitch(Offset screen) => Offset(
                (1 - screen.dy / size.height).clamp(0.0, 1.0),
                (screen.dx / size.width).clamp(0.0, 1.0),
              );
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: const _PitchPainter()),
                    ),
                    for (final spot in spots)
                      Builder(
                        builder: (context) {
                          final center = toScreen(spot.place);
                          return Positioned(
                            left: center.dx - marker,
                            top: center.dy - marker / 2,
                            width: marker * 2,
                            child: GestureDetector(
                              key: Key('lineup-slot-${spot.slot.code}'),
                              onTap: edit ? () => onTap?.call(spot.slot) : null,
                              onPanUpdate: edit && spot.player != null
                                  ? (details) {
                                      final box =
                                          context.findRenderObject()
                                              as RenderBox?;
                                      final stack = box?.parent;
                                      if (stack is! RenderBox) return;
                                      final local = stack.globalToLocal(
                                        details.globalPosition,
                                      );
                                      onMoved?.call(spot.slot, toPitch(local));
                                    }
                                  : null,
                              child: _PlayerMarker(spot: spot, size: marker),
                            ),
                          );
                        },
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

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker({required this.spot, required this.size});
  final _PitchSpot spot;
  final double size;

  @override
  Widget build(BuildContext context) {
    final player = spot.player;
    final colors = Theme.of(context).colorScheme;
    final keeper = spot.slot.group == 'goalkeeper';
    final initials = player == null
        ? ''
        : player.name
              .split(' ')
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part[0])
              .join();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: player == null
                ? Colors.white.withValues(alpha: 0.18)
                : keeper
                ? const Color(0xFFF2B705)
                : colors.primary,
            border: Border.all(
              color: Colors.white,
              width: player == null ? 1.5 : 2.5,
            ),
            boxShadow: player == null
                ? null
                : const [BoxShadow(blurRadius: 4, color: Colors.black38)],
          ),
          child: player == null
              ? Text(
                  spot.slot.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.3,
                  ),
                )
              : Text(
                  player.number?.toString() ?? initials,
                  style: TextStyle(
                    color: keeper ? Colors.black87 : colors.onPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.38,
                  ),
                ),
        ),
        const SizedBox(height: 2),
        Text(
          player?.name.split(' ').first ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 3, color: Colors.black)],
          ),
        ),
      ],
    );
  }
}

/// A football pitch standing up: stripes, lines, boxes and the centre.
class _PitchPainter extends CustomPainter {
  const _PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stripe = h / 10;
    for (var i = 0; i < 10; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * stripe, w, stripe),
        Paint()
          ..color = i.isEven
              ? const Color(0xFF3E8E4E)
              : const Color(0xFF378245),
      );
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final m = w * 0.04;
    canvas.drawRect(Rect.fromLTRB(m, m, w - m, h - m), line);
    canvas.drawLine(Offset(m, h / 2), Offset(w - m, h / 2), line);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.14, line);
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      2.5,
      line..style = PaintingStyle.fill,
    );
    line.style = PaintingStyle.stroke;
    for (final top in [true, false]) {
      final y = top ? m : h - m;
      final dir = top ? 1.0 : -1.0;
      final box = w * 0.6, small = w * 0.28;
      canvas.drawRect(
        Rect.fromPoints(
          Offset((w - box) / 2, y),
          Offset((w + box) / 2, y + dir * h * 0.15),
        ),
        line,
      );
      canvas.drawRect(
        Rect.fromPoints(
          Offset((w - small) / 2, y),
          Offset((w + small) / 2, y + dir * h * 0.055),
        ),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_PitchPainter oldDelegate) => false;
}
