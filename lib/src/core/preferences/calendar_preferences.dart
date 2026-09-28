import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preference for which calendar view (agenda/month/week/day)
/// opens by default. Unset (null) means "no explicit choice yet" -- callers
/// fall back to month view in that case, so this only ever needs to persist
/// an explicit override.
abstract interface class CalendarPreferences {
  Future<String?> readDefaultViewMode();
  Future<void> writeDefaultViewMode(String mode);
}

class StatelessCalendarPreferences implements CalendarPreferences {
  const StatelessCalendarPreferences();

  @override
  Future<String?> readDefaultViewMode() async => null;

  @override
  Future<void> writeDefaultViewMode(String mode) async {}
}

class SharedPreferencesCalendarPreferences implements CalendarPreferences {
  const SharedPreferencesCalendarPreferences();

  static const _key = 'teamzone.calendar_default_view_mode';

  @override
  Future<String?> readDefaultViewMode() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> writeDefaultViewMode(String mode) async {
    await (await SharedPreferences.getInstance()).setString(_key, mode);
  }
}

class MemoryCalendarPreferences implements CalendarPreferences {
  String? _value;

  @override
  Future<String?> readDefaultViewMode() async => _value;

  @override
  Future<void> writeDefaultViewMode(String mode) async {
    _value = mode;
  }
}
