import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/localization/app_strings.dart';

void main() {
  testWidgets('context roles have distinct localized labels', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        supportedLocales: const [Locale('sv'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final strings = AppStrings.of(context);
    expect(strings.domainValue('leader'), 'Ledare');
    expect(strings.domainValue('player'), 'Spelare');
    expect(strings.domainValue('guardian'), 'Vårdnadshavare');
    expect(strings.domainValue('club_functionary'), 'Klubbfunktionär');
  });
}
