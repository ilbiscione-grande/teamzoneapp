import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/support/support_usage_services.dart';
import 'package:teamzone_app/src/features/support/support_usage_tab.dart';

// Supportens statistik (2026-11-14): each card opens to a value per day in
// the period and breakdowns. Counts only; the only names are clubs.

PlatformUsage _usage(int periodDays) => PlatformUsage.fromJson({
  'period_days': periodDays,
  'activity_recorded_since': '2026-09-30',
  'apps_recorded_since': '2026-11-14',
  'accounts': {
    'total': 18,
    'by_type': {'member': 16, 'follower': 2},
    'new_in_period': 3,
    'linked_to_club': 14,
  },
  'active': {'today': 3, 'last_7_days': 4, 'last_30_days': 8, 'in_period': 8},
  'apps': {'web': 5},
  'daily': [
    {'day': '2026-11-14', 'active': 3, 'new_accounts': 0},
  ],
  'clubs': {'active': 6},
  'areas': {'callup_answers': 1247},
  'subscriptions': const {},
  'push_devices': const {},
});

class _Basic implements SupportUsageServices {
  @override
  Future<PlatformUsage> getPlatformUsage({int periodDays = 30}) async =>
      _usage(periodDays);
}

class _Detailed extends _Basic implements SupportUsageDetailServices {
  final opened = <String>[];

  @override
  Future<UsageDetail> getUsageDetail({
    required String metric,
    required String item,
    int periodDays = 30,
  }) async {
    opened.add('$metric.$item/$periodDays');
    return UsageDetail.fromJson({
      'metric': metric,
      'item': item,
      'daily': [
        {'day': '2026-11-13', 'value': 400},
        {'day': '2026-11-14', 'value': 847},
      ],
      'groups': [
        {
          'group': 'by_response',
          'rows': [
            {'key': 'accepted', 'value': 1000},
            {'key': 'declined', 'value': 247},
          ],
        },
        {
          'group': 'clubs',
          'rows': [
            {'key': 'c1', 'label': 'Hjälp IF', 'value': 900},
            {'key': 'c2', 'label': 'Lugna BK', 'value': 347},
          ],
        },
      ],
    });
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
  testWidgets('a card opens to a value per day and breakdowns', (tester) async {
    final services = _Detailed();
    await tester.pumpWidget(_app(SupportUsageTab(services: services)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('support-usage-period-90')));
    await tester.pumpAndSettle();
    final card = find.byKey(
      const ValueKey('support-usage-area-callup_answers'),
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

    expect(services.opened, ['area.callup_answers/90']);
    final sheet = find.byKey(const ValueKey('support-usage-detail'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Svar på kallelser')),
      findsOneWidget,
    );
    expect(find.text('Antal i perioden.'), findsOneWidget);
    expect(find.byTooltip('2026-11-14: 847'), findsOneWidget);
    expect(find.text('Svar'), findsOneWidget);
    expect(find.text('Kommer'), findsOneWidget);
    expect(find.text('Kommer inte'), findsOneWidget);
    expect(find.text('Klubbar med flest'), findsOneWidget);
    expect(find.text('Hjälp IF'), findsOneWidget);
    expect(find.text('900'), findsOneWidget);
  });

  testWidgets('the active-accounts card asks for its window', (tester) async {
    final services = _Detailed();
    await tester.pumpWidget(_app(SupportUsageTab(services: services)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('support-usage-active-last_7_days')),
    );
    await tester.pumpAndSettle();
    expect(services.opened, ['active.last_7_days/30']);
    expect(find.text('Aktiva konton per dag'), findsWidgets);
  });

  testWidgets('without details the cards are not clickable', (tester) async {
    await tester.pumpWidget(_app(SupportUsageTab(services: _Basic())));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('support-usage-accounts-total')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-usage-detail')), findsNothing);
  });

  test('card details are support-only and give counts', () {
    final migration = File(
      'supabase/migrations/20270321090000_support_usage_details.sql',
    ).readAsStringSync();
    expect(
      migration,
      contains(
        "if not internal.actor_is_support_admin() then\n"
        "    raise insufficient_privilege using message = 'not_found';",
      ),
    );
    expect(
      migration,
      contains(
        "raise invalid_parameter_value using message = 'unknown_metric';",
      ),
    );
    // The only names returned are club names.
    expect(migration, isNot(contains('display_name')));
    expect(migration, isNot(contains('email')));
  });
}
