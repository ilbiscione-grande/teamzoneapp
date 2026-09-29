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
  testWidgets('player picks general and detailed positions plus own label', (
    tester,
  ) async {
    final roster = _Roster(
      roles: [
        const TeamRole(personId: 'ada', name: 'Ada Spelare', role: 'player'),
      ],
      people: [
        const RosterPersonSummary(
          id: 'ada',
          displayName: 'Ada Spelare',
          teamId: 'team',
          teamName: 'F2012',
          assignmentState: 'active',
          safeguardingRequired: false,
        ),
      ],
    );
    await _openRoster(tester, roster);
    await tester.tap(find.text('Ada Spelare'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('person-team-details')),
    );
    expect(find.text('Position'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('person-team-details')));
    await tester.pumpAndSettle();
    // A player is offered positions, not leader titles.
    expect(find.widgetWithText(FilterChip, 'Huvudtränare'), findsNothing);
    expect(find.textContaining('Fotboll'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Försvarare'));
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Mittback'));
    await tester.tap(find.widgetWithText(FilterChip, 'Mittback'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Egen position'),
      'Libero',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-team-person-details')));
    await tester.pumpAndSettle();
    expect(roster.roles.single.positions, ['centre_back', 'defender']);
    expect(roster.roles.single.customPositions, ['Libero']);
    expect(roster.roles.single.titles, isEmpty);
    // The general position is implied by the detailed one.
    expect(find.text('Mittback · Libero'), findsOneWidget);
    expect(roster.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save retains selections and retries same command', (
    tester,
  ) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Thomas Emilson',
          role: 'leader',
          isSelf: true,
        ),
      ],
    )..failWith = StateError('offline');
    await _openRoster(tester, roster);
    await _openRolesSheet(tester);
    await tester.tap(find.text('Thomas Emilson (du)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Huvudtränare'));
    await tester.tap(find.byKey(const ValueKey('save-team-person-details')));
    await tester.pumpAndSettle();
    expect(roster.roles.single.titles, isEmpty);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Huvudtränare'))
          .selected,
      isTrue,
    );
    roster.failWith = null;
    await tester.tap(find.byKey(const ValueKey('save-team-person-details')));
    await tester.pumpAndSettle();
    expect(roster.detailKeys, hasLength(2));
    expect(roster.detailKeys.first, roster.detailKeys.last);
    expect(roster.roles.single.titles, ['head_coach']);
  });

  testWidgets('own leader sets titles and an own title without positions', (
    tester,
  ) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Thomas Emilson',
          role: 'leader',
          isSelf: true,
        ),
      ],
    );
    await _openRoster(tester, roster);
    await _openRolesSheet(tester);
    await tester.tap(find.text('Thomas Emilson (du)').last);
    await tester.pumpAndSettle();
    expect(find.text('Titel'), findsWidgets);
    expect(find.widgetWithText(FilterChip, 'Mittback'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'Huvudtränare'));
    await tester.tap(find.widgetWithText(FilterChip, 'Kontaktperson'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Egen titel'),
      'Ungdomsansvarig',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-team-person-details')));
    await tester.pumpAndSettle();
    expect(roster.roles.single.titles, ['contact_person', 'head_coach']);
    expect(roster.roles.single.customTitles, ['Ungdomsansvarig']);
    expect(roster.roles.single.positions, isEmpty);
    expect(roster.calls, isEmpty);
    expect(
      find.text('Kontaktperson · Huvudtränare · Ungdomsansvarig'),
      findsOneWidget,
    );
    await tester.tap(find.text('Thomas Emilson (du)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Huvudtränare'));
    await tester.tap(find.widgetWithText(FilterChip, 'Kontaktperson'));
    await tester.ensureVisible(find.byTooltip('Ta bort Ungdomsansvarig'));
    await tester.tap(find.byTooltip('Ta bort Ungdomsansvarig'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-team-person-details')));
    await tester.pumpAndSettle();
    expect(roster.roles.single.titles, isEmpty);
    expect(roster.roles.single.customTitles, isEmpty);
    expect(roster.roles.single.detailsRevision, 2);
    expect(find.text('Välj titel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel descriptive edits writes nothing', (tester) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Thomas Emilson',
          role: 'leader',
          isSelf: true,
        ),
      ],
    );
    await _openRoster(tester, roster);
    await _openRolesSheet(tester);
    await tester.tap(find.text('Thomas Emilson (du)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Lagledare'));
    await tester.tap(find.text('Avbryt'));
    await tester.pumpAndSettle();
    expect(roster.roles.single.detailsRevision, 0);
    expect(roster.roles.single.titles, isEmpty);
  });

  testWidgets('handball team offers handball positions', (tester) async {
    final roster = _Roster(
      sport: 'handball',
      roles: [
        const TeamRole(personId: 'ada', name: 'Ada Spelare', role: 'player'),
      ],
      people: [
        const RosterPersonSummary(
          id: 'ada',
          displayName: 'Ada Spelare',
          teamId: 'team',
          teamName: 'F2012',
          assignmentState: 'active',
          safeguardingRequired: false,
        ),
      ],
    );
    await _openRoster(tester, roster);
    await tester.tap(find.text('Ada Spelare'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('person-team-details')),
    );
    await tester.tap(find.byKey(const ValueKey('person-team-details')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Handboll'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Mittback'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Vänstersexa'));
    await tester.tap(find.widgetWithText(FilterChip, 'Vänstersexa'));
    await tester.tap(find.byKey(const ValueKey('save-team-person-details')));
    await tester.pumpAndSettle();
    expect(roster.roles.single.positions, ['hb_left_wing']);
    expect(find.text('Vänstersexa'), findsOneWidget);
  });

  testWidgets('team overview shows leader titles', (tester) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Thomas Emilson',
          role: 'leader',
          titles: ['head_coach'],
          customTitles: ['Ungdomsansvarig'],
        ),
      ],
    );
    await _openRoster(tester, roster);
    await tester.tap(find.text('Översikt'));
    await tester.pumpAndSettle();
    expect(
      find.text('Thomas Emilson · Huvudtränare · Ungdomsansvarig'),
      findsOneWidget,
    );
  });

  testWidgets('new team shows creator and adds self as leader', (tester) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Thomas Emilson',
          role: 'club_functionary',
          isSelf: true,
        ),
      ],
      candidates: [
        const LeaderCandidate(
          personId: 'me',
          name: 'Thomas Emilson',
          context: 'Klubben',
          isSelf: true,
        ),
        const LeaderCandidate(
          personId: 'lars',
          name: 'Lars Ledare',
          context: 'F2011',
        ),
      ],
    );
    await _openRoster(tester, roster);
    // No players yet, but the leader is listed in the squad.
    expect(find.text('LEDARE (1)'), findsOneWidget);
    expect(find.text('Inga spelare i truppen ännu.'), findsOneWidget);
    expect(find.text('Thomas Emilson (du)'), findsOneWidget);
    await _openRolesSheet(tester);
    expect(find.text('Klubbfunktionär'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('add-team-leader')));
    await tester.pumpAndSettle();
    expect(find.text('KLUBBENS LEDARE'), findsOneWidget);
    // Yourself first, then other club leaders.
    expect(
      tester.getTopLeft(find.text('Thomas Emilson (du)').last).dy,
      lessThan(tester.getTopLeft(find.text('Lars Ledare')).dy),
    );
    await tester.tap(find.text('Thomas Emilson (du)').last);
    await tester.pumpAndSettle();
    expect(roster.calls.single, ('me', null, 'leader'));
    expect(find.text('Thomas Emilson är nu ledare i laget.'), findsOneWidget);
    expect(find.text('Klubbfunktionär · Ledare'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing club leader is added and can be changed', (
    tester,
  ) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Thomas Emilson',
          role: 'leader',
          isSelf: true,
        ),
      ],
      candidates: [
        const LeaderCandidate(
          personId: 'lars',
          name: 'Lars Ledare',
          context: 'F2011',
        ),
      ],
    );
    await _openRoster(tester, roster);
    await tester.tap(find.byTooltip('Hantera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ledare och roller').last);
    await tester.pumpAndSettle();
    // Your own leader role cannot be changed; no role menu on your row.
    expect(find.byTooltip('Ändra roll'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-team-leader')));
    await tester.pumpAndSettle();
    expect(find.text('F2011'), findsOneWidget);
    await tester.tap(find.text('Lars Ledare'));
    await tester.pumpAndSettle();
    expect(roster.calls.last, ('lars', null, 'leader'));

    await tester.tap(find.byTooltip('Ändra roll').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ändra till spelare'));
    await tester.pumpAndSettle();
    expect(roster.calls.last, ('lars', 'leader', 'player'));
    expect(find.text('Lars Ledare är nu spelare i laget.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('squad player gets a leader role from their profile', (
    tester,
  ) async {
    final roster = _Roster(
      roles: [
        const TeamRole(personId: 'ada', name: 'Ada Spelare', role: 'player'),
      ],
      people: [
        const RosterPersonSummary(
          id: 'ada',
          displayName: 'Ada Spelare',
          teamId: 'team',
          teamName: 'F2012',
          assignmentState: 'active',
          safeguardingRequired: false,
        ),
      ],
    );
    await _openRoster(tester, roster);
    await tester.tap(find.text('Ada Spelare'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('person-team-role')));
    expect(find.text('Roll i laget'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('person-team-role')));
    await tester.pumpAndSettle();
    expect(find.text('Lägg till ledarroll'), findsOneWidget);
    await tester.tap(find.text('Byt från spelare till ledare'));
    await tester.pumpAndSettle();
    expect(roster.calls.single, ('ada', 'player', 'leader'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('refused own-role change shows the reason', (tester) async {
    final roster = _Roster(
      roles: [
        const TeamRole(personId: 'ada', name: 'Ada Spelare', role: 'player'),
      ],
      people: [
        const RosterPersonSummary(
          id: 'ada',
          displayName: 'Ada Spelare',
          teamId: 'team',
          teamName: 'F2012',
          assignmentState: 'active',
          safeguardingRequired: false,
        ),
      ],
    )..failWith = const TeamRoleException('home_in_other_team');
    await _openRoster(tester, roster);
    await tester.tap(find.text('Ada Spelare'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('person-team-role')));
    await tester.tap(find.byKey(const ValueKey('person-team-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lägg till ledarroll'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Personen spelar i ett annat lag. Använd Flytta eller Representation.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('head coach applies the template the title suggests', (
    tester,
  ) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Hanna Huvudtränare',
          role: 'leader',
          isSelf: true,
          permissions: _all,
          permissionTemplate: 'head_coach',
        ),
        const TeamRole(
          personId: 'mats',
          name: 'Mats Lagledare',
          role: 'leader',
          titles: ['team_manager'],
          permissions: _standard,
        ),
      ],
    )..grantable = _all;
    await _openRoster(tester, roster);
    await _openRolesSheet(tester);
    expect(find.text('Behörighet: Huvudtränare'), findsOneWidget);
    expect(find.text('Behörighet: Ledare (standard)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leader-permissions-mats')));
    await tester.pumpAndSettle();
    expect(find.text('Titeln föreslår mallen Lagledare.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('apply-suggested-template')));
    await tester.pumpAndSettle();
    await _showPermission(tester, 'training.plan');
    final training = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('permission-training.plan')),
    );
    expect(
      training.value,
      isFalse,
      reason: 'team manager has no training plan',
    );
    await tester.tap(find.byKey(const ValueKey('save-permissions')));
    await tester.pumpAndSettle();
    final call = roster.permissionCalls.single;
    expect(call.$1, 'mats');
    expect(call.$2.toSet(), _teamManager.toSet());
    expect(call.$3.toSet(), _standard.toSet());
    expect(call.$4, 'team_manager');
    expect(
      find.text('Behörigheterna sparades för Mats Lagledare.'),
      findsOneWidget,
    );
    expect(find.text('Behörighet: Lagledare'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permissions you lack and your own leader right are locked', (
    tester,
  ) async {
    const mine = [
      'event.attendance.manage',
      'event.logistics',
      'match.live',
      'match.plan',
      'team.leaders.manage',
      'training.plan',
    ];
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Anna Assistent',
          role: 'leader',
          isSelf: true,
          permissions: mine,
          permissionTemplate: 'custom',
        ),
      ],
    )..grantable = mine;
    await _openRoster(tester, roster);
    await _openRolesSheet(tester);
    await tester.tap(find.byKey(const ValueKey('leader-permissions-me')));
    await tester.pumpAndSettle();
    Future<SwitchListTile> tile(String capability) async {
      await _showPermission(tester, capability);
      return tester.widget<SwitchListTile>(
        find.byKey(ValueKey('permission-$capability')),
      );
    }

    expect((await tile('team.leaders.manage')).onChanged, isNull);
    expect((await tile('team.leaders.manage')).value, isTrue);
    expect((await tile('publication.manage')).onChanged, isNull);
    expect((await tile('training.plan')).onChanged, isNotNull);
    expect(find.text('Anpassad – skiljer sig från mallarna'), findsOneWidget);
    await _showPermission(tester, 'training.plan');
    await tester.tap(find.byKey(const ValueKey('permission-training.plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-permissions')));
    await tester.pumpAndSettle();
    expect(roster.permissionCalls.single.$2, isNot(contains('training.plan')));
    expect(roster.permissionCalls.single.$2, contains('team.leaders.manage'));
  });

  testWidgets('refused permission change explains why', (tester) async {
    final roster =
        _Roster(
            roles: [
              const TeamRole(
                personId: 'mats',
                name: 'Mats Lagledare',
                role: 'leader',
                permissions: _standard,
              ),
            ],
          )
          ..grantable = _all
          ..failWith = const TeamRoleException('stale_permissions');
    await _openRoster(tester, roster);
    await _openRolesSheet(tester);
    await tester.tap(find.byKey(const ValueKey('leader-permissions-mats')));
    await tester.pumpAndSettle();
    await _showPermission(tester, 'publication.manage');
    await tester.tap(
      find.byKey(const ValueKey('permission-publication.manage')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-permissions')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Behörigheterna har ändrats av någon annan. Stäng och öppna igen.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('squad lists leaders grouped below the players', (tester) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'lars',
          name: 'Lars Ledare',
          role: 'leader',
          titles: ['head_coach'],
        ),
        const TeamRole(personId: 'ada', name: 'Ada Spelare', role: 'player'),
      ],
      people: [
        const RosterPersonSummary(
          id: 'ada',
          displayName: 'Ada Spelare',
          teamId: 'team',
          teamName: 'F2012',
          assignmentState: 'active',
          safeguardingRequired: false,
        ),
      ],
    );
    await _openRoster(tester, roster);
    expect(find.text('SPELARE (1)'), findsOneWidget);
    expect(find.text('LEDARE (1)'), findsOneWidget);
    expect(find.text('Ledare · Huvudtränare'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Ada Spelare')).dy,
      lessThan(tester.getTopLeft(find.text('Lars Ledare')).dy),
    );
    // Search applies to leaders as well.
    await tester.enterText(find.byType(SearchBar), 'Ada');
    await tester.pumpAndSettle();
    expect(find.text('Lars Ledare'), findsNothing);
    await tester.enterText(find.byType(SearchBar), 'Lars');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('roster-leader-lars')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('roster-leader-lars')));
    await tester.pumpAndSettle();
    expect(find.text('Medlemsuppgifter'), findsOneWidget);
    expect(find.text('Lars Ledare'), findsOneWidget);
    expect(find.byKey(const ValueKey('person-profile-roles')), findsOneWidget);
    // Player-only statistics are not shown for a leader.
    expect(find.text('Träningsnärvaro'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leader profile manages role, title and permissions', (
    tester,
  ) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Hanna Huvudtränare',
          role: 'leader',
          isSelf: true,
          permissions: _all,
          permissionTemplate: 'head_coach',
        ),
        const TeamRole(
          personId: 'mats',
          name: 'Mats Lagledare',
          role: 'leader',
          titles: ['team_manager'],
          permissions: _standard,
        ),
      ],
    )..grantable = _all;
    await _openRoster(tester, roster);
    await tester.tap(find.byKey(const ValueKey('roster-leader-mats')));
    await tester.pumpAndSettle();
    expect(find.text('Lagledare'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('person-permissions')),
    );
    expect(find.text('Ledare (standard)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('person-permissions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-suggested-template')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-permissions')));
    await tester.pumpAndSettle();
    expect(roster.permissionCalls.single.$4, 'team_manager');
    expect(
      find.text('Behörigheterna sparades för Mats Lagledare.'),
      findsOneWidget,
    );
    // Removing the only role here leaves the team, so the profile closes.
    await tester.ensureVisible(find.byKey(const ValueKey('person-team-role')));
    await tester.tap(find.byKey(const ValueKey('person-team-role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ta bort ledarrollen'));
    await tester.pumpAndSettle();
    expect(roster.calls.last, ('mats', 'leader', null));
    expect(find.text('Medlemsuppgifter'), findsNothing);
    expect(find.byKey(const ValueKey('roster-leader-mats')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer profile opens your own team profile', (tester) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Thomas Emilson',
          role: 'leader',
          isSelf: true,
        ),
      ],
    );
    await _openRoster(tester, roster);
    await tester.tap(find.byTooltip('Öppna menyn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-own-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Medlemsuppgifter'), findsOneWidget);
    expect(find.text('Thomas Emilson (du)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('your title replaces the leader role in the menu', (
    tester,
  ) async {
    await _openRoster(tester, _Roster(), identity: const _TitledIdentity());
    await tester.tap(find.byTooltip('Öppna menyn'));
    await tester.pumpAndSettle();
    expect(find.text('Huvudtränare · Klubbfunktionär'), findsOneWidget);
    expect(find.textContaining('Ledare'), findsNothing);
  });

  testWidgets('empty filter keeps the filter chips', (tester) async {
    final roster = _Roster(
      roles: [
        const TeamRole(personId: 'lars', name: 'Lars Ledare', role: 'leader'),
      ],
    );
    await _openRoster(tester, roster);
    await tester.tap(find.widgetWithText(FilterChip, 'Tidigare'));
    await tester.pumpAndSettle();
    expect(find.text('Inga matchande personer'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Alla'));
    await tester.pumpAndSettle();
    expect(find.text('Lars Ledare'), findsOneWidget);
  });

  testWidgets('a functionary who also leads is listed once', (tester) async {
    final roster = _Roster(
      roles: [
        const TeamRole(
          personId: 'me',
          name: 'Coach Emilson',
          role: 'leader',
          isSelf: true,
          permissions: _standard,
        ),
        const TeamRole(
          personId: 'me',
          name: 'Coach Emilson',
          role: 'club_functionary',
          isSelf: true,
        ),
      ],
    )..grantable = _all;
    await _openRoster(tester, roster);
    await _openRolesSheet(tester);
    expect(find.byKey(const ValueKey('leader-me')), findsOneWidget);
    expect(find.text('Klubbfunktionär · Ledare'), findsOneWidget);
    expect(
      find.text('Behörighet: Klubbfunktionär – hela klubben'),
      findsOneWidget,
    );
  });

  testWidgets('read-only roster viewer sees leaders without actions', (
    tester,
  ) async {
    final roster = _Roster(
      canManage: false,
      roles: [
        const TeamRole(personId: 'lars', name: 'Lars Ledare', role: 'leader'),
      ],
    );
    await _openRoster(tester, roster, identity: const _ViewerIdentity());
    expect(find.byTooltip('Hantera'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('roster-leader-lars')));
    await tester.pumpAndSettle();
    expect(find.text('Lars Ledare'), findsOneWidget);
    expect(find.text('Roll i laget'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('person-team-role')));
    await tester.pumpAndSettle();
    expect(find.text('Lägg till ledarroll'), findsNothing);
    expect(find.text('Redigera profil'), findsNothing);
  });
}

Future<void> _openRolesSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Hantera'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ledare och roller').last);
  await tester.pumpAndSettle();
}

Future<void> _showPermission(WidgetTester tester, String capability) =>
    tester.scrollUntilVisible(
      find.byKey(ValueKey('permission-$capability')),
      120,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .last,
    );

Future<void> _openRoster(
  WidgetTester tester,
  _Roster roster, {
  IdentityServices identity = const _Identity(),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TeamZoneApp(
      environment: const AppEnvironment(name: 'team09'),
      locale: const Locale('sv'),
      services: AppServices(
        identity: identity,
        roster: roster,
        isConfigured: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Laget'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Trupp'));
  await tester.pumpAndSettle();
}

class _Roster extends UnconfiguredRosterServices {
  final detailKeys = <String>[];
  List<String> grantable = const [];
  final permissionCalls = <(String, List<String>, List<String>, String?)>[];

  @override
  Future<void> setLeaderPermissions({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> capabilities,
    required List<String> expected,
    String? template,
    required String idempotencyKey,
  }) async {
    permissionCalls.add((personId, capabilities, expected, template));
    if (failWith != null) throw failWith!;
    roles = [
      for (final r in roles)
        if (r.personId != personId || r.role != 'leader')
          r
        else
          TeamRole(
            personId: r.personId,
            name: r.name,
            role: r.role,
            isSelf: r.isSelf,
            titles: r.titles,
            permissions: capabilities,
            permissionTemplate: template,
          ),
    ];
  }

  @override
  Future<int> setTeamPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> titles,
    required List<String> positions,
    required List<String> customTitles,
    required List<String> customPositions,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    detailKeys.add(idempotencyKey);
    if (failWith != null) throw failWith!;
    roles = [
      for (final r in roles)
        if (r.personId != personId)
          r
        else
          TeamRole(
            personId: r.personId,
            name: r.name,
            role: r.role,
            isSelf: r.isSelf,
            titles: titles,
            positions: positions,
            customTitles: customTitles,
            customPositions: customPositions,
            detailsRevision: expectedRevision + 1,
          ),
    ];
    return expectedRevision + 1;
  }

  _Roster({
    List<TeamRole> roles = const [],
    this.candidates = const [],
    this.people = const [],
    this.canManage = true,
    this.sport = 'football',
  }) : roles = [...roles];

  final String sport;

  static const _catalogs = {
    'football': [
      SportPosition(key: 'goalkeeper', level: 'general'),
      SportPosition(key: 'defender', level: 'general'),
      SportPosition(key: 'midfielder', level: 'general'),
      SportPosition(key: 'forward', level: 'general'),
      SportPosition(key: 'centre_back', level: 'detailed', parent: 'defender'),
      SportPosition(key: 'left_back', level: 'detailed', parent: 'defender'),
      SportPosition(key: 'striker', level: 'detailed', parent: 'forward'),
    ],
    'handball': [
      SportPosition(key: 'goalkeeper', level: 'general'),
      SportPosition(key: 'hb_backcourt', level: 'general'),
      SportPosition(key: 'hb_wing', level: 'general'),
      SportPosition(key: 'hb_pivot', level: 'general'),
      SportPosition(
        key: 'hb_left_back',
        level: 'detailed',
        parent: 'hb_backcourt',
      ),
      SportPosition(key: 'hb_left_wing', level: 'detailed', parent: 'hb_wing'),
      SportPosition(key: 'hb_right_wing', level: 'detailed', parent: 'hb_wing'),
    ],
  };

  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) async =>
      TeamOverview(
        teamId: teamId,
        clubId: 'club',
        teamName: 'F2012',
        clubName: 'Testklubben',
        leaders: [
          for (final role in roles)
            if (role.role == 'leader')
              TeamLeaderSummary(
                personId: role.personId,
                displayName: role.name,
              ),
        ],
        memberCount: people.length,
        canManage: canManage,
        activeInvitationCount: 0,
        pendingApplicationCount: 0,
      );

  List<TeamRole> roles;
  final List<LeaderCandidate> candidates;
  final List<RosterPersonSummary> people;
  final bool canManage;
  Object? failWith;
  final calls = <(String, String?, String?)>[];

  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async => people;

  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) async {
    final player = people.where((p) => p.id == personId).firstOrNull;
    final role = roles.where((r) => r.personId == personId).firstOrNull;
    if (player == null && role == null) throw StateError('not_found');
    return RosterPersonDetails(
      id: personId,
      displayName: player?.displayName ?? role!.name,
      teamId: teamId,
      teamName: 'F2012',
      assignmentState: 'active',
      birthYear: 2012,
      provenance: 'created',
      personRevision: canManage ? 1 : null,
      isSelf: role?.isSelf ?? false,
      homeMember: player != null,
    );
  }

  @override
  Future<TeamRoles> listTeamRoles({
    required String clubId,
    required String teamId,
  }) async => TeamRoles(
    canManage: canManage,
    roles: [...roles],
    grantable: grantable,
    sport: sport,
    positionCatalog: _catalogs[sport] ?? const [],
  );

  @override
  Future<List<LeaderCandidate>> listLeaderCandidates({
    required String clubId,
    required String teamId,
  }) async => candidates
      .where(
        (c) =>
            !roles.any((r) => r.personId == c.personId && r.role == 'leader'),
      )
      .toList();

  @override
  Future<void> setTeamRole({
    required String clubId,
    required String teamId,
    required String personId,
    String? fromRole,
    String? toRole,
    required String idempotencyKey,
  }) async {
    calls.add((personId, fromRole, toRole));
    if (failWith != null) throw failWith!;
    final name = [
      ...roles.where((r) => r.personId == personId).map((r) => r.name),
      ...candidates.where((c) => c.personId == personId).map((c) => c.name),
    ].first;
    final self =
        roles.any((r) => r.personId == personId && r.isSelf) ||
        candidates.any((c) => c.personId == personId && c.isSelf);
    if (fromRole != null) {
      roles.removeWhere((r) => r.personId == personId && r.role == fromRole);
    }
    if (toRole != null) {
      roles.add(
        TeamRole(personId: personId, name: name, role: toRole, isSelf: self),
      );
    }
  }
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
      rolePackage: 'club_functionary',
      capabilities: {
        'team.read',
        'team.roster.view',
        'club.memberships.manage',
      },
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

class _TitledIdentity extends _Identity {
  const _TitledIdentity();
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'leader',
      rolePackages: ['club_functionary', 'leader'],
      titles: ['head_coach'],
      capabilities: {
        'team.read',
        'team.roster.view',
        'club.memberships.manage',
      },
    ),
  ];
}

class _ViewerIdentity extends _Identity {
  const _ViewerIdentity();
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'player',
      capabilities: {'team.read', 'team.roster.view'},
    ),
  ];
}

const _all = [
  'development.manage',
  'event.attendance.correct_late',
  'event.attendance.manage',
  'event.logistics',
  'event.manage',
  'event.squad.manage',
  'match.live',
  'match.plan',
  'publication.manage',
  'team.leaders.manage',
  'team.roster.manage',
  'training.plan',
];
const _standard = [
  'event.attendance.correct_late',
  'event.attendance.manage',
  'event.logistics',
  'event.manage',
  'event.squad.manage',
  'match.live',
  'match.plan',
  'team.roster.manage',
  'training.plan',
];
const _teamManager = [
  'event.attendance.correct_late',
  'event.attendance.manage',
  'event.logistics',
  'event.manage',
  'event.squad.manage',
  'match.live',
  'publication.manage',
  'team.roster.manage',
];
