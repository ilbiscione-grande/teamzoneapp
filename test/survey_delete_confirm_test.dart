import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/team_development/survey_delete_confirm.dart';

void main() {
  Future<List<bool>> start(WidgetTester tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        supportedLocales: const [Locale('sv')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await confirmSurveyAnswersDeletion(
                context,
                title: 'Ta bort svaret?',
                message: 'Adas svar tas bort.',
              ),
            ),
            child: const Text('start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('answers are deleted only after two confirmations', (
    tester,
  ) async {
    final results = await start(tester);
    expect(find.text('Adas svar tas bort.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('survey-delete-continue')));
    await tester.pumpAndSettle();
    expect(results, isEmpty, reason: 'the first yes is not enough');
    expect(
      find.text(
        'Är du säker på att du vill ta bort svaren för gott? Det går inte att återställa.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('survey-delete-confirm')));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('the second warning can be declined', (tester) async {
    final results = await start(tester);
    await tester.tap(find.byKey(const Key('survey-delete-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('survey-delete-keep')));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('the second warning can be dismissed', (tester) async {
    final results = await start(tester);
    await tester.tap(find.byKey(const Key('survey-delete-continue')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('the first dialog can be cancelled', (tester) async {
    final results = await start(tester);
    await tester.tap(find.text('Avbryt'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(find.byKey(const Key('survey-delete-second')), findsNothing);
  });
}
