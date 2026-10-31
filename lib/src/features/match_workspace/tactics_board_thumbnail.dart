import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tactics_board_preview.dart';

/// A board's first frame, small: a green pitch with its players and ball.
/// Without a preview (a board since removed) a plain pitch icon.
class TacticsBoardThumbnail extends StatelessWidget {
  const TacticsBoardThumbnail({super.key, this.preview, this.width = 64});
  final TacticsBoardPreview? preview;
  final double width;

  @override
  Widget build(BuildContext context) {
    final preview = this.preview;
    final height = width / (preview?.aspect ?? 1.5);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: preview == null
            ? const ColoredBox(
                color: _grass,
                child: Icon(Icons.sports_soccer, color: Colors.white, size: 20),
              )
            : CustomPaint(painter: _ThumbnailPainter(preview)),
      ),
    );
  }
}

const _grass = Color(0xff2f7d46);

class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter(this.preview);
  final TacticsBoardPreview preview;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _grass);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final box in preview.lines) {
      final rect = Rect.fromLTWH(
        box.left * size.width,
        box.top * size.height,
        box.width * size.width,
        box.height * size.height,
      );
      if (box.round) {
        canvas.drawOval(rect, line);
      } else if (box.width == 0) {
        canvas.drawLine(rect.topLeft, rect.bottomLeft, line);
      } else {
        canvas.drawRect(rect, line);
      }
    }
    // Players about as large as on the board, never smaller than a dot.
    final radius = math.max(2.5, size.width / 34);
    for (final dot in preview.dots) {
      final at = Offset(dot.left * size.width, dot.top * size.height);
      final r = dot.ball ? radius * .6 : radius;
      canvas.drawCircle(at, r, Paint()..color = Color(dot.fill));
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = dot.ball ? const Color(0xff111827) : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
    }
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) => old.preview != preview;
}
