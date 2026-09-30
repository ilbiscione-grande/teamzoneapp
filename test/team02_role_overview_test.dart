import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets('leader sees picture, requests, next event, latest match', (
    tester,
  ) async {
    await tester.pumpWidget(_app(canManage: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    expect(find.text('F2012'), findsWidgets);
    final requests = find.byKey(const ValueKey('team-overview-requests'));
    expect(requests, findsOneWidget);
    expect(find.text('Aktiva inbjudningar'), findsOneWidget);
    expect(find.text('Väntande ansökningar'), findsOneWidget);
    final next = find.byKey(const ValueKey('team-overview-next-event'));
    await tester.scrollUntilVisible(
      next,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.descendant(of: next, matching: find.text('Träning tisdag')),
      findsOneWidget,
    );
    // Order: requests above the next event.
    expect(
      tester.getTopLeft(requests).dy,
      lessThan(tester.getTopLeft(next).dy),
    );
    final match = find.byKey(const ValueKey('team-overview-last-match'));
    await tester.scrollUntilVisible(
      match,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    // The latest match wins over an older one; cancelled ones are skipped.
    expect(
      find.descendant(of: match, matching: find.text('Mot Bergby')),
      findsOneWidget,
    );
    expect(find.text('Inställd match'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Ada Ledare'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Redigera lagprofil'), findsOneWidget);
  });

  testWidgets('requests card is hidden when nothing is waiting', (
    tester,
  ) async {
    await tester.pumpWidget(_app(canManage: true, openRequests: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-overview-requests')), findsNothing);
    expect(find.text('Nästa händelse'), findsOneWidget);
  });

  testWidgets('player never sees administrative team needs', (tester) async {
    await tester.pumpWidget(_app(canManage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    expect(find.text('F2012'), findsWidgets);
    expect(find.byKey(const ValueKey('team-overview-requests')), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Ada Ledare'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Aktiva inbjudningar'), findsNothing);
    expect(find.text('Väntande ansökningar'), findsNothing);
    expect(find.text('Redigera lagprofil'), findsNothing);
  });

  testWidgets('leader chooses a private upload instead of entering an URL', (
    tester,
  ) async {
    await tester.pumpWidget(_app(canManage: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Redigera lagprofil'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Redigera lagprofil'));
    await tester.pumpAndSettle();

    expect(find.text('Lagbild'), findsOneWidget);
    expect(find.text('Välj lagbild'), findsOneWidget);
    expect(find.text('Lagbildens HTTPS-adress'), findsNothing);
    expect(find.textContaining('Originalet lagras privat'), findsOneWidget);
  });

  testWidgets('team profile editor is full screen on phones and saves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final roster = _Roster();
    await tester.pumpWidget(_app(canManage: true, roster: roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Redigera lagprofil'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Redigera lagprofil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redigera lagprofil'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Dialog)).width, 390);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Om laget')),
      findsOneWidget,
    );
    // Only club administrators change the sport; leaders see it read-only.
    expect(find.byKey(const ValueKey('team-sport-readonly')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-sport-handball')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('team-type')), 'Flicklag');
    await tester.enterText(
      find.byKey(const ValueKey('team-age-class')),
      'F2012',
    );
    await tester.tap(find.byKey(const ValueKey('save-team-profile')));
    await tester.pumpAndSettle();
    expect(roster.saved, ('Flicklag', 'F2012'));
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('club administrators can change the team sport', (
    tester,
  ) async {
    final roster = _Roster(canSetSport: true);
    await tester.pumpWidget(_app(canManage: true, roster: roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Redigera lagprofil'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Redigera lagprofil'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-sport-readonly')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('team-sport-handball')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-sport-handball')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-team-profile')));
    await tester.pumpAndSettle();
    expect(roster.sport, 'handball');
    expect(tester.takeException(), isNull);
  });

  test('TEAM-02 projection minimizes admin data behind capability', () {
    final sql = File(
      'supabase/migrations/20260824151510_team02_role_based_overview.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('create table core.team_profiles'));
    expect(sql, contains('internal.actor_has_club_access'));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains("'active_invitation_count',case when can_manage"));
    expect(sql, contains("'pending_application_count',case when can_manage"));
    expect(sql, contains("else 0 end"));
    expect(
      sql,
      contains(
        'revoke all on table core.team_profiles from public,anon,authenticated',
      ),
    );
    expect(
      sql,
      isNot(contains('grant select on core.membership_applications')),
    );
  });

  test('TEAM-02 profile editing is capability scoped and revision safe', () {
    final sql = File(
      'supabase/migrations/20260901100421_team02_team_profile_edit.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains('expected_revision'));
    expect(sql, contains("'team.profile.update.v1'"));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains("normalized_image!~'^https://'"));
    expect(sql, contains('revoke all on function'));
  });

  test('TEAM-02 permits a team-scoped leader without club-wide access', () {
    final sql = File(
      'supabase/migrations/20260901104226_team02_allow_team_leader_profile_edit.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'team.roster.manage'"));
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains('team_row.id'));
    expect(sql, contains('revoke all on function'));
  });

  test('TEAM-02 image upload is private, scoped and separately authorized', () {
    final sql = File(
      'supabase/migrations/20260912134327_team02_private_team_image_upload.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'team-profile-images','team-profile-images',false"));
    expect(
      sql,
      contains(
        'alter table core.team_profile_images enable row level security',
      ),
    );
    expect(sql, contains('revoke all on table core.team_profile_images'));
    expect(sql, contains('internal.actor_can_upload_team_profile_image'));
    expect(sql, contains("image.state='staged'"));
    expect(sql, contains("'team.roster.manage'"));
    expect(sql, contains('api.authorize_team_profile_image'));
    expect(sql, contains("'expires_in_seconds',3600"));
    expect(sql, isNot(contains('public=true')));
    final readPolicy = File(
      'supabase/migrations/20260912140450_team02_team_image_signed_read_policy.sql',
    ).readAsStringSync().toLowerCase();
    expect(readPolicy, contains('for select to authenticated'));
    expect(readPolicy, contains("image.state='active'"));
    expect(readPolicy, contains('profile.image_asset_id=image.id'));
    expect(
      readPolicy,
      contains('internal.actor_has_club_access(image.club_id)'),
    );
  });
}

Widget _app({
  required bool canManage,
  bool openRequests = true,
  _Roster? roster,
}) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team02'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: _Identity(canManage),
    roster: roster ?? _Roster(openRequests: openRequests),
    calendar: _Calendar(),
    isConfigured: true,
  ),
);

class _Calendar extends UnconfiguredCalendarServices {
  CalendarEventSummary _event(
    String id,
    String title,
    String type,
    Duration fromNow, {
    String state = 'scheduled',
    String? matchState,
  }) {
    final start = DateTime.now().add(fromNow).toUtc();
    return CalendarEventSummary(
      id: id,
      clubId: 'club',
      owningTeamId: 'team',
      teamName: 'F2012',
      title: title,
      type: type,
      state: state,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1, minutes: 30)),
      allDay: false,
      timezone: 'Europe/Stockholm',
      revision: 1,
      matchState: matchState,
    );
  }

  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async => [
    _event('m-old', 'Mot Alby', 'match', const Duration(days: -20)),
    _event('m-new', 'Mot Bergby', 'match', const Duration(days: -6)),
    _event(
      'm-cancel',
      'Inställd match',
      'match',
      const Duration(days: -2),
      state: 'cancelled',
    ),
    _event('t-later', 'Träning torsdag', 'training', const Duration(days: 4)),
    _event('t-next', 'Träning tisdag', 'training', const Duration(days: 2)),
  ];
}

class _Roster extends UnconfiguredRosterServices {
  _Roster({this.openRequests = true, this.canSetSport = false});
  final bool openRequests;
  final bool canSetSport;
  (String, String)? saved;
  String? sport;

  @override
  Future<TeamRoles> listTeamRoles({
    required String clubId,
    required String teamId,
  }) async => TeamRoles(canManage: true, canSetSport: canSetSport, roles: const []);

  @override
  Future<void> setTeamSport({
    required String clubId,
    required String teamId,
    required String sport,
    required String idempotencyKey,
  }) async {
    this.sport = sport;
  }

  @override
  Future<int> updateTeamProfile({
    required String teamId,
    required String teamType,
    required String ageClass,
    required String summary,
    required String imageAction,
    String? stagedImageId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    saved = (teamType, ageClass);
    return expectedRevision + 1;
  }

  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) async =>
      TeamOverview(
        teamId: 'team',
        clubId: 'club',
        teamName: 'F2012',
        clubName: 'Testklubben',
        teamType: 'Flicklag',
        ageClass: '2012',
        summary: 'Lagets officiella interna presentation.',
        leaders: [
          TeamLeaderSummary(personId: 'leader', displayName: 'Ada Ledare'),
        ],
        memberCount: 18,
        canManage: true,
        activeInvitationCount: openRequests ? 2 : 0,
        pendingApplicationCount: openRequests ? 3 : 0,
      );

  @override
  Future<TeamProfileEditData> getTeamProfileEdit({
    required String teamId,
  }) async => const TeamProfileEditData(teamId: 'team', revision: 1);
}

class _Identity implements IdentityServices {
  const _Identity(this.canManage);
  final bool canManage;
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
      rolePackage: canManage ? 'leader' : 'player',
      capabilities: canManage
          ? const {'team.read', 'team.roster.manage'}
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
