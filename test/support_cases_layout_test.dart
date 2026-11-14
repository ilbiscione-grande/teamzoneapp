import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/support/support_cases_layout.dart';

// Ärenden on the support page: the case queue and club verifications side
// by side on a wide screen, a tab each on a narrow one.

Widget _app(Size size) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    locale: const Locale('sv'),
    supportedLocales: const [Locale('sv')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SupportCasesLayout(
        cases: ListView(children: const [Text('Ärende A')]),
        verifications: ListView(children: const [Text('Verifiering B')]),
      ),
    ),
  ),
);

void main() {
  testWidgets('wide: both blocks side by side', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const Size(1400, 900)));
    expect(find.byKey(const ValueKey('support-cases-tabs')), findsNothing);
    expect(find.text('Ärende A'), findsOneWidget);
    expect(find.text('Verifiering B'), findsOneWidget);
    final cases = tester.getTopLeft(find.text('Ärende A'));
    final verification = tester.getTopLeft(find.text('Verifiering B'));
    expect(verification.dx, greaterThan(cases.dx + 400));
    expect((verification.dy - cases.dy).abs(), lessThan(4));
  });

  testWidgets('narrow: a tab each', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const Size(390, 800)));
    expect(find.byKey(const ValueKey('support-cases-tabs')), findsOneWidget);
    expect(find.text('Ärende A'), findsOneWidget);
    expect(find.text('Verifiering B'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('support-cases-tab-verifications')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verifiering B'), findsOneWidget);
  });
}
