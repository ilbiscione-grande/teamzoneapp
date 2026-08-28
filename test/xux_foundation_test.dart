import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/shared/layout/app_breakpoints.dart';
import 'package:teamzone_app/src/shared/theme/app_theme.dart';
import 'package:teamzone_app/src/shared/widgets/app_states.dart';

void main() {
  test('theme has stable light/dark seeds and padded touch targets', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
    expect(
      AppTheme.light().materialTapTargetSize,
      MaterialTapTargetSize.padded,
    );
    expect(AppSizes.minimumTouchTarget, greaterThanOrEqualTo(48));
  });

  test('phone tablet and desktop boundaries remain explicit', () {
    expect(AppBreakpoints.classify(599), AppWindowClass.phone);
    expect(AppBreakpoints.classify(600), AppWindowClass.tablet);
    expect(AppBreakpoints.classify(1024), AppWindowClass.desktop);
  });

  testWidgets('shared loading state exposes a live semantic label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppLoadingIndicator(label: 'Laddar kalender')),
    );
    expect(find.bySemanticsLabel('Laddar kalender'), findsOneWidget);
  });

  testWidgets('shared state card preserves action and readable content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppStateCard(
          icon: Icons.inbox_outlined,
          title: 'Tomt',
          message: 'Inget att visa',
          action: TextButton(onPressed: null, child: Text('Försök igen')),
        ),
      ),
    );
    expect(find.text('Tomt'), findsOneWidget);
    expect(find.text('Inget att visa'), findsOneWidget);
    expect(find.text('Försök igen'), findsOneWidget);
  });

  test(
    'app shell uses centralized themes and localized loading label exists',
    () {
      final app = File('lib/src/app/teamzone_app.dart').readAsStringSync();
      final strings = File(
        'lib/src/core/localization/app_strings.dart',
      ).readAsStringSync();
      final boardStrings = File(
        'lib/src/core/localization/board_strings.dart',
      ).readAsStringSync();
      final economyStrings = File(
        'lib/src/core/localization/economy_strings.dart',
      ).readAsStringSync();
      expect(app, contains('AppTheme.light()'));
      expect(app, contains('AppTheme.dark()'));
      expect(strings, contains('String get loading'));
      for (final commonAction in [
        'cancel',
        'continueAction',
        'create',
        'save',
        'close',
        'reason',
      ]) {
        expect(strings, contains('String get $commonAction'));
      }
      expect(
        RegExp(r'Center\(child: CircularProgressIndicator\(\)\)').hasMatch(app),
        isFalse,
      );
      expect(boardStrings, contains("'scheduled'"));
      expect(boardStrings, contains("'revoked'"));
      expect(boardStrings, contains('2 approvals are required'));
      expect(app, isNot(contains('_boardOffice(')));
      expect(app, isNot(contains('_boardErrorMessage(')));
      expect(economyStrings, contains("'manual_entry'"));
      expect(economyStrings, contains("'posted'"));
      expect(
        economyStrings,
        contains('Two independent approvals are required'),
      );
      expect(app, isNot(contains('_economyErrorMessage(')));
    },
  );

  test('all Swedish app-shell literals cross the locale boundary', () {
    final app = File('lib/src/app/teamzone_app.dart').readAsStringSync();
    final strings = File(
      'lib/src/core/localization/app_strings.dart',
    ).readAsStringSync();
    final swedishLiteral = RegExp(r"'([^']*[åäöÅÄÖ][^']*)'");
    for (final match in swedishLiteral.allMatches(app)) {
      final start = (match.start - 240).clamp(0, match.start);
      final localContext = app.substring(start, match.end);
      expect(
        localContext.contains('.feature('),
        isTrue,
        reason: 'Unlocalized app literal: ${match.group(1)}',
      );
    }
    for (final match in RegExp(r"\.feature\('([^']+)'\)").allMatches(app)) {
      expect(
        strings.contains("'${match.group(1)}':"),
        isTrue,
        reason: 'Missing feature dictionary entry: ${match.group(1)}',
      );
    }
  });
}
