import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

void main() {
  testWidgets('Laget exposes exactly Overview, Roster and Calendar tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'team01'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _Identity(),
          roster: const _Roster(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    expect(find.text('Översikt'), findsOneWidget);
    expect(find.text('Trupp'), findsOneWidget);
    final calendarTab = find.descendant(
      of: find.byType(TabBar),
      matching: find.text('Kalender'),
    );
    expect(calendarTab, findsOneWidget);
    expect(find.text('Verifieringslaget'), findsWidgets);

    await tester.tap(calendarTab);
    await tester.pumpAndSettle();
    expect(find.text('Kommande'), findsOneWidget);
    expect(find.text('Tidigare'), findsOneWidget);
    expect(find.text('Matcher'), findsOneWidget);
    expect(find.text('Träningar'), findsOneWidget);
  });

  test('team tab query survives canonical deep-link normalization', () {
    expect(
      ProductRouteContract.canonicalInitialLocation('/team?tab=calendar'),
      '/team?tab=calendar',
    );
    final shell = File('lib/src/app/product_shell.dart').readAsStringSync();
    final roster = File(
      'lib/src/features/roster/roster_surface.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/src/features/calendar/calendar_surface.dart',
    ).readAsStringSync();
    expect(shell, contains("queryParameters['tab']"));
    expect(roster, contains("'/calendar?event="));
    expect(shell, contains("queryParameters['event']"));
    expect(calendar, contains('_showDetailsById(eventId)'));
  });
}

class _Roster extends UnconfiguredRosterServices {
  const _Roster();
  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) async =>
      const TeamOverview(
        teamId: 'team',
        clubId: 'club',
        teamName: 'Verifieringslaget',
        clubName: 'Verifieringsklubben',
        leaders: [],
        memberCount: 0,
        canManage: false,
        activeInvitationCount: 0,
        pendingApplicationCount: 0,
      );
}

class _Identity implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'profile',
    displayName: 'Verifierare',
    locale: 'sv',
  );
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Verifieringsklubben',
      teamId: 'team',
      teamName: 'Verifieringslaget',
      rolePackage: 'leader',
      capabilities: {'team.read'},
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
