/// A Tacticsboard board's first frame as a small picture: the pitch lines
/// and the players and ball, in shares (0–1) of the picture. The same
/// reading as the shared link's chat picture (webtools/lib/tactics/preview.ts).
class TacticsBoardPreview {
  const TacticsBoardPreview({
    required this.lines,
    required this.dots,
    required this.aspect,
  });

  static const _length = 105.0, _width = 68.0, _margin = 3.0;
  static const _boxDepth = 16.5, _boxWidth = 40.32;
  static const _sixDepth = 5.5, _sixWidth = 18.32, _circle = 9.15;
  static const _teamColors = {
    'home': ('#1d4ed8', '#ffffff'),
    'away': ('#dc2626', '#ffffff'),
  };

  /// From the plan's `preview`: the board's view, teams and first frame's objects.
  factory TacticsBoardPreview.fromJson(Map<String, dynamic> json) {
    final view = json['view'] as String?;
    final (x, width) = switch (view) {
      'attack' => (_length / 2 - _margin, _length / 2 + _margin * 2),
      'defend' => (-_margin, _length / 2 + _margin * 2),
      _ => (-_margin, _length + _margin * 2),
    };
    const y = -_margin, height = _width + _margin * 2;
    PreviewBox box(
      double left,
      double top,
      double boxWidth,
      double boxHeight, {
      bool round = false,
    }) => PreviewBox(
      left: (left - x) / width,
      top: (top - y) / height,
      width: boxWidth / width,
      height: boxHeight / height,
      round: round,
    );
    final lines = view == 'empty'
        ? const <PreviewBox>[]
        : [
            box(0, 0, _length, _width),
            box(_length / 2, 0, 0, _width),
            box(
              _length / 2 - _circle,
              _width / 2 - _circle,
              _circle * 2,
              _circle * 2,
              round: true,
            ),
            box(0, (_width - _boxWidth) / 2, _boxDepth, _boxWidth),
            box(
              _length - _boxDepth,
              (_width - _boxWidth) / 2,
              _boxDepth,
              _boxWidth,
            ),
            box(0, (_width - _sixWidth) / 2, _sixDepth, _sixWidth),
            box(
              _length - _sixDepth,
              (_width - _sixWidth) / 2,
              _sixDepth,
              _sixWidth,
            ),
          ];
    final teams = json['teams'] is Map ? json['teams'] as Map : const {};
    final dots = <PreviewDot>[];
    for (final item in json['objects'] is List ? json['objects'] as List : []) {
      if (item is! Map || item['hidden'] == true) continue;
      final at = (item['x'], item['y']);
      if (at case (final num pointX, final num pointY)) {
        if (pointX < x ||
            pointX > x + width ||
            pointY < y ||
            pointY > y + height) {
          continue;
        }
        final left = (pointX - x) / width, top = (pointY - y) / height;
        if (item['type'] == 'player') {
          final side = item['side'] == 'away' ? 'away' : 'home';
          final team = teams[side] is Map ? teams[side] as Map : const {};
          final number = item['number'];
          dots.add(
            PreviewDot(
              left: left,
              top: top,
              fill: _color(
                item['color'] ?? team['color'],
                _teamColors[side]!.$1,
              ),
              ink: _color(team['numberColor'], _teamColors[side]!.$2),
              label: number is num ? '${number.toInt()}' : '',
            ),
          );
        } else if (item['type'] == 'ball' && item['attachedTo'] == null) {
          dots.add(
            PreviewDot(
              left: left,
              top: top,
              fill: 0xffffffff,
              ink: 0xff111827,
              label: '',
              ball: true,
            ),
          );
        }
      }
    }
    return TacticsBoardPreview(
      lines: lines,
      dots: dots,
      aspect: width / height,
    );
  }

  final List<PreviewBox> lines;
  final List<PreviewDot> dots;

  /// The view's width over its height.
  final double aspect;

  /// A colour written #rgb or #rrggbb, as ARGB; else the fallback.
  static int _color(Object? value, String fallback) =>
      _hex(value) ?? _hex(fallback)!;

  static int? _hex(Object? value) {
    if (value is! String) return null;
    var hex = value.replaceFirst('#', '');
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    final parsed = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    return parsed == null ? null : 0xff000000 | parsed;
  }
}

/// A pitch line in shares of the picture; width 0 is the halfway line.
class PreviewBox {
  const PreviewBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.round = false,
  });
  final double left, top, width, height;
  final bool round;
}

/// A player (with their number) or the ball, at its place in the picture.
class PreviewDot {
  const PreviewDot({
    required this.left,
    required this.top,
    required this.fill,
    required this.ink,
    required this.label,
    this.ball = false,
  });
  final double left, top;
  final int fill, ink;
  final String label;
  final bool ball;
}
