import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

void main() {
  testWidgets('manager creates a roster person with guarded form submission', (
    tester,
  ) async {
    final roster = _Roster();
    await tester.pumpWidget(_app(roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hantera'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lägg till person'));
    await tester.tap(find.text('Lägg till person'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Visningsnamn'),
      '  Ada  Spelare ',
    );
    await _selectBirthYear(tester);
    await tester.tap(find.text('Spara person'));
    await tester.pumpAndSettle();
    expect(roster.createCalls, 1);
    expect(roster.lastName, 'Ada  Spelare');
    expect(find.text('Ada  Spelare'), findsOneWidget);
  });

  testWidgets('dirty roster form warns before it is discarded', (tester) async {
    final roster = _Roster();
    await tester.pumpWidget(_app(roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hantera'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lägg till person'));
    await tester.tap(find.text('Lägg till person'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Visningsnamn'),
      'Ada',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Kasta ändringar?'), findsOneWidget);
  });

  testWidgets('manager edits only the club-owned roster profile', (
    tester,
  ) async {
    final roster = _Roster(seeded: true);
    await tester.pumpWidget(_app(roster));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ada Spelare'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redigera profil'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Visningsnamn'),
      'Ada Uppdaterad',
    );
    await _selectBirthYear(tester);
    await tester.ensureVisible(find.text('Spara person'));
    await tester.tap(find.text('Spara person'));
    await tester.pumpAndSettle();
    expect(roster.updateCalls, 1);
    expect(roster.expectedRevision, 3);
    expect(find.text('Ada Uppdaterad'), findsOneWidget);
  });

  test('TEAM-04 SQL is atomic, tenant-bound and identity-preserving', () {
    final sql = File(
      'supabase/migrations/20260826190142_team04_roster_person_commands.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'club.memberships.manage'"));
    expect(sql, contains('person.revision<>expected_revision'));
    expect(sql, contains("message='stale_revision'"));
    expect(sql, contains('update core.club_people set display_name'));
    expect(sql, isNot(contains('update core.persons set')));
    expect(sql, isNot(contains('update core.profiles set')));
    expect(sql, contains('internal.command_deduplication'));
    expect(sql, contains('audit.command_events'));
    expect(sql, contains('revoke all on function'));
  });

  test('birth date v2 SQL stores exact date but lists only birth year', () {
    final sql = File(
      'supabase/migrations/20260913075009_team04_birth_date_picker.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('add column birth_date date'));
    expect(sql, contains('extract(year from person.birth_date)'));
    expect(sql, contains("'{management,birth_date}'"));
    expect(sql, contains('create_roster_person_v2'));
    expect(sql, contains('update_roster_person_v2'));
    expect(sql, contains('revoke all on function'));
  });

  test('birth data v3 requires only year and keeps exact date optional', () {
    final sql = File(
      'supabase/migrations/20260913080957_team04_partial_birth_date.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('add column birth_year smallint'));
    expect(sql, contains('new_birth_date date'));
    expect(sql, contains('birth_date=new_birth_date'));
    expect(sql, contains('coalesce(person.birth_year::text,person.age_class)'));
    expect(sql, isNot(contains("date_trunc('year'")));
  });

  test('TEAM-04 allows distinct people with the same name and age class', () {
    final sql = File(
      'supabase/migrations/20260912183346_team04_allow_same_name_and_age_class.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains('internal.command_deduplication'));
    expect(sql, contains("command_type='roster.person.create.v1'"));
    expect(sql, isNot(contains('duplicate_roster_person')));
    expect(sql, isNot(contains('pg_advisory_xact_lock')));
    expect(sql, contains('insert into core.persons'));
    expect(sql, contains('update core.club_people set display_name'));
  });

  test('team leaders receive scoped roster management, not club admin', () {
    final sql = File(
      'supabase/migrations/20260831153810_team_leader_scoped_roster_management.sql',
    ).readAsStringSync().toLowerCase();
    expect(sql, contains("'team.roster.manage'"));
    expect(sql, contains("assignment.role_package = 'leader'"));
    expect(sql, contains("required_capability = 'club.memberships.manage'"));
    expect(sql, contains('target_team_id is not null'));
    expect(sql, contains("grant_row.scope_type = 'team'"));
  });

  test('person revision is parsed separately from assignment revision', () {
    final details = RosterPersonDetails.fromJson(const {
      'club_person_id': 'person',
      'display_name': 'Ada',
      'team_id': 'team',
      'team_name': 'F2012',
      'assignment_state': 'active',
      'person_revision': 4,
      'management': {'provenance': 'created', 'assignment_revision': 9},
    });
    expect(details.personRevision, 4);
    expect(details.assignmentRevision, 9);
  });
}

Widget _app(_Roster roster) => TeamZoneApp(
  environment: const AppEnvironment(name: 'team04'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: const _Identity(),
    roster: roster,
    isConfigured: true,
  ),
);

class _Roster extends UnconfiguredRosterServices {
  _Roster({bool seeded = false}) {
    if (seeded) {
      people.add(
        const RosterPersonSummary(
          id: 'person',
          displayName: 'Ada Spelare',
          ageClass: 'F2012',
          teamId: 'team',
          teamName: 'F2012',
          assignmentState: 'active',
          safeguardingRequired: false,
        ),
      );
    }
  }
  final people = <RosterPersonSummary>[];
  int createCalls = 0;
  int updateCalls = 0;
  int? expectedRevision;
  String? lastName;

  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async => List.unmodifiable(people);

  @override
  Future<String> createPerson({
    required String clubId,
    required String teamId,
    required String displayName,
    required int birthYear,
    DateTime? birthDate,
    required DateTime startsAt,
    required String idempotencyKey,
  }) async {
    createCalls++;
    lastName = displayName;
    people.add(
      RosterPersonSummary(
        id: 'person',
        displayName: displayName,
        ageClass: birthYear.toString(),
        teamId: teamId,
        teamName: 'F2012',
        assignmentState: 'active',
        safeguardingRequired: false,
      ),
    );
    return 'person';
  }

  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) async => RosterPersonDetails(
    id: personId,
    displayName: people.single.displayName,
    teamId: teamId,
    teamName: 'F2012',
    assignmentState: 'active',
    ageClass: people.single.ageClass,
    provenance: 'created',
    personRevision: 3,
  );

  @override
  Future<int> updatePerson({
    required String clubId,
    required String teamId,
    required String personId,
    required String displayName,
    required int birthYear,
    DateTime? birthDate,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    updateCalls++;
    this.expectedRevision = expectedRevision;
    people[0] = RosterPersonSummary(
      id: personId,
      displayName: displayName,
      ageClass: birthYear.toString(),
      teamId: teamId,
      teamName: 'F2012',
      assignmentState: 'active',
      safeguardingRequired: false,
    );
    return expectedRevision + 1;
  }
}

Future<void> _selectBirthYear(WidgetTester tester) async {
  final field = tester.widget<DropdownButtonFormField<int>>(
    find.byKey(const Key('roster-birth-year-field')),
  );
  field.onChanged!(2012);
  await tester.pumpAndSettle();
}

class _Identity implements IdentityServices {
  const _Identity();
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'leader',
      capabilities: {'team.read', 'team.roster.view', 'team.roster.manage'},
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
