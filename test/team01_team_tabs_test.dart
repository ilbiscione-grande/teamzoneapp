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
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';
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
          calendar: const _Calendar(),
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
    expect(find.text('Kommande träning'), findsOneWidget);
    expect(find.text('Spelad match'), findsNothing);

    await tester.tap(find.text('Tidigare'));
    await tester.pumpAndSettle();
    expect(find.text('Kommande träning'), findsNothing);
    expect(find.text('Spelad match'), findsOneWidget);
    expect(find.text('Resultat  3–1'), findsOneWidget);

    await tester.tap(find.byTooltip('Filtrera händelser'));
    await tester.pumpAndSettle();
    expect(find.text('Matcher'), findsOneWidget);
    expect(find.text('Träningar'), findsOneWidget);

    await tester.tap(find.text('Matcher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spelad match'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Spelad match'), findsOneWidget);
    expect(
      find.widgetWithText(InputChip, 'Matcher'),
      findsOneWidget,
      reason: 'Back navigation must preserve the selected period and filter.',
    );
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
    expect(shell, contains('if (_router.canPop())'));
    expect(shell, contains('_router.pop()'));
    expect(shell, contains('if (currentPath != ProductRouteContract.home)'));
    expect(shell, contains('_locationHistory.clear()'));
    expect(shell, contains('_router.go(ProductRouteContract.home)'));
    expect(
      roster,
      contains('.push(ProductRouteContract.calendarEvent(event.id))'),
    );
    expect(
      roster,
      contains(r".pushReplacement('/team?tab=${names[index]}')"),
      reason:
          'The selected tab must be the browser-history origin for details.',
    );
    expect(
      calendar,
      contains("void _showDetails(CalendarEventSummary summary)"),
    );
    final resultMigration = File(
      'supabase/migrations/20260912054644_team01_calendar_match_results.sql',
    ).readAsStringSync();
    expect(resultMigration, contains("workspace.state='completed'"));
    expect(resultMigration, contains('projection.score_us'));
    expect(resultMigration, contains('projection.score_opponent'));
  });

  testWidgets('club-only context gets a useful no-team state', (tester) async {
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'team01-club-only'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _ClubOnlyIdentity(),
          roster: const _Roster(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();

    expect(find.text('Du är inte kopplad till något lag'), findsOneWidget);
    expect(find.text('Inställningar'), findsWidgets);
    expect(find.text('Lagöversikten kunde inte laddas'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
  });
}

class _Calendar extends UnconfiguredCalendarServices {
  const _Calendar();

  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async {
    final now = DateTime.now();
    return [
      CalendarEventSummary(
        id: 'upcoming',
        clubId: 'club',
        owningTeamId: 'team',
        teamName: 'Verifieringslaget',
        title: 'Kommande träning',
        type: 'training',
        state: 'scheduled',
        startsAt: now.add(const Duration(days: 2)),
        endsAt: now.add(const Duration(days: 2, hours: 2)),
        allDay: false,
        timezone: 'Europe/Stockholm',
        revision: 1,
      ),
      CalendarEventSummary(
        id: 'previous',
        clubId: 'club',
        owningTeamId: 'team',
        teamName: 'Verifieringslaget',
        title: 'Spelad match',
        type: 'match',
        state: 'completed',
        startsAt: now.subtract(const Duration(days: 2, hours: 2)),
        endsAt: now.subtract(const Duration(days: 2)),
        allDay: false,
        timezone: 'Europe/Stockholm',
        revision: 2,
        matchState: 'completed',
        scoreUs: 3,
        scoreOpponent: 1,
      ),
    ];
  }
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

class _ClubOnlyIdentity extends _Identity {
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'club-context',
      clubId: 'club',
      clubName: 'Verifieringsklubben',
      rolePackage: 'club_functionary',
      capabilities: {'club.board.read', 'club.economy.read'},
    ),
  ];
}
