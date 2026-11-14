import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/support/support_log_services.dart';
import 'package:teamzone_app/src/features/support/support_log_tab.dart';

// Supportens logg (adminsidan, del 5): what support has done, newest
// first, with who did it and the reason.

class _Fake implements SupportLogServices {
  final asked = <String>[];

  @override
  Future<SupportLogPage> listSupportActions({
    String? area,
    bool includeViews = false,
    DateTime? before,
  }) async {
    asked.add(
      '${area ?? 'all'}/$includeViews/${before == null ? '-' : 'before'}',
    );
    if (before != null) {
      return SupportLogPage.fromJson({
        'entries': [
          {
            'id': 'e3',
            'occurred_at': '2026-11-12T09:00:00Z',
            'type': 'support.admin_granted',
            'actor': 'Sara Support',
            'actor_is_me': false,
            'target': 'Nils Ny',
            'reason': 'Ny i supporten',
            'details': {'again': true},
          },
        ],
        'more': false,
      });
    }
    return SupportLogPage.fromJson({
      'entries': [
        {
          'id': 'e1',
          'occurred_at': '2026-11-14T15:12:54Z',
          'type': 'support.club_admin_removed',
          'actor': '',
          'actor_is_me': true,
          'club': 'Hjälp IF',
          'target': 'Kim Kassör',
          'reason': 'Har lämnat klubben',
          'details': {'left_without_admin': true},
        },
        {
          'id': 'e2',
          'occurred_at': '2026-11-14T10:00:00Z',
          'type': 'support.board_change_applied',
          'actor': 'Sara Support',
          'actor_is_me': false,
          'club': 'Hjälp IF',
          'target': 'Bo Ordförande',
          'reason': 'Styrelsen kom inte åt appen',
          'details': {'office': 'chair', 'approvals': 1},
        },
      ],
      'more': true,
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
  testWidgets('shows what support did, with who and why', (tester) async {
    final services = _Fake();
    await tester.pumpWidget(_app(SupportLogTab(services: services)));
    await tester.pumpAndSettle();

    expect(services.asked, ['all/false/-']);
    expect(find.text('Tog bort klubbadmin'), findsOneWidget);
    expect(find.text('Hjälp IF · Kim Kassör'), findsOneWidget);
    expect(find.text('Utan namn (du)'), findsOneWidget);
    expect(find.text('Motivering: Har lämnat klubben'), findsOneWidget);
    expect(
      find.text('Klubben står nu utan klubbadmin med konto'),
      findsOneWidget,
    );
    expect(find.text('Verkställde styrelseändring'), findsOneWidget);
    expect(find.text('Godkännanden innan: 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('support-log-more')));
    await tester.pumpAndSettle();
    expect(services.asked.last, 'all/false/before');
    expect(find.text('Lade till supportadmin'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-log-more')), findsNothing);
  });

  testWidgets('filters on area and opened clubs', (tester) async {
    final services = _Fake();
    await tester.pumpWidget(_app(SupportLogTab(services: services)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-log-area-admins')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-log-views')));
    await tester.pumpAndSettle();
    expect(services.asked, ['all/false/-', 'admins/false/-', 'admins/true/-']);
  });

  test('the log is support only and leaves out requesters', () {
    final migration = File(
      'supabase/migrations/20270324090000_support_action_log.sql',
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
      contains("event.command_type <> 'support.protected_name.request.v1'"),
    );
    expect(migration, contains("<> 'support'"));
    expect(migration, isNot(contains("'requester_profile_id'")));
  });
}
