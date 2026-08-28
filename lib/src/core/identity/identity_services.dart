import 'package:teamzone_app/src/core/identity/identity_models.dart';

abstract interface class IdentityServices {
  SessionStatus get sessionStatus;

  Stream<SessionStatus> get sessionChanges;

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<TeamZoneProfile> getProfile();

  Future<List<TeamZoneContext>> getContexts();
}

abstract interface class SessionPersistenceControl {
  Future<void> setSessionPersistence({required bool persist});
}

class UnconfiguredIdentityServices implements IdentityServices {
  const UnconfiguredIdentityServices();

  @override
  SessionStatus get sessionStatus => SessionStatus.unauthenticated;

  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();

  @override
  Future<TeamZoneProfile> getProfile() =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<List<TeamZoneContext>> getContexts() =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<void> signIn({required String email, required String password}) =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<void> signOut() async {}
}
