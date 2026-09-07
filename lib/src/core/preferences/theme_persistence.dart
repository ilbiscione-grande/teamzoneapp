import 'package:shared_preferences/shared_preferences.dart';

/// Device-local (not per-profile: a shared device typically has one owner
/// even across accounts, and it's a low-stakes cosmetic preference) storage
/// for the chosen color theme id.
abstract interface class ThemePersistence {
  Future<String?> readColorThemeId();
  Future<void> writeColorThemeId(String id);
}

class StatelessThemePersistence implements ThemePersistence {
  const StatelessThemePersistence();

  @override
  Future<String?> readColorThemeId() async => null;

  @override
  Future<void> writeColorThemeId(String id) async {}
}

class SharedPreferencesThemePersistence implements ThemePersistence {
  const SharedPreferencesThemePersistence();

  static const _key = 'teamzone.color_theme';

  @override
  Future<String?> readColorThemeId() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> writeColorThemeId(String id) async {
    await (await SharedPreferences.getInstance()).setString(_key, id);
  }
}

class MemoryThemePersistence implements ThemePersistence {
  String? _value;

  @override
  Future<String?> readColorThemeId() async => _value;

  @override
  Future<void> writeColorThemeId(String id) async {
    _value = id;
  }
}
