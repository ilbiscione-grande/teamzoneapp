import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import 'package:teamzone_app/src/features/overview/overview_services.dart';

// A club functionary's Home: messages from the public pages waiting to be
// handled are under Att hantera and open the inbox on its Klubbsajt tab.

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
      capabilities: {'club.read'},
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

class _Messaging extends UnconfiguredMessagingServices {
  Map<String, dynamic> _summary(String id, bool handled) => {
    'id': id,
    'club_name': 'IF Eksjö Fotboll',
    'team_name': null,
    'sender_name': id == 't1' ? 'Ada Andersson' : 'Bo Berg',
    'sender_email': 'ada@example.se',
    'subject': id == 't1' ? 'Ny spelare' : 'Sponsring',
    'preview': 'Hej!',
    'last_activity_at': '2026-11-12T18:37:00Z',
    'expires_at': '2026-12-12T18:37:00Z',
    'handled': handled,
    'unread': !handled,
  };

  @override
  Future<List<ContactThreadSummary>> listContactThreads() async => [
    ContactThreadSummary.fromJson(_summary('t1', false)),
    ContactThreadSummary.fromJson(_summary('t2', true)),
  ];
}

class _Overview extends UnconfiguredOverviewServices
    implements ClubHomeServices {
  @override
  Future<MainSurfacesProjection> load({
    required List<String> contextIds,
  }) async => MainSurfacesProjection.fromJson({
    'schema_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'sync_cursor': '',
    'contexts': const [],
    'actions': const [],
    'home': {
      'upcoming_count': 0,
      'pending_callup_count': 0,
      'next_event': null,
    },
    'inbox': {'messages_available': false, 'pending_notification_count': 0},
    'statistics': {
      'present': 0,
      'late': 0,
      'partial': 0,
      'absent': 0,
      'unknown': 0,
    },
  });

  @override
  Future<ClubHome> loadClubHome(String contextId) async => ClubHome.fromJson({
    'club_id': 'club',
    'can_announce': false,
    'teams': const [],
  });
}

void main() {
  testWidgets('waiting site messages open the Klubbsajt tab', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'club-site'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: const _Identity(),
          messaging: _Messaging(),
          overview: _Overview(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Att hantera'), findsOneWidget);
    final tile = find.byKey(const ValueKey('club-home-site-messages'));
    expect(tile, findsOneWidget);
    expect(find.text('1 att hantera'), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    // The inbox opens on Klubbsajt, with the message to handle.
    expect(find.textContaining('Ada Andersson · Ny spelare'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
