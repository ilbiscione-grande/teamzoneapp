import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/support/support_usage_services.dart';
import 'package:teamzone_app/src/features/support/support_usage_tab.dart';

// Supportens adminsida, del 2 (2026-11-14): Statistik shows how the apps
// are used, counts only, for a chosen period.

class _Services implements SupportUsageServices {
  final periods = <int>[];

  @override
  Future<PlatformUsage> getPlatformUsage({int periodDays = 30}) async {
    periods.add(periodDays);
    return PlatformUsage.fromJson({
      'period_days': periodDays,
      'activity_recorded_since': '2026-09-30',
      'apps_recorded_since': '2026-11-14',
      'accounts': {
        'total': 18,
        'by_type': {'member': 16, 'follower': 2},
        'new_in_period': 3,
        'linked_to_club': 14,
      },
      'active': {
        'today': 3,
        'last_7_days': 4,
        'last_30_days': 8,
        'in_period': periodDays == 7 ? 4 : 8,
      },
      'apps': {'web': 5, 'android': 2},
      'daily': [
        {'day': '2026-11-13', 'active': 2, 'new_accounts': 1},
        {'day': '2026-11-14', 'active': 3, 'new_accounts': 0},
      ],
      'clubs': {'active': 6, 'teams': 19},
      'areas': {'messages_sent': 2, 'bookings_created': 17},
      'subscriptions': {'webtool.tacticsboard': 1},
      'push_devices': {'android': 1},
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
  testWidgets('statistics show accounts, active, apps and areas', (
    tester,
  ) async {
    final services = _Services();
    await tester.pumpWidget(_app(SupportUsageTab(services: services)));
    await tester.pumpAndSettle();

    expect(services.periods, [30]);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('Medlemskonton'), findsOneWidget);
    expect(find.text('Senaste 30 dagarna'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-usage-daily')), findsOneWidget);
    expect(
      find.byTooltip('2026-11-13: 2 aktiva, 1 nya konton'),
      findsOneWidget,
    );

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Enheter med push (Android)'),
      200,
      scrollable: list,
    );
    expect(find.text('Webben'), findsOneWidget);
    expect(find.text('Bokningar skapade'), findsOneWidget);
    expect(find.text('Tacticsboard, aktiva'), findsOneWidget);
    expect(find.textContaining('Bara antal, inga namn.'), findsOneWidget);
  });

  testWidgets('choosing a period reloads it', (tester) async {
    final services = _Services();
    await tester.pumpWidget(_app(SupportUsageTab(services: services)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-usage-period-7')));
    await tester.pumpAndSettle();
    expect(services.periods, [30, 7]);
  });

  test('the app records which app an active day comes from', () {
    final profile = File(
      'lib/src/features/account/profile_services.dart',
    ).readAsStringSync();
    expect(profile, contains("_rpc('record_app_activity', {'app': app})"));
    // Desktop builds keep the old call.
    expect(profile, contains("? _rpc('record_activity')"));
    final surface = File(
      'lib/src/features/auth/support_admin_surface.dart',
    ).readAsStringSync();
    expect(surface, contains('SupportUsageTab(services: usage)'));
  });

  test('statistics are support only and contain no names', () {
    final migration = File(
      'supabase/migrations/20270318090000_support_platform_usage.sql',
    ).readAsStringSync();
    expect(
      migration,
      contains(
        "if not internal.actor_is_support_admin() then\n"
        "    raise insufficient_privilege using message = 'not_found';",
      ),
    );
    expect(migration, isNot(contains('display_name')));
    expect(migration, contains('primary key (profile_id, day, app)'));
    expect(
      migration,
      contains('revoke all on table core.profile_activity_apps'),
    );
    expect(
      migration,
      contains('greatest(7, least(coalesce(period_days, 30), 365))'),
    );
  });
}
