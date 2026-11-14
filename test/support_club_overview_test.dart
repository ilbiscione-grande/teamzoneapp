import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/support/support_club_services.dart';
import 'package:teamzone_app/src/features/support/support_clubs_tab.dart';

// Supportens adminsida, del 1 (2026-11-14): Klubbar shows every club,
// those needing support first; opening one shows names and is logged.

SupportClubSummary _club(
  String id,
  String name, {
  int admins = 1,
  int pending = 0,
  String status = 'active',
}) => SupportClubSummary.fromJson({
  'club_id': id,
  'club_name': name,
  'club_status': status,
  'verification_status': 'unofficial',
  'created_at': '2026-10-01T10:00:00Z',
  'team_count': 2,
  'people_count': 40,
  'account_count': 5,
  'admin_count': admins,
  'board_mandate_count': 3,
  'board_forming': true,
  'pending_board_changes': pending,
  'oldest_pending_board_change': pending > 0 ? '2026-11-10T08:00:00Z' : null,
});

class _Services implements SupportClubServices {
  final opened = <String>[];

  @override
  Future<List<SupportClubSummary>> listClubsForSupport() async => [
    _club('c1', 'Utan admin IF', admins: 0),
    _club('c2', 'Styrelse väntar BK', pending: 2),
    _club('c3', 'Lugna klubben'),
    _club('c4', 'Avslutade FF', admins: 0, status: 'ended'),
  ];

  @override
  Future<SupportClubDetail> getClubForSupport({required String clubId}) async {
    opened.add(clubId);
    return SupportClubDetail.fromJson({
      'club_id': clubId,
      'club_name': 'Utan admin IF',
      'club_status': 'active',
      'verification_status': 'official',
      'has_admin_with_account': false,
      'board_forming': true,
      'admins': [
        {'name': 'Anna Admin', 'has_account': false, 'ends_at': null},
      ],
      'board': [
        {
          'name': 'Bo Ordförande',
          'office': 'chair',
          'has_account': true,
          'starts_at': '2026-01-01T00:00:00Z',
          'ends_at': '2027-03-01T00:00:00Z',
        },
      ],
      'pending_board_changes': [
        {
          'action': 'grant',
          'office': 'treasurer',
          'name': 'Cia Kassör',
          'created_at': '2026-11-10T08:00:00Z',
          'approvals': 1,
        },
      ],
      'teams': [
        {'name': 'P12', 'status': 'active', 'people': 18},
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
  testWidgets('clubs needing support are flagged and can be filtered', (
    tester,
  ) async {
    await tester.pumpWidget(_app(SupportClubsTab(services: _Services())));
    await tester.pumpAndSettle();

    expect(find.text('4 klubbar · 2 behöver hjälp'), findsOneWidget);
    // Only an active club lacks an admin; an ended one does not need help.
    expect(find.text('Saknar klubbadmin med konto'), findsOneWidget);
    expect(
      find.text('2 väntande styrelseändringar, äldsta från 2026-11-10'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('support-clubs-attention')));
    await tester.pumpAndSettle();
    expect(find.text('Lugna klubben'), findsNothing);
    expect(find.text('Avslutade FF'), findsNothing);
    expect(find.text('Utan admin IF'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('support-clubs-search')),
      'styrelse',
    );
    await tester.pumpAndSettle();
    expect(find.text('Utan admin IF'), findsNothing);
    expect(find.text('Styrelse väntar BK'), findsOneWidget);
  });

  testWidgets('opening a club shows admins, board, changes and teams', (
    tester,
  ) async {
    final services = _Services();
    await tester.pumpWidget(_app(SupportClubsTab(services: services)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Utan admin IF'));
    await tester.pumpAndSettle();

    expect(services.opened, ['c1']);
    expect(find.byKey(const ValueKey('support-club-detail')), findsOneWidget);
    expect(find.text('Anna Admin'), findsOneWidget);
    expect(find.text('Inget konto'), findsOneWidget);
    expect(find.text('Ordförande: Bo Ordförande'), findsOneWidget);
    expect(find.text('Lägg till Kassör: Cia Kassör'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Att du öppnade klubben sparas i supportens logg.'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('support-club-detail')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('P12'), findsOneWidget);
    expect(
      find.text('Att du öppnade klubben sparas i supportens logg.'),
      findsOneWidget,
    );
  });

  test('the app reaches the overview through the Supabase services', () {
    final services = File(
      'lib/src/features/membership/membership_services.dart',
    ).readAsStringSync();
    expect(services, contains('SupportClubServices,'));
    expect(services, contains('fetchClubsForSupport(_client)'));
    final surface = File(
      'lib/src/features/auth/support_admin_surface.dart',
    ).readAsStringSync();
    expect(surface, contains('membership is SupportClubServices'));
    expect(surface, contains('SupportClubsTab(services: clubs)'));
  });

  test('the server functions are support only and log each opened club', () {
    final migration = File(
      'supabase/migrations/20270317090000_support_club_overview.sql',
    ).readAsStringSync();
    expect(
      RegExp(
        r"if not internal\.actor_is_support_admin\(\) then\s+"
        r"raise insufficient_privilege using message = 'not_found';",
      ).allMatches(migration).length,
      2,
    );
    expect(migration, contains("'support.club_viewed'"));
    // The same rule as the guard that keeps a club admin.
    expect(
      migration,
      contains('internal.club_has_admin_with_account(club.id)'),
    );
    expect(migration, contains("grant_row.ends_at is null"));
    expect(migration, contains('from public, anon, authenticated;'));
    expect(migration, isNot(contains('serialization_failure')));
  });
}
