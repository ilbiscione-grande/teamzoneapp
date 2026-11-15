/// A linked board's first frame in short form, and the small picture the
/// training session draws of it (miniatyr av länkad tavla, 2026-11-15). The
/// shapes follow Tacticsboard's board model: metres on a 105 x 68 pitch,
/// objects placed by their centre.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

const _pitchLength = 105.0, _pitchWidth = 68.0, _margin = 3.0;

class TrainingBoardPreview {
  const TrainingBoardPreview({
    required this.view,
    required this.objects,
    this.crop,
    this.teamColors = const {},
    this.numberColors = const {},
  });

  static TrainingBoardPreview? fromJson(Object? json) {
    if (json is! Map) return null;
    final teams = json['teams'] is Map ? json['teams'] as Map : const {};
    final crop = json['crop'];
    return TrainingBoardPreview(
      view: json['view'] as String? ?? 'full',
      crop: crop is Map
          ? Rect.fromLTWH(
              _num(crop['x']),
              _num(crop['y']),
              _num(crop['width']),
              _num(crop['height']),
            )
          : null,
      teamColors: {
        for (final side in const ['home', 'away'])
          side: _color(
            (teams[side] as Map?)?['color'],
            side == 'home' ? const Color(0xFF1D4ED8) : const Color(0xFFDC2626),
          ),
      },
      numberColors: {
        for (final side in const ['home', 'away'])
          side: _color((teams[side] as Map?)?['number_color'], Colors.white),
      },
      objects: [
        for (final item in (json['objects'] as List? ?? const []))
          if (item is Map) PreviewObject.fromJson(item),
      ],
    );
  }

  /// 'full', 'attack', 'defend' or 'empty' (no pitch lines).
  final String view;
  final Rect? crop;
  final Map<String, Color> teamColors, numberColors;
  final List<PreviewObject> objects;

  /// The part of the pitch shown, in metres: the crop, else the view; an
  /// empty view fits its objects, as an exercise is often drawn small.
  Rect get shown {
    final crop = this.crop;
    if (crop != null && crop.width > 0 && crop.height > 0) return crop;
    const half = _pitchLength / 2;
    switch (view) {
      case 'attack':
        return const Rect.fromLTWH(
          half - _margin,
          -_margin,
          half + _margin * 2,
          _pitchWidth + _margin * 2,
        );
      case 'defend':
        return const Rect.fromLTWH(
          -_margin,
          -_margin,
          half + _margin * 2,
          _pitchWidth + _margin * 2,
        );
      case 'empty':
        if (objects.isNotEmpty) {
          var box = objects.first.bounds;
          for (final item in objects.skip(1)) {
            box = box.expandToInclude(item.bounds);
          }
          box = box.inflate(4);
          // Never smaller than a small grid, so a lone cone is not huge.
          final grow = Size(
            math.max(0, 16 - box.width) / 2,
            math.max(0, 12 - box.height) / 2,
          );
          return Rect.fromLTRB(
            box.left - grow.width,
            box.top - grow.height,
            box.right + grow.width,
            box.bottom + grow.height,
          );
        }
    }
    return const Rect.fromLTWH(
      -_margin,
      -_margin,
      _pitchLength + _margin * 2,
      _pitchWidth + _margin * 2,
    );
  }
}

class PreviewObject {
  const PreviewObject({
    required this.type,
    required this.x,
    required this.y,
    this.side,
    this.number,
    this.color,
    this.attached = false,
    this.width = 0,
    this.height = 0,
    this.fill = 0,
    this.dashed = false,
    this.rotation = 0,
    this.scale = 1,
    this.points = const [],
    this.arrow,
  });

  factory PreviewObject.fromJson(Map json) => PreviewObject(
    type: json['type'] as String? ?? '',
    x: _num(json['x']),
    y: _num(json['y']),
    side: json['side'] as String?,
    number: (json['number'] as num?)?.toInt(),
    color: json['color'] is String ? _color(json['color'], Colors.white) : null,
    attached: json['attached'] == true,
    width: _num(json['width']),
    height: _num(json['height']),
    fill: _num(json['fill']).clamp(0, 1).toDouble(),
    dashed: json['dashed'] == true,
    rotation: _num(json['rotation']),
    scale: json['scale'] == null ? 1 : _num(json['scale']),
    points: [for (final p in (json['points'] as List? ?? const [])) _num(p)],
    arrow: json['arrow'] as String?,
  );

  final String type;
  final double x, y, width, height, fill, rotation, scale;
  final String? side, arrow;
  final int? number;
  final Color? color;
  final bool attached, dashed;
  final List<double> points;

  /// Roughly the room it takes, in metres.
  Rect get bounds => switch (type) {
    'rect' || 'ellipse' => Rect.fromCenter(
      center: Offset(x, y),
      width: width,
      height: height,
    ),
    'line' when points.length == 4 => Rect.fromPoints(
      Offset(x + points[0], y + points[1]),
      Offset(x + points[2], y + points[3]),
    ),
    _ => Rect.fromCenter(center: Offset(x, y), width: 2, height: 2),
  };
}

double _num(Object? value) => value is num ? value.toDouble() : 0;

Color _color(Object? value, Color fallback) {
  if (value is! String) return fallback;
  final hex = value.replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return fallback;
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

/// Draws the preview on a green pitch, the shown part fitted in the middle.
class TrainingBoardPreviewPainter extends CustomPainter {
  const TrainingBoardPreviewPainter(this.preview);
  final TrainingBoardPreview preview;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF2F7D46),
    );
    final shown = preview.shown;
    final scale = math.min(
      size.width / shown.width,
      size.height / shown.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - shown.width * scale) / 2,
      (size.height - shown.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-shown.left, -shown.top);
    // Lines a set width on screen, whatever the scale.
    final px = 1 / scale;
    if (preview.view != 'empty') _pitch(canvas, px);
    for (final item in preview.objects) {
      switch (item.type) {
        case 'rect' || 'ellipse':
          _shape(canvas, item, px);
        case 'line':
          _line(canvas, item, px);
        case 'cone' || 'pole' || 'mannequin' || 'goal':
          _equipment(canvas, item, px);
      }
    }
    // Players and the ball on top, as on the board.
    for (final item in preview.objects) {
      if (item.type == 'player') _player(canvas, item, px);
      if (item.type == 'ball' && !item.attached) {
        canvas.drawCircle(
          Offset(item.x, item.y),
          .7,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          Offset(item.x, item.y),
          .7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = px
            ..color = const Color(0xFF111827),
        );
      }
    }
    canvas.restore();
  }

  void _pitch(Canvas canvas, double px) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * px
      ..color = Colors.white.withValues(alpha: .85);
    const box = (depth: 16.5, width: 40.32), six = (depth: 5.5, width: 18.32);
    canvas.drawRect(const Rect.fromLTWH(0, 0, _pitchLength, _pitchWidth), line);
    canvas.drawLine(
      const Offset(_pitchLength / 2, 0),
      const Offset(_pitchLength / 2, _pitchWidth),
      line,
    );
    canvas.drawCircle(
      const Offset(_pitchLength / 2, _pitchWidth / 2),
      9.15,
      line,
    );
    for (final (depth, width) in [
      (box.depth, box.width),
      (six.depth, six.width),
    ]) {
      final top = (_pitchWidth - width) / 2;
      canvas.drawRect(Rect.fromLTWH(0, top, depth, width), line);
      canvas.drawRect(
        Rect.fromLTWH(_pitchLength - depth, top, depth, width),
        line,
      );
    }
  }

  void _rotated(Canvas canvas, PreviewObject item, void Function() draw) {
    canvas.save();
    canvas.translate(item.x, item.y);
    canvas.rotate(item.rotation * math.pi / 180);
    draw();
    canvas.restore();
  }

  void _shape(Canvas canvas, PreviewObject item, double px) {
    final color = item.color ?? Colors.white;
    _rotated(canvas, item, () {
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: item.width,
        height: item.height,
      );
      final path = item.type == 'ellipse'
          ? (Path()..addOval(rect))
          : (Path()..addRect(rect));
      if (item.fill > 0) {
        canvas.drawPath(
          path,
          Paint()..color = color.withValues(alpha: item.fill),
        );
      }
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * px
        ..color = color;
      canvas.drawPath(
        item.dashed ? _dashed(path, 6 * px, 4 * px) : path,
        stroke,
      );
    });
  }

  void _line(Canvas canvas, PreviewObject item, double px) {
    if (item.points.length != 4) return;
    final from = Offset(item.x + item.points[0], item.y + item.points[1]);
    final to = Offset(item.x + item.points[2], item.y + item.points[3]);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * px
      ..strokeCap = StrokeCap.round
      ..color = item.color ?? Colors.white;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
    canvas.drawPath(item.dashed ? _dashed(path, 6 * px, 4 * px) : path, paint);
    if (item.arrow == 'end' || item.arrow == 'both') {
      _head(canvas, from, to, paint, px);
    }
    if (item.arrow == 'both') _head(canvas, to, from, paint, px);
  }

  void _head(Canvas canvas, Offset from, Offset to, Paint paint, double px) {
    final angle = (to - from).direction;
    final length = 8 * px;
    for (final turn in const [2.6, -2.6]) {
      canvas.drawLine(
        to,
        to + Offset.fromDirection(angle + turn, length),
        paint,
      );
    }
  }

  void _equipment(Canvas canvas, PreviewObject item, double px) {
    final color = item.color ?? Colors.white;
    _rotated(canvas, item, () {
      switch (item.type) {
        case 'goal':
          // A goal's mouth, 7.32 m wide, two deep, open towards the play.
          final width = 7.32 * item.scale, depth = 2 * item.scale;
          canvas.drawPath(
            Path()
              ..moveTo(-depth / 2, -width / 2)
              ..lineTo(depth / 2, -width / 2)
              ..lineTo(depth / 2, width / 2)
              ..lineTo(-depth / 2, width / 2),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * px
              ..color = color,
          );
        case 'cone':
          final r = .6 * item.scale;
          canvas.drawPath(
            Path()
              ..moveTo(0, -r)
              ..lineTo(r, r)
              ..lineTo(-r, r)
              ..close(),
            Paint()..color = color,
          );
        default:
          canvas.drawCircle(
            Offset.zero,
            .5 * item.scale,
            Paint()..color = color,
          );
      }
    });
  }

  void _player(Canvas canvas, PreviewObject item, double px) {
    final side = item.side ?? 'home';
    final fill = item.color ?? preview.teamColors[side] ?? Colors.blue;
    const r = 1.4;
    final at = Offset(item.x, item.y);
    canvas.drawCircle(at, r, Paint()..color = fill);
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = Colors.black.withValues(alpha: .35),
    );
    final number = item.number;
    if (number == null) return;
    final text = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: preview.numberColors[side] ?? Colors.white,
          fontSize: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, at - Offset(text.width / 2, text.height / 2));
  }

  static Path _dashed(Path path, double dash, double gap) {
    final out = Path();
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        out.addPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          Offset.zero,
        );
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(TrainingBoardPreviewPainter old) => old.preview != preview;
}
