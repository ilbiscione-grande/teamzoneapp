import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';

abstract interface class ContextPersistence {
  Future<String?> readActiveContextId(String profileId);
  Future<void> writeActiveContextId(String profileId, String contextId);
  Future<void> clear(String profileId);
}

class StatelessContextPersistence implements ContextPersistence {
  const StatelessContextPersistence();

  @override
  Future<String?> readActiveContextId(String profileId) async => null;

  @override
  Future<void> writeActiveContextId(String profileId, String contextId) async {}

  @override
  Future<void> clear(String profileId) async {}
}

class SharedPreferencesContextPersistence implements ContextPersistence {
  const SharedPreferencesContextPersistence();

  String _key(String profileId) => 'teamzone.active_context.$profileId';

  @override
  Future<String?> readActiveContextId(String profileId) async =>
      (await SharedPreferences.getInstance()).getString(_key(profileId));

  @override
  Future<void> writeActiveContextId(String profileId, String contextId) async {
    await (await SharedPreferences.getInstance()).setString(
      _key(profileId),
      contextId,
    );
  }

  @override
  Future<void> clear(String profileId) async {
    await (await SharedPreferences.getInstance()).remove(_key(profileId));
  }
}

class MemoryContextPersistence implements ContextPersistence {
  final Map<String, String> _values = {};

  @override
  Future<String?> readActiveContextId(String profileId) async =>
      _values[profileId];

  @override
  Future<void> writeActiveContextId(String profileId, String contextId) async {
    _values[profileId] = contextId;
  }

  @override
  Future<void> clear(String profileId) async {
    _values.remove(profileId);
  }
}

TeamZoneContext selectValidContext(
  List<TeamZoneContext> contexts,
  String? persistedId,
) {
  if (contexts.isEmpty) throw StateError('No context is available.');
  for (final context in contexts) {
    if (context.id == persistedId) return context;
  }
  const priority = {
    'leader': 0,
    'club_functionary': 1,
    'guardian': 2,
    'player': 3,
    'guest': 4,
  };
  final sorted = [...contexts]
    ..sort(
      (a, b) => (priority[a.rolePackage] ?? 99).compareTo(
        priority[b.rolePackage] ?? 99,
      ),
    );
  return sorted.first;
}
