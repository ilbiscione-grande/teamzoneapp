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
  testWidgets('roster opens member details as its own routed page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(role: 'leader', canView: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Trupp')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Person 00'), findsOneWidget);
    // Plain A–Ö is paged; the default position groups show everyone.
    await tester.tap(find.byKey(const ValueKey('roster-filter')));
    await tester.pumpAndSettle();
    final byName = find.byKey(const ValueKey('roster-sort-name'));
    await tester.ensureVisible(byName);
    await tester.tap(byName);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(byName)).pop();
    await tester.pumpAndSettle();
    final rosterList = find.ancestor(
      of: find.text('Person 00'),
      matching: find.byType(ListView),
    );
    final rosterScroll = tester.state<ScrollableState>(
      find.descendant(of: rosterList, matching: find.byType(Scrollable)),
    );
    rosterScroll.position.jumpTo(rosterScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Visa fler'), findsOneWidget);
    // Active people are shown by default; archived ones via the filter.
    await tester.tap(find.byKey(const ValueKey('roster-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('roster-status-other')));
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byKey(const ValueKey('roster-status-other'))),
    ).pop();
    await tester.pumpAndSettle();
    expect(find.text('Tidigare 00'), findsOneWidget);
    expect(find.text('Person 00'), findsNothing);
    await tester.tap(find.text('Tidigare 00'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('person-profile-title')), findsOneWidget);
    // Member info no longer shows the administrative section.
    expect(find.text('Administrativa uppgifter'), findsNothing);
    expect(find.text('Testimport'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('person-profile-title')), findsNothing);
    expect(find.text('Tidigare 00'), findsOneWidget);
  });

  testWidgets('the squad filters on one birth year, a span, younger, older', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(role: 'leader', canView: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Trupp')),
    );
    await tester.pumpAndSettle();

    Future<void> openFilter() async {
      await tester.tap(find.byKey(const ValueKey('roster-filter')));
      await tester.pumpAndSettle();
    }

    Future<void> closeFilter() async {
      Navigator.of(
        tester.element(find.byKey(const ValueKey('roster-age-mode-all'))),
      ).pop();
      await tester.pumpAndSettle();
    }

    Future<void> mode(String name) async {
      await tester.ensureVisible(find.byKey(ValueKey('roster-age-mode-$name')));
      await tester.tap(find.byKey(ValueKey('roster-age-mode-$name')));
      await tester.pumpAndSettle();
    }

    Future<void> pick(String field, int year) async {
      final finder = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'roster-age-$field-',
            ),
      );
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('$year').last);
      await tester.pumpAndSettle();
    }

    // One year.
    await openFilter();
    await mode('exact');
    await pick('År', 2012);
    await closeFilter();
    expect(find.text('Person 10'), findsOneWidget);
    expect(find.text('Person 00'), findsNothing);
    expect(find.text('Person 20'), findsNothing);

    // A span, here picked newest first.
    await openFilter();
    await mode('range');
    await pick('Från', 2014);
    await pick('Till', 2012);
    await closeFilter();
    expect(find.text('Person 00'), findsNothing);
    expect(find.text('Person 10'), findsOneWidget);

    // Younger than 2012 is born after it; older is born before it.
    await openFilter();
    await mode('younger');
    await pick('År', 2012);
    expect(find.text('Födda 2013 och senare'), findsOneWidget);
    await closeFilter();
    expect(find.text('Person 00'), findsNothing);
    expect(find.text('Person 10'), findsNothing);
    expect(find.text('Person 20'), findsOneWidget);

    await openFilter();
    await mode('older');
    await closeFilter();
    expect(find.text('Person 00'), findsOneWidget);
    expect(find.text('Person 10'), findsNothing);
    expect(find.text('Person 20'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop uses the same routed member details page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(role: 'leader', canView: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Trupp')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Person 00'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('person-profile-title')), findsOneWidget);
    expect(find.text('Översikt'), findsOneWidget);
    expect(find.text('Administrativa uppgifter'), findsNothing);
    expect(find.text('Välj en person'), findsNothing);
  });

  test('member details has a stable canonical deep link', () {
    const id = 'person/with space';
    final route = ProductRouteContract.teamMember(id);
    expect(route, '/team/member/person%2Fwith%20space');
    expect(ProductRouteContract.isCanonical(route), isTrue);
    expect(ProductRouteContract.canonicalInitialLocation(route), route);
  });

  testWidgets('unknown role is fail closed before roster data is shown', (
    tester,
  ) async {
    await tester.pumpWidget(_app(role: 'guest', canView: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Trupp')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Truppen är inte tillgänglig'), findsOneWidget);
    expect(find.text('Person 00'), findsNothing);
  });

  test('role-minimized detail parser omits management for ordinary member', () {
    final minimal = RosterPersonDetails.fromJson(const {
      'club_person_id': 'person',
      'display_name': 'Ada',
      'team_id': 'team',
      'team_name': 'F2012',
      'assignment_state': 'active',
    });
    expect(minimal.hasManagementDetails, isFalse);
    expect(minimal.safeguardingRequired, isNull);
  });

  test('TEAM-03 SQL enforces capability, role and explicit grants', () {
    final sql = File(
      'supabase/migrations/20260824155142_team03_roster_details.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'team.roster.view'"));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains("'player','leader','guardian','club_functionary'"));
    expect(sql, contains("message='role_not_supported'"));
    expect(sql, contains("'management',case when can_manage"));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('grant execute on function'));
  });
}

Widget _app({required String role, required bool canView}) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team03'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: _Identity(role, canView),
    roster: const _Roster(),
    isConfigured: true,
  ),
);

class _Roster extends UnconfiguredRosterServices {
  const _Roster();

  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async => [
    for (var index = 0; index < 35; index++)
      RosterPersonSummary(
        id: 'active-$index',
        displayName: 'Person ${index.toString().padLeft(2, '0')}',
        // Born 2010 (00–09), 2012 (10–19) and 2014 (20–34).
        ageClass: '${index < 10 ? 2010 : (index < 20 ? 2012 : 2014)}',
        teamId: 'team',
        teamName: 'F2012',
        assignmentState: 'active',
        safeguardingRequired: false,
      ),
    for (var index = 0; index < 2; index++)
      RosterPersonSummary(
        id: 'ended-$index',
        displayName: 'Tidigare ${index.toString().padLeft(2, '0')}',
        teamId: 'team',
        teamName: 'F2012',
        assignmentState: 'ended',
        safeguardingRequired: false,
      ),
  ];

  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) async => RosterPersonDetails(
    id: personId,
    displayName: 'Tidigare 00',
    teamId: teamId,
    teamName: 'F2012',
    assignmentState: 'ended',
    provenance: 'Testimport',
  );
}

class _Identity implements IdentityServices {
  const _Identity(this.role, this.canView);
  final String role;
  final bool canView;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: role,
      capabilities: canView
          ? const {'team.read', 'team.roster.view', 'club.memberships.manage'}
          : const {'team.read'},
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
