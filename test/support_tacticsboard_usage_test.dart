import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/support/support_tacticsboard_services.dart';
import 'package:teamzone_app/src/features/support/support_tacticsboard_tab.dart';

// Supportens statistik för Tacticsboard (2026-11-14): counts from
// Tacticsboard's own database, read through an edge function that checks
// the caller is a support administrator.

TacticsboardUsage _usage(int periodDays) => TacticsboardUsage.fromJson({
  'period_days': periodDays,
  'accounts': {'total': 18, 'new_in_period': 4, 'signed_in_7_days': 5},
  'billing': {'trials_active': 2, 'trials_started': 4},
  'subscriptions': {
    'paying_month': 7,
    'paying_year': 3,
    'withdrawals_in_period': null,
  },
  'projects': {'total': 11, 'new_in_period': 6},
  'live': {'sessions_in_period': 2},
  'sharing': {'open_reports': 1},
  'daily': [
    {'day': '2026-11-13', 'new_projects': 1, 'new_accounts': 0},
    {'day': '2026-11-14', 'new_projects': 5, 'new_accounts': 2},
  ],
}, source: 'zfxcblgnemuenaqjkaic');

class _Fake implements SupportTacticsboardServices {
  _Fake({this.configured = true});
  final bool configured;
  final asked = <int>[];

  @override
  Future<TacticsboardUsage> getTacticsboardUsage({int periodDays = 30}) async {
    asked.add(periodDays);
    if (!configured) throw const TacticsboardUsageNotConfigured();
    return _usage(periodDays);
  }
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('sv'),
  supportedLocales: const [Locale('sv')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  testWidgets('shows Tacticsboard counts and opens a card', (tester) async {
    final services = _Fake();
    await tester.pumpWidget(_app(SupportTacticsboardTab(services: services)));
    await tester.pumpAndSettle();

    expect(find.text('Provperioder'), findsOneWidget);
    expect(find.text('Betalar per månad'), findsOneWidget);
    // Not recorded in this database: no card.
    expect(find.text('Ångrade köp i perioden'), findsNothing);
    expect(find.textContaining('zfxcblgnemuenaqjkaic'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('support-tacticsboard-period-90')),
    );
    await tester.pumpAndSettle();
    expect(services.asked, [30, 90]);

    final card = find.byKey(
      const ValueKey('support-usage-tacticsboard_projects-new_in_period'),
    );
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('support-tacticsboard-detail')),
      findsOneWidget,
    );
    expect(find.text('Nya projekt per dag'), findsOneWidget);
    expect(find.byTooltip('2026-11-14: 5'), findsOneWidget);
  });

  testWidgets('says when the database is not connected', (tester) async {
    await tester.pumpWidget(
      _app(SupportTacticsboardTab(services: _Fake(configured: false))),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('support-tacticsboard-not-configured')),
      findsOneWidget,
    );
  });

  test('only the server may read the counts, and only counts', () {
    final migration = File(
      'supabase/migrations/20270322090000_tacticsboard_usage_for_support.sql',
    ).readAsStringSync();
    expect(migration, contains('from public, anon, authenticated;'));
    expect(migration, contains('to service_role;'));
    expect(migration, isNot(contains('to authenticated')));
    expect(migration, isNot(contains('display_name')));
    expect(migration, isNot(contains('customer_email')));

    final function = File(
      'supabase/functions/support-tacticsboard-usage/index.ts',
    ).readAsStringSync();
    expect(function, contains('.rpc("is_support_admin")'));
    expect(function, contains('isSupportAdmin !== true'));
    expect(function, contains('"not_configured"'));
  });
}
