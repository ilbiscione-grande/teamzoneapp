import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/support/support_club_actions.dart';
import 'package:teamzone_app/src/features/support/support_club_services.dart';
import 'package:teamzone_app/src/features/support/support_clubs_tab.dart';

// Supportens adminsida, del 3 (2026-11-14): support appoints or removes a
// club admin and applies or cancels a stuck board change, each with a
// reason that is logged.

class _Services implements SupportClubServices, SupportClubActionServices {
  _Services({this.admins = 1});
  final int admins;
  final calls = <String>[];
  Object? refuse;
  bool leftWithout = false;

  @override
  Future<List<SupportClubSummary>> listClubsForSupport() async => const [];

  @override
  Future<SupportClubDetail> getClubForSupport({required String clubId}) async =>
      SupportClubDetail.fromJson({
        'club_id': clubId,
        'club_name': 'Hjälp IF',
        'club_status': 'active',
        'verification_status': 'official',
        'has_admin_with_account': true,
        'board_forming': false,
        'admins': [
          {
            'person_id': 'p-anna',
            'name': 'Anna Admin',
            'has_account': true,
            'ends_at': null,
          },
          if (admins > 1)
            {
              'person_id': 'p-erik',
              'name': 'Erik Admin',
              'has_account': true,
              'ends_at': null,
            },
        ],
        'board': const [],
        'pending_board_changes': [
          {
            'id': 'change-1',
            'action': 'grant',
            'office': 'treasurer',
            'name': 'Cia Kassör',
            'created_at': '2026-11-01T08:00:00Z',
            'approvals': 1,
          },
        ],
        'people_with_account': [
          {'person_id': 'p-anna', 'name': 'Anna Admin', 'is_admin': true},
          {'person_id': 'p-david', 'name': 'David Tränare', 'is_admin': false},
        ],
        'teams': const [],
      });

  @override
  Future<void> grantClubAdmin({
    required String clubId,
    required String personId,
    required String reason,
  }) async {
    calls.add('grant $personId: $reason');
    if (refuse != null) throw refuse!;
  }

  @override
  Future<bool> removeClubAdmin({
    required String clubId,
    required String personId,
    required String reason,
  }) async {
    calls.add('remove $personId: $reason');
    if (refuse != null) throw refuse!;
    return leftWithout;
  }

  @override
  Future<void> resolveBoardChange({
    required String changeId,
    required bool apply,
    required String reason,
  }) async {
    calls.add('${apply ? 'apply' : 'cancel'} $changeId: $reason');
    if (refuse != null) throw refuse!;
  }
}

Widget _sheet(_Services services, {VoidCallback? onChanged}) => MaterialApp(
  locale: const Locale('sv'),
  supportedLocales: const [Locale('sv')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: SupportClubDetailSheet(
      services: services,
      actions: services,
      clubId: 'c1',
      name: 'Hjälp IF',
      onChanged: onChanged,
    ),
  ),
);

Future<void> _reason(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('support-club-action-reason')),
    text,
  );
  await tester.tap(find.byKey(const ValueKey('support-club-action-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a club admin is appointed among those with an account', (
    tester,
  ) async {
    var changed = 0;
    final services = _Services();
    await tester.pumpWidget(_sheet(services, onChanged: () => changed++));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('support-club-admin-grant')));
    await tester.pumpAndSettle();
    // Only someone who is not admin yet can be chosen.
    await tester.tap(find.byKey(const ValueKey('support-club-admin-person')));
    await tester.pumpAndSettle();
    expect(find.text('David Tränare').last, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DropdownMenuItem<String>),
        matching: find.text('Anna Admin'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('David Tränare').last);
    await tester.pumpAndSettle();

    await _reason(tester, 'kort');
    expect(services.calls, isEmpty);
    expect(find.text('Ange minst 5 tecken.'), findsOneWidget);

    await _reason(tester, 'Ordförande bad om hjälp');
    expect(services.calls, ['grant p-david: Ordförande bad om hjälp']);
    expect(find.text('Klubbadmin är utsedd.'), findsOneWidget);
    expect(changed, 1);
  });

  testWidgets('removing the only admin warns of the logged exception', (
    tester,
  ) async {
    final services = _Services()..leftWithout = true;
    await tester.pumpWidget(_sheet(services));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('support-club-admin-remove-p-anna')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('support-club-action-warning')),
      findsOneWidget,
    );
    await _reason(tester, 'Anna har lämnat klubben');
    expect(services.calls, ['remove p-anna: Anna har lämnat klubben']);
    expect(
      find.text(
        'Klubbadmin är borttagen. Klubben saknar nu klubbadmin med konto.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('removing one of two admins has no warning', (tester) async {
    final services = _Services(admins: 2);
    await tester.pumpWidget(_sheet(services));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('support-club-admin-remove-p-erik')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('support-club-action-warning')),
      findsNothing,
    );
    await _reason(tester, 'Erik har slutat');
    expect(find.text('Klubbadmin är borttagen.'), findsOneWidget);
  });

  testWidgets('a stuck board change is applied or explained when refused', (
    tester,
  ) async {
    final services = _Services()
      ..refuse = const PostgrestException(
        message: 'board_change_not_pending',
        code: 'PT409',
      );
    await tester.pumpWidget(_sheet(services));
    await tester.pumpAndSettle();

    final apply = find.byKey(const ValueKey('support-board-apply-change-1'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ändringen genomförs utan styrelsens godkännanden. Gör det bara när styrelsen inte kan godkänna själv.',
      ),
      findsOneWidget,
    );
    await _reason(tester, 'Andra godkännaren har avgått');
    expect(services.calls, ['apply change-1: Andra godkännaren har avgått']);
    expect(find.text('Styrelseändringen väntar inte längre.'), findsOneWidget);
  });

  testWidgets('without actions the club view only reads', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('sv'),
        supportedLocales: const [Locale('sv')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SupportClubDetailSheet(
            services: _Services(),
            clubId: 'c1',
            name: 'Hjälp IF',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('support-club-admin-grant')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('support-board-apply-change-1')),
      findsNothing,
    );
  });

  test('refusal codes are recognised', () {
    expect(
      supportClubActionRefusal(
        const PostgrestException(message: 'already_club_admin', code: 'PT409'),
      ),
      'already_club_admin',
    );
    expect(supportClubActionRefusal(Exception('network')), isNull);
  });

  test('every action is support-only, needs a reason and is logged', () {
    final migration = File(
      'supabase/migrations/20270320090000_support_club_actions.sql',
    ).readAsStringSync();
    expect(
      RegExp(
        r"if not internal\.actor_is_support_admin\(\) then\s+"
        r"raise insufficient_privilege using message = 'not_found';",
      ).allMatches(migration).length,
      4,
    );
    expect(
      RegExp(
        r'clean_reason := internal\.support_reason\(reason\);',
      ).allMatches(migration).length,
      3,
    );
    for (final event in [
      'support.club_admin_granted',
      'support.club_admin_removed',
      'support.board_change_applied',
      'support.board_change_cancelled',
    ]) {
      expect(migration, contains("'$event'"));
    }
    // The emergency exception is narrow: on, checked at once, off again.
    expect(
      migration,
      contains(
        "perform set_config('teamzone.allow_no_club_admin', 'on', true);\n"
        '    set constraints core.capability_grants_club_keeps_admin immediate;\n'
        '    set constraints core.capability_grants_club_keeps_admin deferred;\n'
        "    perform set_config('teamzone.allow_no_club_admin', 'off', true);",
      ),
    );
    expect(migration, contains("raise sqlstate 'PT409'"));
    expect(migration, isNot(contains('serialization_failure')));
  });
}
