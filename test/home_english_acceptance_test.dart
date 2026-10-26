import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';

import 'package:teamzone_app/src/features/overview/overview_services.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';

void main() {
  testWidgets(
    'English Home localizes system copy and preserves activity names at 390px',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TeamZoneApp(
          environment: const AppEnvironment(name: 'verification'),
          locale: const Locale('en'),
          services: AppServices(
            identity: _Identity(),
            overview: _Home(),
            isConfigured: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Good '), findsOneWidget);
      expect(find.textContaining('LATER TODAY'), findsOneWidget);
      expect(find.text('Svensk träningstitel'), findsNWidgets(2));
      expect(find.text('Upcoming'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Quick actions'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Plan an activity'), findsOneWidget);
      expect(find.text('Manage the team'), findsOneWidget);
      expect(find.text('Open the inbox'), findsOneWidget);
      expect(find.text('Snabbåtgärder'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _Home extends UnconfiguredOverviewServices {
  @override
  Future<MainSurfacesProjection> load({
    required List<String> contextIds,
  }) async => MainSurfacesProjection.fromJson({
    'schema_version': 1,
    'generated_at': DateTime.now().toIso8601String(),
    'sync_cursor': '',
    'contexts': [],
    'actions': [],
    'home': {
      'upcoming_count': 2,
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
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async {
    final now = DateTime.now();
    LeaderHomeEvent event(String id, DateTime start) => LeaderHomeEvent(
      id: id,
      title: 'Svensk träningstitel',
      type: 'training',
      state: 'scheduled',
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
    );
    return LeaderHomeProjection(
      generatedAt: now,
      todayEvents: [event('today', now.add(const Duration(minutes: 1)))],
      upcomingEvents: [event('next', now.add(const Duration(days: 1)))],
      tasks: [],
      planningActions: const [
        LeaderHomeAction(
          kind: 'create_event',
          title: 'Planera aktivitet',
          route: '/calendar',
          enabled: true,
        ),
        LeaderHomeAction(
          kind: 'manage_team',
          title: 'Hantera laget',
          route: '/team',
          enabled: true,
        ),
        LeaderHomeAction(
          kind: 'open_inbox',
          title: 'Öppna inkorgen',
          route: '/inbox',
          enabled: true,
        ),
      ],
    );
  }
}

class _Identity implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'leader',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'P2012',
      rolePackage: 'leader',
      capabilities: {'event.manage'},
    ),
  ];
  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'profile',
    displayName: 'Testare',
    locale: 'sv',
  );
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}
