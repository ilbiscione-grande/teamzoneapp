import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
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
}

class _NewUser implements IdentityServices {
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Ny', locale: 'sv');
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
