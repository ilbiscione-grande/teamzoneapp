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
  'active': {'now': 3, 'today': 5},
  'tools': {'ball': 103, 'player': 1802, 'cone': 6},
  'activity_recorded_since': '2026-11-14',
  'rankings': {
    'starters': [
      {'key': 'match.corner-for', 'value': 9},
      {'key': 'training.warm-up', 'value': 4},
    ],
    'shared': [
      {'key': 'x1', 'label': 'Aktiveringsrondo 6 mot 2', 'value': 7},
    ],
    'favorites': <Object>[],
    'pages': [
      {'key': '/tacticsboard/[id]', 'value': 120},
    ],
  },
  'daily_more': [
    {'day': '2026-11-14', 'active': 5, 'page_views': 120, 'uses': 13},
  ],
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
    expect(find.text('Just nu (senaste 5 min)'), findsOneWidget);

    // Tools, the most used first.
    final players = tester.getTopLeft(find.text('Spelare'));
    final balls = tester.getTopLeft(find.text('Bollar'));
    expect(players.dy < balls.dy || players.dx < balls.dx, isTrue);

    // Ranked lists with readable names, never ids or addresses.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('support-tacticsboard-ranking-pages')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Hörna anfall · Match'), findsOneWidget);
    expect(find.text('Uppvärmning · Träning'), findsOneWidget);
    expect(find.text('Aktiveringsrondo 6 mot 2'), findsOneWidget);
    expect(find.text('Tacticsboard, ett projekt'), findsOneWidget);
    expect(find.text('Inget i perioden än.'), findsOneWidget);
    expect(find.textContaining('räknas sedan 2026-11-14'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('support-tacticsboard-period-90')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );

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

  test('the two lists per day are merged by day', () {
    final usage = _usage(30);
    expect(usage.series('active').last.value, 5);
    expect(usage.series('new_projects').last.value, 5);
    expect(usage.series('active').first.value, 0);
    expect(tacticsboardSeries('uses', 'page'), 'page_views');
    expect(tacticsboardSeries('active', 'now'), 'active');
  });

  test('usage is recorded without saying who, and guests are not counted', () {
    final migration = File(
      'supabase/migrations/20270323090000_webtools_usage_tracking.sql',
    ).readAsStringSync();
    final counts = migration.substring(
      migration.indexOf(
        'create table if not exists core.webtools_usage_counts',
      ),
      migration.indexOf('alter table core.webtools_presence'),
    );
    expect(counts, isNot(contains('profile_id')));
    expect(migration, contains("auth.jwt() ->> 'is_anonymous'"));
    expect(
      migration,
      contains(
        'grant execute on function internal.get_tacticsboard_usage_more_for_server(integer) to service_role;',
      ),
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
