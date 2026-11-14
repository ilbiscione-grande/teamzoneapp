import 'dart:io';

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
  _Board({this.mandates = const [], this.changes = const []});
  final List<Map<String, Object?>> mandates;
  final List<Map<String, Object?>> changes;
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
        'mandates': mandates,
        'changes': changes,
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

  testWidgets('today\'s board comes first, past mandates fold away', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now().toUtc();
    String day(int days) => now.add(Duration(days: days)).toIso8601String();
    Map<String, Object?> mandate(
      String id,
      String name,
      String office,
      String state,
    ) => {
      'id': id,
      'assignment_id': 'a-$id',
      'name': name,
      'office': office,
      'starts_at': day(-30),
      'ends_at': day(300),
      'state': state,
    };
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'board-forming'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _Identity(),
          board: _Board(
            mandates: [
              mandate('ulf', 'Ulf Karlsson', 'chair', 'revoked'),
              mandate('ola', 'Ola Lövdahl', 'member', 'active'),
              mandate('jonas', 'Jonas Svensson', 'chair', 'active'),
            ],
            changes: [
              {
                'id': 'change',
                'assignment_id': 'a-ulf',
                'mandate_id': 'ulf',
                'name': 'Ulf Karlsson',
                'action': 'revoke',
                'office': 'chair',
                'state': 'applied',
                'created_by': 'profile',
              },
            ],
          ),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.text('Styrelse');
    await tester.ensureVisible(entry.first);
    await tester.tap(entry.first);
    await tester.pumpAndSettle();

    expect(find.text('Sitter i styrelsen idag'), findsOneWidget);
    // The chair first, then the members; Ulf only under Tidigare mandat.
    final chair = tester.getTopLeft(
      find.textContaining('Jonas Svensson').first,
    );
    final member = tester.getTopLeft(find.textContaining('Ola Lövdahl').first);
    expect(chair.dy, lessThan(member.dy));
    expect(find.byKey(const ValueKey('board-mandate-ulf')), findsNothing);
    expect(find.text('Tidigare mandat (1)'), findsOneWidget);
    expect(find.text('Genomförda och avslutade ändringar (1)'), findsOneWidget);
    await tester.tap(find.text('Tidigare mandat (1)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-mandate-ulf')), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  test('the board forms until three with a mandate can sign in', () {
    final migration = File(
      'supabase/migrations/20270315090000_board_forming_counts_accounts.sql',
    ).readAsStringSync();
    // Only mandate holders with an active account in the club count.
    expect(migration, contains("link.state = 'active')) < 3"));
    // A change still pending is applied without approvals meanwhile.
    expect(
      migration,
      contains('if not internal.board_forming(change_row.club_id) and'),
    );
  });
}
