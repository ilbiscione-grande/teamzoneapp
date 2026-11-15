import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/account_presence.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/identity/session_persistence.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';

// An account deleted while someone is signed in (support approved the
// erasure) must not leave them in the app as "Raderad användare": the app
// asks the sign-in service, signs out and says the account is gone.

class _DeletedIdentity implements IdentityServices, AccountPresenceCheck {
  _DeletedIdentity({required this.gone});

  bool gone;
  final _changes = StreamController<SessionStatus>.broadcast();
  int checks = 0;

  Future<void> close() => _changes.close();

  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;

  @override
  Stream<SessionStatus> get sessionChanges => _changes.stream;

  @override
  Future<bool> signOutIfAccountGone() async {
    checks++;
    if (!gone) return false;
    accountRemovedNotice.value = true;
    _changes.add(SessionStatus.unauthenticated);
    return true;
  }

  @override
  Future<TeamZoneProfile> getProfile() async {
    if (await signOutIfAccountGone()) throw const AccountRemovedException();
    return const TeamZoneProfile(
      id: 'profile',
      displayName: 'Raderad användare',
      locale: 'sv',
    );
  }

  @override
  Future<List<TeamZoneContext>> getContexts() async => const [];

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async => _changes.add(SessionStatus.unauthenticated);
}

Widget _app(IdentityServices identity) => TeamZoneApp(
  environment: const AppEnvironment(name: 'audit'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: identity,
    contextPersistence: MemoryContextPersistence(),
    isConfigured: true,
  ),
);

void main() {
  testWidgets('a deleted account is signed out at start and told why', (
    tester,
  ) async {
    final identity = _DeletedIdentity(gone: true);
    await tester.pumpWidget(_app(identity));
    await tester.pumpAndSettle();

    expect(find.text('Kontot är raderat'), findsOneWidget);
    expect(find.text('Sessionen har avslutats'), findsNothing);
    expect(find.textContaining('Raderad användare'), findsNothing);
    expect(accountRemovedNotice.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await identity.close();
  });

  testWidgets('deleted while the app was in the background', (tester) async {
    final identity = _DeletedIdentity(gone: false);
    await tester.pumpWidget(_app(identity));
    await tester.pumpAndSettle();
    expect(find.textContaining('Raderad användare'), findsWidgets);

    identity.gone = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Kontot är raderat'), findsOneWidget);
    expect(find.textContaining('Raderad användare'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await identity.close();
  });

  test('only a missing account or session signs out, not a network error', () {
    final source = File(
      'lib/src/core/supabase/supabase_bootstrap.dart',
    ).readAsStringSync();
    expect(source, contains("error.code == 'user_not_found'"));
    expect(source, contains("error.code != 'session_not_found'"));
    expect(source, contains('on AuthException catch (error)'));
  });
}
