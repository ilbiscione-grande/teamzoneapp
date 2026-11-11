import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/membership/club_fees.dart';
import 'package:teamzone_app/src/features/membership/membership_services.dart';

// "Medlem i klubben" (2026-11-11): a club-wide role without a team or any
// capability. Someone who only has it gets the app, not the waiting room,
// and finds Mina avgifter under Inställningar.
void main() {
  testWidgets('a member of the club without a team gets the app', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Member(),
          membership: _Fees(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('waiting-room')), findsNothing);
    // The member's app: the club's Home and the usual tabs.
    expect(find.text('Hem'), findsWidgets);
    expect(find.text('Mer'), findsWidgets);

    await tester.tap(find.text('Mer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inställningar').last);
    await tester.pumpAndSettle();
    final myFees = find.byKey(const ValueKey('setting-my-fees'));
    await tester.ensureVisible(myFees);
    await tester.pumpAndSettle();
    await tester.tap(myFees);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-club-fees')), findsOneWidget);
    expect(find.text('Du har inga obetalda avgifter.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Member implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Mia', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'member-ctx',
      clubId: 'club-a',
      clubName: 'IF Eksjö Fotboll',
      rolePackage: 'member',
      capabilities: {},
    ),
  ];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _Fees extends UnconfiguredMembershipServices implements ClubFeesProvider {
  @override
  ClubFeeServices get clubFees => _NoFees();
}

class _NoFees implements ClubFeeServices {
  @override
  Future<List<MyClubFee>> loadMyClubFees() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
