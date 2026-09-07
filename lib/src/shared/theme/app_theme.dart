import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppSizes {
  static const double minimumTouchTarget = 48;
  static const double contentMaxWidth = 1200;
  static const double stateCardMaxWidth = 520;
}

abstract final class AppMotion {
  static const Duration short = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 280);

  static Duration accessible(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// A selectable color theme: one seed color, from which both the light and
/// dark ColorSchemes are derived (`ColorScheme.fromSeed`). The visual
/// language everything else is built from — typography, spacing, card
/// shapes — stays identical across themes; only the seed color changes.
enum AppColorTheme {
  green('green', 'Grön', Color(0xFF599370)),
  blue('blue', 'Blå', Color(0xFF16283D)),
  red('red', 'Röd', Color(0xFF852929)),
  amber('amber', 'Orange', Color(0xFF724C14));

  const AppColorTheme(this.id, this.label, this.seed);

  /// Stable identifier persisted to device storage — not the enum name, so
  /// renaming/reordering the enum later can't silently change what a saved
  /// preference resolves to.
  final String id;
  final String label;
  final Color seed;

  static AppColorTheme fromId(String? id) => AppColorTheme.values.firstWhere(
    (theme) => theme.id == id,
    orElse: () => AppColorTheme.green,
  );

  /// The shared "accent surface" background: a radial gradient starting
  /// from a point somewhat lighter than this theme's base color, fading
  /// out to the base color itself. Used by both the navigation panel and
  /// the Home page's hero event card.
  RadialGradient get menuGradient => RadialGradient(
    center: const Alignment(-0.6, -0.2),
    radius: 1.3,
    colors: [Color.lerp(seed, Colors.white, 0.12)!, seed],
  );
}

abstract final class AppTheme {
  static const String fontFamily = 'Geist';

  static ThemeData light([AppColorTheme colorTheme = AppColorTheme.green]) =>
      _build(Brightness.light, colorTheme.seed);
  static ThemeData dark([AppColorTheme colorTheme = AppColorTheme.green]) =>
      _build(Brightness.dark, colorTheme.seed);

  static ThemeData _build(Brightness brightness, Color seed) {
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      brightness: brightness,
      colorScheme: colors,
      fontFamily: fontFamily,
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(AppSizes.minimumTouchTarget, AppSizes.minimumTouchTarget),
          ),
        ),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(AppSizes.minimumTouchTarget, AppSizes.minimumTouchTarget),
          ),
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(AppSizes.minimumTouchTarget, AppSizes.minimumTouchTarget),
          ),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(AppSizes.minimumTouchTarget, AppSizes.minimumTouchTarget),
          ),
        ),
      ),
    );
  }
}

/// Exposes the currently selected [AppColorTheme] and a way to change it to
/// every descendant of the app root — installed once above MaterialApp in
/// `TeamZoneApp`, so a deeply nested page (e.g. the profile settings theme
/// picker) can read and change it without threading a callback through
/// every constructor in between.
class AppColorThemeScope extends InheritedWidget {
  const AppColorThemeScope({
    required this.colorTheme,
    required this.onColorThemeChanged,
    required super.child,
    super.key,
  });

  final AppColorTheme colorTheme;
  final ValueChanged<AppColorTheme> onColorThemeChanged;

  static AppColorThemeScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppColorThemeScope>();
    assert(scope != null, 'No AppColorThemeScope found in context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppColorThemeScope oldWidget) =>
      colorTheme != oldWidget.colorTheme;
}
