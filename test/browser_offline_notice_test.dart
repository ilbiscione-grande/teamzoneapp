import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/shared/widgets/browser_offline_notice.dart';

void main() {
  testWidgets('offline notice appears and clears when connection returns', (
    tester,
  ) async {
    final changes = StreamController<bool>(sync: true);
    addTearDown(changes.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        supportedLocales: const [Locale('sv'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: BrowserOfflineNotice(
            initiallyOnline: true,
            connectionChanges: changes.stream,
          ),
        ),
      ),
    );

    expect(
      find.text('Du är offline. Nytt innehåll kan inte hämtas.'),
      findsNothing,
    );
    changes.add(false);
    await tester.pump();
    expect(
      find.text('Du är offline. Nytt innehåll kan inte hämtas.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

    changes.add(true);
    await tester.pump();
    expect(
      find.text('Du är offline. Nytt innehåll kan inte hämtas.'),
      findsNothing,
    );
  });
}
