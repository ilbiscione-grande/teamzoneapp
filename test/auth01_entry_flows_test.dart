import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/auth_entry_services.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';

void main() {
  testWidgets('offers separate sign-in/create-account and both methods', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_EntryFake()));
    await tester.pumpAndSettle();

    expect(find.text('Logga in'), findsWidgets);
    expect(find.text('Skapa konto'), findsOneWidget);
    expect(find.text('Lösenord'), findsWidgets);
    expect(find.text('E-postkod/länk'), findsOneWidget);
    expect(find.text('Glömt lösenord?'), findsOneWidget);
  });

  testWidgets(
    'password account creation requires matching password and verification',
    (tester) async {
      final entry = _EntryFake();
      await tester.pumpWidget(_app(entry));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skapa konto'));
      await tester.pumpAndSettle();

      await tester.enterText(_field('E-post'), 'new@example.com');
      await tester.enterText(_field('Lösenord'), 'correct-horse');
      await tester.enterText(_field('Bekräfta lösenord'), 'correct-horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Skapa konto'));
      await tester.pumpAndSettle();

      expect(entry.signUpCalls, 1);
      expect(entry.lastEmail, 'new@example.com');
      expect(
        find.textContaining('verifiera adressen innan du loggar in'),
        findsOneWidget,
      );
    },
  );

  testWidgets('email sign-in explicitly forbids implicit account creation', (
    tester,
  ) async {
    final entry = _EntryFake();
    await tester.pumpWidget(_app(entry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('E-postkod/länk'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('E-post'), 'member@example.com');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Skicka e-postkod/länk'),
    );
    await tester.pumpAndSettle();

    expect(entry.lastPurpose, EmailChallengePurpose.signIn);
    expect(find.text('E-postkod'), findsOneWidget);
    expect(find.textContaining('Skicka ny kod om'), findsOneWidget);
    final resend = tester.widget<TextButton>(
      find.ancestor(
        of: find.textContaining('Skicka ny kod om'),
        matching: find.byType(TextButton),
      ),
    );
    expect(resend.onPressed, isNull);
  });

  testWidgets('email account creation uses sign-up purpose and verifies code', (
    tester,
  ) async {
    final entry = _EntryFake();
    await tester.pumpWidget(_app(entry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skapa konto'));
    await tester.tap(find.text('E-postkod/länk'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('E-post'), 'new@example.com');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Skicka e-postkod/länk'),
    );
    await tester.pumpAndSettle();
    expect(entry.lastPurpose, EmailChallengePurpose.signUp);

    await tester.enterText(_field('E-postkod'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Verifiera kod'));
    await tester.pumpAndSettle();
    expect(entry.verifiedCode, '123456');
  });

  testWidgets('forgot-password response remains neutral on backend failure', (
    tester,
  ) async {
    final entry = _EntryFake()..failReset = true;
    await tester.pumpWidget(_app(entry));
    await tester.pumpAndSettle();
    await tester.enterText(_field('E-post'), 'unknown@example.com');
    await tester.tap(find.text('Glömt lösenord?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Om adressen är registrerad'), findsOneWidget);
  });

  testWidgets(
    'password recovery event takes precedence over authenticated shell',
    (tester) async {
      final entry = _EntryFake();
      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'test'),
          locale: const Locale('sv'),
          services: AppServices(
            identity: _Identity(status: SessionStatus.authenticated),
            authEntry: entry,
            isConfigured: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      entry.events.add(AuthEntryEvent.passwordRecovery);
      await tester.pumpAndSettle();
      expect(find.text('Nytt lösenord'), findsWidgets);
      await entry.events.close();
    },
  );

  test('OTP cooldown and expiry use deterministic time', () {
    var now = DateTime.utc(2026, 8, 23, 12);
    final controller = EmailChallengeController(now: () => now)..markSent();
    expect(controller.canResend, isFalse);
    expect(controller.isExpired, isFalse);
    now = now.add(const Duration(seconds: 61));
    expect(controller.canResend, isTrue);
    expect(controller.isExpired, isFalse);
    now = now.add(const Duration(minutes: 10));
    expect(controller.isExpired, isTrue);
    controller.dispose();
  });

  test('Supabase adapter uses exact safe Auth SDK contracts', () {
    final source = File(
      'lib/src/core/supabase/supabase_bootstrap.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('shouldCreateUser: purpose == EmailChallengePurpose.signUp'),
    );
    expect(source, contains('type: OtpType.email'));
    expect(source, contains('resetPasswordForEmail'));
    expect(source, contains('AuthChangeEvent.passwordRecovery'));
    expect(source, contains("'teamzone://app/auth/callback'"));
    expect(source, contains("'https://app.teamzoneapp.se/auth/callback'"));
    expect(source, isNot(contains('service_role')));
  });
}

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

Widget _app(_EntryFake entry) => TeamZoneApp(
  environment: const AppEnvironment(name: 'test'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: _Identity(status: SessionStatus.unauthenticated),
    authEntry: entry,
    isConfigured: true,
  ),
);

class _EntryFake implements AuthEntryServices {
  final events = StreamController<AuthEntryEvent>.broadcast();
  int signUpCalls = 0;
  String? lastEmail;
  String? verifiedCode;
  EmailChallengePurpose? lastPurpose;
  bool failReset = false;

  @override
  Stream<AuthEntryEvent> get entryEvents => events.stream;

  @override
  Future<void> requestEmailChallenge({
    required String email,
    required EmailChallengePurpose purpose,
  }) async {
    lastEmail = email;
    lastPurpose = purpose;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    if (failReset) throw StateError('private detail');
  }

  @override
  Future<PasswordSignUpResult> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    signUpCalls += 1;
    lastEmail = email;
    return const PasswordSignUpResult(verificationRequired: true);
  }

  @override
  Future<void> updatePassword({required String password}) async {}

  @override
  Future<void> verifyEmailChallenge({
    required String email,
    required String code,
  }) async {
    verifiedCode = code;
  }
}

class _Identity implements IdentityServices {
  _Identity({required this.status});
  final SessionStatus status;
  @override
  SessionStatus get sessionStatus => status;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [];
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}
