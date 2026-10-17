import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DraggableAssistantFab(
                    child: FloatingActionButton(
                      key: const Key('fab'),
                      onPressed: () {},
                      child: const Icon(Icons.assistant),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double bottomOf(WidgetTester tester) => tester
      .widget<Positioned>(
        find
            .ancestor(
              of: find.byKey(const Key('fab')),
              matching: find.byType(Positioned),
            )
            .first,
      )
      .bottom!;

  testWidgets('the assistant button moves along the right edge and stays', (
    tester,
  ) async {
    await mount(tester);
    expect(bottomOf(tester), 16);
    await tester.drag(find.byKey(const Key('fab')), const Offset(0, -200));
    await tester.pumpAndSettle();
    // Less the touch slop before a drag counts as one.
    expect(bottomOf(tester), inInclusiveRange(180, 216));
    // Never past the top.
    await tester.drag(find.byKey(const Key('fab')), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(bottomOf(tester), closeTo(600 - 64 - 16, 1));
    // The place is kept on the device.
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        'assistant_fab_position',
      ),
      closeTo(1, 0.01),
    );
    await mount(tester);
    expect(bottomOf(tester), closeTo(600 - 64 - 16, 1));
  });
}
