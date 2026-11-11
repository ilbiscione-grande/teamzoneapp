import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/membership/membership_services.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

// A new user without a team pastes a team code in "Har du fått en
// inbjudan?" (2026-11-11): it was tried only as a personal invitation and
// always said the invitation was invalid.
void main() {
  Future<_Roster> pasteCode(
    WidgetTester tester, {
    required bool teamCodeValid,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final roster = _Roster(teamCodeValid: teamCodeValid);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _NewUser(),
          roster: roster,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('waiting-room')), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'lagkod-123');
    await tester.tap(find.text('Acceptera inbjudan'));
    await tester.pumpAndSettle();
    return roster;
  }

  testWidgets('a team code sends a request to join the team', (tester) async {
    final roster = await pasteCode(tester, teamCodeValid: true);
    expect(roster.calls, ['claim lagkod-123', 'team code lagkod-123']);
    expect(
      find.text(
        'Ansökan är skickad till laget. Du kommer in när en ledare har godkänt den.',
      ),
      findsOneWidget,
    );
    expect(find.text('Inbjudan är ogiltig eller har gått ut.'), findsNothing);
  });

  testWidgets('a code that is neither still says it is invalid', (
    tester,
  ) async {
    final roster = await pasteCode(tester, teamCodeValid: false);
    expect(roster.calls, ['claim lagkod-123', 'team code lagkod-123']);
    expect(find.text('Inbjudan är ogiltig eller har gått ut.'), findsOneWidget);
  });

  testWidgets('someone without a name names themself before applying', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final membership = _Naming();
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _NewUser(name: ''),
          roster: _Roster(teamCodeValid: true),
          membership: membership,
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    FilledButton accept() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Acceptera inbjudan'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(find.text('Vad heter du?'), findsOneWidget);
    expect(accept().onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('waiting-room-name')),
      '  Nils Nysson ',
    );
    await tester.tap(find.byKey(const ValueKey('waiting-room-name-save')));
    await tester.pumpAndSettle();
    expect(membership.names, ['Nils Nysson']);
    expect(find.text('Vad heter du?'), findsNothing);
    expect(accept().onPressed, isNotNull);
  });
}

class _Naming extends UnconfiguredMembershipServices
    implements DisplayNameServices {
  final names = <String>[];
  @override
  Future<String> setMyDisplayName(String name) async {
    names.add(name);
    return name;
  }
}

class _NewUser implements IdentityServices {
  _NewUser({this.name = 'Ny'});
  final String name;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      TeamZoneProfile(id: 'profile', displayName: name, locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => const [];
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}

class _Roster extends UnconfiguredRosterServices {
  _Roster({required this.teamCodeValid});
  final bool teamCodeValid;
  final calls = <String>[];

  @override
  Future<String> claim({
    required String token,
    required String idempotencyKey,
  }) async {
    calls.add('claim $token');
    throw StateError('not_found');
  }

  @override
  Future<String> claimTeamCode({
    required String token,
    required String idempotencyKey,
  }) async {
    calls.add('team code $token');
    if (!teamCodeValid) throw StateError('not_found');
    return 'request';
  }
}
