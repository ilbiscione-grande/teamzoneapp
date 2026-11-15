import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/training/training_models.dart';

void main() {
  final json = {
    'source': 'mine',
    'ref': '00000000-0000-4000-8000-000000000001',
    'board_id': 'board-1',
    'name': 'Press i par',
    'preview': {
      'view': 'empty',
      'crop': null,
      'teams': {
        'home': {'color': '#1d4ed8', 'number_color': '#ffffff'},
        'away': {'color': '#dc2626', 'number_color': '#000000'},
      },
      'objects': [
        {'type': 'player', 'x': 10, 'y': 20, 'side': 'home', 'number': 7},
        {'type': 'ball', 'x': 11, 'y': 21},
        {
          'type': 'rect',
          'x': 15,
          'y': 25,
          'width': 24,
          'height': 18,
          'color': '#facc15',
          'fill': 0.18,
          'dashed': true,
        },
        {
          'type': 'line',
          'x': 5,
          'y': 5,
          'points': [0, 0, 6, 2],
          'arrow': 'end',
          'color': '#ffffff',
        },
        {'type': 'goal', 'x': 30, 'y': 25, 'rotation': 90, 'scale': 1},
        {'type': 'cone', 'x': 2, 'y': 30, 'color': '#f97316'},
      ],
    },
  };

  test('a linked board reads its preview but never sends it back', () {
    final link = TrainingBoardLink.fromJson(json)!;
    final preview = link.preview!;
    expect(preview.objects.map((o) => o.type), [
      'player',
      'ball',
      'rect',
      'line',
      'goal',
      'cone',
    ]);
    expect(preview.teamColors['home'], const Color(0xFF1D4ED8));
    expect(preview.numberColors['away'], const Color(0xFF000000));
    expect(link.toJson().containsKey('preview'), isFalse);
    expect(link.missing, isFalse);
    // A saved link whose project is gone says so, and never sends it back.
    final gone = TrainingBoardLink.fromJson({
      ...json,
      'preview': null,
      'missing': true,
    })!;
    expect(gone.missing, isTrue);
    expect(gone.toJson().containsKey('missing'), isFalse);
    // Without a preview (linked since the last save) the link still reads.
    expect(
      TrainingBoardLink.fromJson({...json, 'preview': null})?.preview,
      isNull,
    );
  });

  test('an empty view fits its objects, a pitch view shows the pitch', () {
    final empty = TrainingBoardLink.fromJson(json)!.preview!;
    final shown = empty.shown;
    // The zone (3..27 x 16..34) and the cone at (2, 30) are inside.
    expect(shown.contains(const Offset(3, 16)), isTrue);
    expect(shown.contains(const Offset(27, 34)), isTrue);
    expect(shown.contains(const Offset(2, 30)), isTrue);
    expect(shown.width, lessThan(60));

    final full = TrainingBoardPreview.fromJson({'view': 'full'})!;
    expect(full.shown, const Rect.fromLTWH(-3, -3, 111, 74));
    final attack = TrainingBoardPreview.fromJson({'view': 'attack'})!;
    expect(attack.shown.left, 49.5);
    final cropped = TrainingBoardPreview.fromJson({
      'view': 'full',
      'crop': {'x': 10, 'y': 10, 'width': 20, 'height': 15},
    })!;
    expect(cropped.shown, const Rect.fromLTWH(10, 10, 20, 15));
  });

  testWidgets('the preview paints without errors', (tester) async {
    final preview = TrainingBoardLink.fromJson(json)!.preview!;
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 320,
          height: 200,
          child: CustomPaint(painter: TrainingBoardPreviewPainter(preview)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
