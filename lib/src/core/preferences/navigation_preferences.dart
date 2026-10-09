import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bottom bar's fifth button. Home, Laget, Kalender and Inkorg are the
/// same for everyone; the fifth follows the active role unless the user
/// picked one in Inställningar.
enum FifthSlot {
  settings('/settings'),
  workspaces('/workspaces'),
  development('/development'),
  economy('/economy'),
  board('/board');

  const FifthSlot(this.path);
  final String path;

  static FifthSlot? fromName(String? name) =>
      FifthSlot.values.where((slot) => slot.name == name).firstOrNull;
}

/// What the active context may show in the fifth slot.
class FifthSlotAccess {
  const FifthSlotAccess({
    required this.isLeader,
    required this.hasEconomy,
    required this.hasBoard,
  });
  final bool isLeader, hasEconomy, hasBoard;

  bool allows(FifthSlot slot) => switch (slot) {
    FifthSlot.settings || FifthSlot.development => true,
    FifthSlot.workspaces => isLeader,
    FifthSlot.economy => hasEconomy,
    FifthSlot.board => hasBoard,
  };

  /// Leaders get their workspaces, the treasurer the economy, the board its
  /// page, everyone else the settings.
  FifthSlot get roleDefault => isLeader
      ? FifthSlot.workspaces
      : hasEconomy
      ? FifthSlot.economy
      : hasBoard
      ? FifthSlot.board
      : FifthSlot.settings;

  List<FifthSlot> get options => [
    for (final slot in FifthSlot.values)
      if (allows(slot)) slot,
  ];

  /// The user's own choice when this context allows it, otherwise the role
  /// default — never an empty or forbidden button.
  FifthSlot resolve(FifthSlot? preference) =>
      preference != null && allows(preference) ? preference : roleDefault;
}

/// Device-local choice for the fifth button. Null = automatic (by role).
abstract interface class NavigationPreferences {
  Future<FifthSlot?> readFifthSlot();
  Future<void> writeFifthSlot(FifthSlot? slot);
}

class StatelessNavigationPreferences implements NavigationPreferences {
  const StatelessNavigationPreferences();
  @override
  Future<FifthSlot?> readFifthSlot() async => null;
  @override
  Future<void> writeFifthSlot(FifthSlot? slot) async {}
}

class SharedPreferencesNavigationPreferences implements NavigationPreferences {
  const SharedPreferencesNavigationPreferences();
  static const _key = 'teamzone.navigation_fifth_slot';

  @override
  Future<FifthSlot?> readFifthSlot() async => FifthSlot.fromName(
    (await SharedPreferences.getInstance()).getString(_key),
  );

  @override
  Future<void> writeFifthSlot(FifthSlot? slot) async {
    final prefs = await SharedPreferences.getInstance();
    if (slot == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, slot.name);
    }
  }
}

class MemoryNavigationPreferences implements NavigationPreferences {
  FifthSlot? _value;
  @override
  Future<FifthSlot?> readFifthSlot() async => _value;
  @override
  Future<void> writeFifthSlot(FifthSlot? slot) async => _value = slot;
}

/// Makes the user's choice available to the shell and the settings page.
class NavigationPreferenceScope extends InheritedWidget {
  const NavigationPreferenceScope({
    required this.fifthSlot,
    required this.onFifthSlotChanged,
    required super.child,
    super.key,
  });

  /// Null = automatic (by role).
  final FifthSlot? fifthSlot;
  final ValueChanged<FifthSlot?> onFifthSlotChanged;

  static NavigationPreferenceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavigationPreferenceScope>();

  @override
  bool updateShouldNotify(NavigationPreferenceScope oldWidget) =>
      fifthSlot != oldWidget.fifthSlot;
}
