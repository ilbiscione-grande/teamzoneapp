import 'package:shared_preferences/shared_preferences.dart';

/// Device-local (not per-profile: a shared device typically has one owner
/// even across accounts, and it's a low-stakes cosmetic preference) storage
/// for the chosen color theme id and light/dark mode ('system', 'light' or
/// 'dark').
abstract interface class ThemePersistence {
  Future<String?> readColorThemeId();
  Future<void> writeColorThemeId(String id);
  Future<String?> readBrightnessMode();
  Future<void> writeBrightnessMode(String mode);
}

class StatelessThemePersistence implements ThemePersistence {
  const StatelessThemePersistence();

  @override
  Future<String?> readColorThemeId() async => null;

  @override
  Future<void> writeColorThemeId(String id) async {}

  @override
  Future<String?> readBrightnessMode() async => null;

  @override
  Future<void> writeBrightnessMode(String mode) async {}
}

class SharedPreferencesThemePersistence implements ThemePersistence {
  const SharedPreferencesThemePersistence();

  static const _key = 'teamzone.color_theme';
  static const _brightnessKey = 'teamzone.brightness_mode';

  @override
  Future<String?> readColorThemeId() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> writeColorThemeId(String id) async {
    await (await SharedPreferences.getInstance()).setString(_key, id);
  }

  @override
  Future<String?> readBrightnessMode() async =>
      (await SharedPreferences.getInstance()).getString(_brightnessKey);

  @override
  Future<void> writeBrightnessMode(String mode) async {
    await (await SharedPreferences.getInstance()).setString(
      _brightnessKey,
      mode,
    );
  }
}

class MemoryThemePersistence implements ThemePersistence {
  String? _value;
  String? _brightness;

  @override
  Future<String?> readColorThemeId() async => _value;

  @override
  Future<void> writeColorThemeId(String id) async {
    _value = id;
  }

  @override
  Future<String?> readBrightnessMode() async => _brightness;

  @override
  Future<void> writeBrightnessMode(String mode) async {
    _brightness = mode;
  }
}
