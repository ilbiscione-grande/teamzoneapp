import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/product/role_situation_contract.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';

void main() {
  const roles = <String>['leader', 'player', 'guardian', 'club_functionary'];
  const viewports = <String, Size>{
    'phone': Size(390, 844),
    'tablet': Size(800, 1100),
    'desktop_web': Size(1440, 900),
  };

  for (final role in roles) {
    for (final viewport in viewports.entries) {
      testWidgets('$role × ${viewport.key} keeps all core surfaces safe', (
        tester,
      ) async {
        tester.view.physicalSize = viewport.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final productRole = RoleSituationContract.roleForPackage(role);
        expect(productRole, isNotNull);
        for (final surface in PrioritySurface.values) {
          final contract = RoleSituationContract.surface(productRole!, surface);
          expect(contract.primaryActions, isNotEmpty);
          expect(
            contract.primaryActions.intersection(
              contract.hiddenWithoutCapability,
            ),
            isEmpty,
          );
        }

        await tester.pumpWidget(_app(role));
        await tester.pumpAndSettle();
        expect(find.textContaining('REL-02-laget'), findsWidgets);

        for (final destination in const ['Hem', 'Laget', 'Kalender', 'Inbox']) {
          final target = find.text(destination).last;
          expect(target, findsOneWidget, reason: '$role ${viewport.key}');
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        expect(
          find.byType(NavigationRail),
          viewport.key == 'phone' ? findsNothing : findsOneWidget,
        );
        expect(
          find.byType(NavigationBar),
          viewport.key == 'phone' ? findsOneWidget : findsNothing,
        );
      });
    }
  }

  test('unknown role remains outside the release matrix', () {
    expect(RoleSituationContract.roleForPackage('admin'), isNull);
    expect(RoleSituationContract.roleForPackage('guest'), isNull);
  });
}

Widget _app(String role) => TeamZoneApp(
  environment: const AppEnvironment(name: 'rel02'),
  locale: const Locale('sv'),
  services: AppServices(identity: _Identity(role), isConfigured: true),
);

class _Identity implements IdentityServices {
  const _Identity(this.role);

  final String role;

  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;

  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();

  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'rel02-profile',
    displayName: 'REL-02',
    locale: 'sv',
  );

  @override
  Future<List<TeamZoneContext>> getContexts() async => [
    TeamZoneContext(
      id: 'rel02-$role',
      clubId: 'rel02-club',
      clubName: 'REL-02-klubben',
      teamId: 'rel02-team',
      teamName: 'REL-02-laget',
      rolePackage: role,
      capabilities: const {'team.read'},
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
