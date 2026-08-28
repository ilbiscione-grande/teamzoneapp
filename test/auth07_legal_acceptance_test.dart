import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/legal/legal_models.dart';
import 'package:teamzone_app/src/features/legal/legal_services.dart';

void main() {
  testWidgets('mandatory legal versions block app and marketing is opt-in', (
    tester,
  ) async {
    final legal = _LegalFake();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          legal: legal,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Läs och godkänn för att fortsätta'), findsOneWidget);
    expect(find.textContaining('Ditt konto är klart'), findsNothing);
    final boxes = find.byType(CheckboxListTile);
    expect((tester.widget<CheckboxListTile>(boxes.at(2))).value, isFalse);
    expect(find.text('Godkänn och fortsätt'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Godkänn och fortsätt'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(boxes.at(0));
    await tester.tap(boxes.at(1));
    await tester.pump();
    await tester.tap(find.text('Godkänn och fortsätt'));
    await tester.pumpAndSettle();
    expect(legal.acceptedTerms, '2026-08-24');
    expect(legal.acceptedPrivacy, '2026-08-24');
    expect(legal.acceptedMarketing, isFalse);
    expect(find.text('Läs och godkänn för att fortsätta'), findsNothing);
  });

  test('AUTH-07 contract versions legal acceptance and separates consent', () {
    final sql = File(
      'supabase/migrations/20260824124115_auth07_legal_acceptance.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('legal_document_versions_one_active'));
    expect(sql, contains('core.legal_acceptances'));
    expect(sql, contains('core.communication_preferences'));
    expect(sql, contains('marketing_opt_in boolean not null default false'));
    expect(sql, contains('legal_version_changed'));
    expect(sql, contains("'identity.legal.accept.v1'"));
    expect(sql, contains("'identity.marketing.preference.v1'"));
    expect(sql, isNot(contains('publication_consents')));
    expect(sql, isNot(contains('guardian')));
    expect(
      sql,
      contains(
        'revoke all on table internal.legal_document_versions,core.legal_acceptances',
      ),
    );
  });
}

class _LegalFake implements LegalServices {
  bool accepted = false;
  String? acceptedTerms, acceptedPrivacy;
  bool? acceptedMarketing;

  @override
  Future<LegalStatus> getStatus() async => LegalStatus(
    termsVersion: '2026-08-24',
    termsUrl: 'https://teamzoneapp.se/villkor',
    termsAccepted: accepted,
    privacyVersion: '2026-08-24',
    privacyUrl: 'https://teamzoneapp.se/integritet',
    privacyAccepted: accepted,
    marketingOptIn: false,
  );

  @override
  Future<void> acceptCurrent({
    required String termsVersion,
    required String privacyVersion,
    required bool marketingOptIn,
    required String idempotencyKey,
  }) async {
    accepted = true;
    acceptedTerms = termsVersion;
    acceptedPrivacy = privacyVersion;
    acceptedMarketing = marketingOptIn;
  }

  @override
  Future<void> setMarketingPreference({
    required bool marketingOptIn,
    required String idempotencyKey,
  }) async => acceptedMarketing = marketingOptIn;
}

class _Identity implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Ada', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}
