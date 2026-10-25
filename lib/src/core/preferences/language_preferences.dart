import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  system,
  sv,
  en;

  Locale? get locale => this == system ? null : Locale(name);

  static AppLanguage fromId(String? value) => values.firstWhere(
    (language) => language.name == value,
    orElse: () => system,
  );
}

abstract interface class LanguagePreferences {
  Future<AppLanguage> readLanguage();
  Future<void> writeLanguage(AppLanguage language);
}

class StatelessLanguagePreferences implements LanguagePreferences {
  const StatelessLanguagePreferences();
  @override
  Future<AppLanguage> readLanguage() async => AppLanguage.system;
  @override
  Future<void> writeLanguage(AppLanguage language) async {}
}

class SharedPreferencesLanguagePreferences implements LanguagePreferences {
  const SharedPreferencesLanguagePreferences();
  static const key = 'teamzone.language';
  @override
  Future<AppLanguage> readLanguage() async => AppLanguage.fromId(
    (await SharedPreferences.getInstance()).getString(key),
  );
  @override
  Future<void> writeLanguage(AppLanguage language) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = language == AppLanguage.system
        ? await preferences.remove(key)
        : await preferences.setString(key, language.name);
    if (!saved) throw StateError('language_preference_not_saved');
  }
}

class LanguagePreferenceScope extends InheritedWidget {
  const LanguagePreferenceScope({
    required this.language,
    required this.saving,
    required this.onChanged,
    required super.child,
    super.key,
  });
  final AppLanguage language;
  final bool saving;
  final Future<bool> Function(AppLanguage) onChanged;
  static LanguagePreferenceScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguagePreferenceScope>()!;
  @override
  bool updateShouldNotify(LanguagePreferenceScope oldWidget) =>
      language != oldWidget.language || saving != oldWidget.saving;
}
