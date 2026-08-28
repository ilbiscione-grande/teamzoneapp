import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/identity/session_persistence.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';

void main() {
  const leader = TeamZoneContext(
    id: 'leader-context',
    clubId: 'club',
    clubName: 'Club',
    teamId: 'leader-team',
    teamName: 'Ledarlaget',
    rolePackage: 'leader',
    capabilities: {'team.read'},
  );
  const player = TeamZoneContext(
    id: 'player-context',
    clubId: 'club',
    clubName: 'Club',
    teamId: 'player-team',
    teamName: 'Spelarlaget',
    rolePackage: 'player',
    capabilities: {'team.read'},
  );

  test('restores only a currently server-authorized context', () {
    expect(selectValidContext([leader, player], player.id), same(player));
    expect(selectValidContext([player, leader], 'revoked'), same(leader));
  });

  test('context persistence is isolated per profile and clearable', () async {
    final store = MemoryContextPersistence();
    await store.writeActiveContextId('user-a', leader.id);
    await store.writeActiveContextId('user-b', player.id);
    expect(await store.readActiveContextId('user-a'), leader.id);
    await store.clear('user-a');
    expect(await store.readActiveContextId('user-a'), isNull);
    expect(await store.readActiveContextId('user-b'), player.id);
  });

  test('shared-device storage removes and stops persisted sessions', () async {
    final delegate = _LocalStorageSpy();
    final storage = ToggleableSessionStorage(delegate);
    await storage.persistSession('first');
    await storage.setEnabled(false);
    await storage.persistSession('second');

    expect(delegate.persisted, ['first']);
    expect(delegate.removals, 1);
  });

  testWidgets('revoked session fails closed and explains recovery', (
    tester,
  ) async {
    final identity = _SessionIdentity(contexts: const [leader]);
    await tester.pumpWidget(
      TeamZoneApp(
        environment: const AppEnvironment(name: 'audit'),
        locale: const Locale('sv'),
        services: AppServices(
          identity: identity,
          contextPersistence: MemoryContextPersistence(),
          isConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ledarlaget'), findsOneWidget);

    identity.emit(SessionStatus.unauthenticated);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sessionen har avslutats'), findsOneWidget);
    expect(find.text('Ledarlaget'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await identity.close();
  });

  test('Supabase adapter freezes fail-closed and local sign-out contract', () {
    final source = File(
      'lib/src/core/supabase/supabase_bootstrap.dart',
    ).readAsStringSync();
    final shell = File('lib/src/app/product_shell.dart').readAsStringSync();
    final auth = File(
      'lib/src/features/auth/auth_surfaces.dart',
    ).readAsStringSync();

    expect(source, contains('currentSession!.isExpired'));
    expect(source, contains('SignOutScope.local'));
    expect(source, contains('ToggleableSessionStorage'));
    expect(source, contains('sink.add(SessionStatus.unauthenticated)'));
    expect(shell, contains('super.key'));
    expect(auth, contains('key: ValueKey(activeContext.id)'));
  });
}

class _LocalStorageSpy extends LocalStorage {
  final persisted = <String>[];
  int removals = 0;

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<bool> hasAccessToken() async => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> persistSession(String persistSessionString) async {
    persisted.add(persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    removals++;
  }
}

class _SessionIdentity implements IdentityServices {
  _SessionIdentity({required this.contexts});

  final List<TeamZoneContext> contexts;
  final _changes = StreamController<SessionStatus>.broadcast();

  void emit(SessionStatus status) => _changes.add(status);
  Future<void> close() => _changes.close();

  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;

  @override
  Stream<SessionStatus> get sessionChanges => _changes.stream;

  @override
  Future<List<TeamZoneContext>> getContexts() async => contexts;

  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Test', locale: 'sv');

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async => emit(SessionStatus.unauthenticated);
}
