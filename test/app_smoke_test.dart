import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';

void main() {
  testWidgets('shows a safe unconfigured state without keys', (tester) async {
    await tester.pumpWidget(
      const TeamZoneApp(
        environment: AppEnvironment(name: 'audit'),
        locale: Locale('sv'),
        services: AppServices(
          identity: UnconfiguredIdentityServices(),
          isConfigured: false,
        ),
      ),
    );

    expect(find.text('Backend är inte ansluten'), findsOneWidget);
    expect(find.textContaining('service-role'), findsOneWidget);
  });

  testWidgets('shows waiting room for an account without context', (
    tester,
  ) async {
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _FakeIdentity(contexts: const []),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ditt konto är klart'), findsOneWidget);
    expect(find.textContaining('onboarding'), findsNothing);
  });

  testWidgets('renders five stable destinations for a valid context', (
    tester,
  ) async {
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _FakeIdentity(
            contexts: const [
              TeamZoneContext(
                id: 'assignment-1',
                clubId: 'club-1',
                clubName: 'Testklubben',
                teamId: 'team-1',
                teamName: 'F2012',
                rolePackage: 'leader',
                capabilities: {'team.read'},
              ),
            ],
          ),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Statistik moved to Laget; the Arbetsytor heading is tested below.
    for (final label in ['Hem', 'Laget', 'Kalender', 'Inkorg']) {
      await tester.scrollUntilVisible(
        find.text(label),
        250,
        scrollable: find.descendant(
          of: find.byKey(const Key('app-navigation-panel-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text(label), findsWidgets);
    }
    expect(find.textContaining('F2012'), findsWidgets);
  });

  testWidgets('the drawer lists the workspaces under a heading and the tools', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _FakeIdentity(
            contexts: const [
              TeamZoneContext(
                id: 'assignment-1',
                clubId: 'club-1',
                clubName: 'Testklubben',
                teamId: 'team-1',
                teamName: 'F2012',
                rolePackage: 'leader',
                capabilities: {
                  'team.read',
                  'event.manage',
                  'publication.manage',
                  'club.memberships.manage',
                },
              ),
            ],
          ),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.descendant(
      of: find.byKey(const Key('app-navigation-panel-list')),
      matching: find.byType(Scrollable),
    );
    // Arbetsytor is a heading, not a row of its own.
    expect(find.text('ARBETSYTOR'), findsOneWidget);
    for (final key in [
      'drawer-workspace-match_workspace',
      'drawer-workspace-training',
      'drawer-workspace-team_development',
      'drawer-workspace-development',
      'drawer-workspace-statistics',
      'drawer-tool-club',
      'drawer-tool-tournaments',
      'drawer-tool-editorial',
      'drawer-tool-publication',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        100,
        scrollable: list,
      );
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('drawer-tool-editorial')));
    await tester.pumpAndSettle();
    expect(find.text('Nyhetsredaktion'), findsWidgets);
    // The + on the heading opens the page listing every module.
    await tester.scrollUntilVisible(
      find.byKey(const Key('drawer-workspaces-add')),
      -100,
      scrollable: list,
    );
    await tester.tap(find.byKey(const Key('drawer-workspaces-add')));
    await tester.pumpAndSettle();
    expect(find.text('Moduler'), findsOneWidget);
  });

  testWidgets('a player has no workspaces or tools in the drawer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: _FakeIdentity(
            contexts: const [
              TeamZoneContext(
                id: 'assignment-1',
                clubId: 'club-1',
                clubName: 'Testklubben',
                teamId: 'team-1',
                teamName: 'F2012',
                rolePackage: 'player',
                capabilities: {'team.read'},
              ),
            ],
          ),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ARBETSYTOR'), findsNothing);
    expect(
      find.byKey(const Key('drawer-workspace-match_workspace')),
      findsNothing,
    );
  });

  test('context parsing rejects missing capability projection', () {
    expect(
      () => TeamZoneContext.fromJson({
        'context_id': 'context',
        'club_id': 'club',
        'club_name': 'Club',
        'role_package': 'unknown',
      }),
      throwsFormatException,
    );
  });

  testWidgets('renders the safe state in English', (tester) async {
    await tester.pumpWidget(
      const TeamZoneApp(
        environment: AppEnvironment(name: 'audit'),
        locale: Locale('en'),
        services: AppServices(
          identity: UnconfiguredIdentityServices(),
          isConfigured: false,
        ),
      ),
    );

    expect(find.text('Backend is not connected'), findsOneWidget);
  });
}

class _FakeIdentity implements IdentityServices {
  _FakeIdentity({required this.contexts});

  final List<TeamZoneContext> contexts;

  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;

  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();

  @override
  Future<List<TeamZoneContext>> getContexts() async => contexts;

  @override
  Future<TeamZoneProfile> getProfile() async => const TeamZoneProfile(
    id: 'profile-1',
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
