import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/features/support/support_admin_services.dart';
import 'package:teamzone_app/src/features/support/support_admins_tab.dart';

// Support split from the app (2026-11-14): support.teamzoneapp.se shows only
// the support page, support is done from an account of its own, and who is
// a support administrator is changed on the page with a reason.

class _Admins implements SupportAdminServices {
  final calls = <String>[];
  Object? refuse;

  final rows = [
    SupportAdmin.fromJson({
      'profile_id': 'me',
      'display_name': 'Thomas',
      'email': 'personal@example.test',
      'active': true,
      'created_at': '2026-09-11T10:00:00Z',
      'is_self': true,
      'club_count': 1,
    }),
    SupportAdmin.fromJson({
      'profile_id': 'old',
      'display_name': 'Tidigare',
      'email': '',
      'active': false,
      'created_at': '2026-09-11T10:00:00Z',
      'revoked_at': '2026-10-01T10:00:00Z',
      'is_self': false,
      'club_count': 0,
    }),
  ];

  @override
  Future<List<SupportAdmin>> listSupportAdmins() async => rows;

  @override
  Future<void> grantSupportAdmin({
    required String email,
    required String reason,
  }) async {
    calls.add('grant $email: $reason');
    if (refuse != null) throw refuse!;
  }

  @override
  Future<void> revokeSupportAdmin({
    required String profileId,
    required String reason,
  }) async {
    calls.add('revoke $profileId: $reason');
    if (refuse != null) throw refuse!;
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
  test('the support site is recognised by its address', () {
    expect(isSupportSiteHost('support.teamzoneapp.se'), isTrue);
    expect(isSupportSiteHost('teamzoneapp-support.web.app'), isTrue);
    expect(isSupportSiteHost('app.teamzoneapp.se'), isFalse);
    expect(isSupportSiteHost('teamzoneapp-b02a2.web.app'), isFalse);
    expect(supportSiteUrl, 'https://support.teamzoneapp.se');
  });

  testWidgets('a support account with club roles is pointed out', (
    tester,
  ) async {
    await tester.pumpWidget(_app(SupportAdminsTab(services: _Admins())));
    await tester.pumpAndSettle();
    expect(find.text('Thomas (du)'), findsOneWidget);
    expect(find.text('Har roller i 1 klubb'), findsOneWidget);
    expect(find.text('Tidigare'), findsWidgets);
    expect(find.text('Borttagen 2026-10-01'), findsOneWidget);
  });

  testWidgets('adding needs an address and a reason', (tester) async {
    final admins = _Admins();
    await tester.pumpWidget(_app(SupportAdminsTab(services: admins)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-admin-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('support-admin-email')),
      'support@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('support-admin-reason')),
      'kort',
    );
    await tester.tap(find.byKey(const ValueKey('support-admin-add-confirm')));
    await tester.pumpAndSettle();
    expect(admins.calls, isEmpty);
    expect(find.text('Ange minst 5 tecken.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('support-admin-reason')),
      'Eget supportkonto',
    );
    await tester.tap(find.byKey(const ValueKey('support-admin-add-confirm')));
    await tester.pumpAndSettle();
    expect(admins.calls, ['grant support@example.test: Eget supportkonto']);
    expect(find.text('Supportadministratören är tillagd.'), findsOneWidget);
  });

  testWidgets('the last support administrator is explained, not removed', (
    tester,
  ) async {
    var signedOut = false;
    final admins = _Admins()
      ..refuse = const PostgrestException(message: 'last_support_admin');
    await tester.pumpWidget(
      _app(
        SupportAdminsTab(
          services: admins,
          onSelfRemoved: () => signedOut = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-admin-remove-me')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Du tar bort din egen supporträtt. Supportsidan stängs för det här kontot.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('support-admin-reason')),
      'Supporten sköts från eget konto',
    );
    await tester.tap(
      find.byKey(const ValueKey('support-admin-remove-confirm')),
    );
    await tester.pumpAndSettle();
    expect(admins.calls, ['revoke me: Supporten sköts från eget konto']);
    expect(
      find.text(
        'Den sista supportadministratören kan inte tas bort. Lägg till en annan först.',
      ),
      findsOneWidget,
    );
    expect(signedOut, isFalse);
  });

  testWidgets('removing oneself signs out of the support site', (tester) async {
    var signedOut = false;
    final admins = _Admins();
    await tester.pumpWidget(
      _app(
        SupportAdminsTab(
          services: admins,
          onSelfRemoved: () => signedOut = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-admin-remove-me')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('support-admin-reason')),
      'Supporten sköts från eget konto',
    );
    await tester.tap(
      find.byKey(const ValueKey('support-admin-remove-confirm')),
    );
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });

  test('the app no longer holds the support page', () {
    final shell = File('lib/src/app/product_shell.dart').readAsStringSync();
    expect(shell, contains('const _SupportMovedSurface()'));
    expect(shell, isNot(contains('_SupportAdminSurface(')));
    final inbox = File(
      'lib/src/features/messaging/inbox_surface.dart',
    ).readAsStringSync();
    expect(inbox, contains('onTap: openSupportSite'));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('isSupportSiteHost(Uri.base.host)'));
    final origins = File(
      'supabase/functions/_shared/sign_in_limits.ts',
    ).readAsStringSync();
    expect(origins, contains('"https://support.teamzoneapp.se"'));
  });

  test('support administrators change only with a reason, never to none', () {
    final migration = File(
      'supabase/migrations/20270319090000_support_admin_management.sql',
    ).readAsStringSync();
    expect(
      RegExp(
        r"if not internal\.actor_is_support_admin\(\) then\s+"
        r"raise insufficient_privilege using message = 'not_found';",
      ).allMatches(migration).length,
      3,
    );
    expect(
      migration,
      contains("raise check_violation using message = 'last_support_admin';"),
    );
    expect(
      migration,
      contains(
        'perform 1 from internal.support_admins admin where admin.active for update;',
      ),
    );
    expect(migration, contains("'support.admin_granted'"));
    expect(migration, contains("'support.admin_revoked'"));
    expect(migration, contains("raise sqlstate 'PT409'"));
    expect(migration, isNot(contains('serialization_failure')));
  });
}
