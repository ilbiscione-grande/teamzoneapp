import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/board/board_models.dart';
import 'package:teamzone_app/src/features/board/board_services.dart';

// A club without a board: members and teams open Styrelse and register the
// first mandates at once.

class _Identity implements IdentityServices {
  const _Identity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Ulf', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context-club',
      clubId: 'club',
      clubName: 'IF Eksjö Fotboll',
      rolePackage: 'club_functionary',
      capabilities: {'club.read', 'club.memberships.manage'},
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

class _Board extends UnconfiguredBoardServices {
  @override
  Future<BoardOverview> getOverview(String clubId) async =>
      BoardOverview.fromJson({
        'forming': true,
        'can_register': true,
        'assignments': [
          {
            'id': 'context-club',
            'name': 'Ulf Karlsson',
            'role_package': 'club_functionary',
          },
        ],
        'mandates': const [],
        'changes': const [],
      });
}

void main() {
  testWidgets('members and teams form the first board', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'board-forming'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _Identity(),
          board: _Board(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.text('Styrelse');
    expect(entry, findsWidgets);
    await tester.ensureVisible(entry.first);
    await tester.tap(entry.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-forming')), findsOneWidget);
    expect(find.text('Styrelsen bildas'), findsOneWidget);
    expect(find.byKey(const ValueKey('board-new-mandate')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-new-mandate')));
    await tester.pumpAndSettle();
    expect(find.text('Registrera styrelsemandat'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
