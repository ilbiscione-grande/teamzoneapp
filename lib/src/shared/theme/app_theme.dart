import 'package:flutter/material.dart';

import 'app_palette.dart';

export 'app_palette.dart';

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

/// A selectable color theme: a seed color for Material's derived roles,
/// plus the accent used in light mode ([primary], a deep tone) and in dark
/// mode ([bright], a lighter tone); see [AppColorSchemes]. The visual
/// language everything else is built from — typography, spacing, card
/// shapes — stays identical across themes; only the colors change.
enum AppColorTheme {
  green(
    'green',
    'Grön',
    Color(0xFF599370),
    Color(0xFF1F6B45),
    Color(0xFF3DDC84),
  ),
  blue('blue', 'Blå', Color(0xFF16283D), Color(0xFF1E4E8C), Color(0xFF6FA8FF)),
  red('red', 'Röd', Color(0xFF852929), Color(0xFF9B2C2C), Color(0xFFFF8A80)),
  amber(
    'amber',
    'Orange',
    Color(0xFF724C14),
    Color(0xFF8A5A12),
    Color(0xFFF6B44B),
  );

  const AppColorTheme(
    this.id,
    this.label,
    this.seed,
    this.primary,
    this.bright,
  );

  /// Stable identifier persisted to device storage — not the enum name, so
  /// renaming/reordering the enum later can't silently change what a saved
  /// preference resolves to.
  final String id;
  final String label;
  final Color seed;
  final Color primary;
  final Color bright;

  static AppColorTheme fromId(String? id) => AppColorTheme.values.firstWhere(
    (theme) => theme.id == id,
    orElse: () => AppColorTheme.green,
  );

  /// The shared "accent surface" background: a radial gradient starting
  /// from a point somewhat lighter than this theme's base color, fading
  /// out to the base color itself. Used by the navigation panel.
  RadialGradient get menuGradient => RadialGradient(
    center: const Alignment(-0.6, -0.2),
    radius: 1.3,
    colors: [Color.lerp(seed, Colors.white, 0.12)!, seed],
  );
}

abstract final class AppTheme {
  /// Body, labels and buttons.
  static const String fontFamily = 'Geist';

  /// Display, headline and the larger title styles.
  static const String headingFontFamily = 'BricolageGrotesque';

  static ThemeData light([AppColorTheme colorTheme = AppColorTheme.green]) =>
      _build(Brightness.light, colorTheme);
  static ThemeData dark([AppColorTheme colorTheme = AppColorTheme.green]) =>
      _build(Brightness.dark, colorTheme);

  /// The app's look on another seed (a workspace module's own color),
  /// keeping the shared surfaces, fonts and shapes.
  static ThemeData seeded(Brightness brightness, Color seed) {
    final light = ColorScheme.fromSeed(seedColor: seed);
    final dark = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return _fromScheme(
      AppColorSchemes.build(
        brightness: brightness,
        seed: seed,
        primary: light.primary,
        bright: dark.primary,
      ),
    );
  }

  /// Bricolage Grotesque for display, headline and the larger titles;
  /// titleSmall stays Geist since Material uses it for tab and section
  /// labels.
  static TextTheme withHeadings(TextTheme base) {
    TextStyle? heading(TextStyle? style, FontWeight weight, double spacing) =>
        style?.copyWith(
          fontFamily: headingFontFamily,
          fontWeight: weight,
          letterSpacing: spacing,
        );
    return base.copyWith(
      displayLarge: heading(base.displayLarge, FontWeight.w700, -1),
      displayMedium: heading(base.displayMedium, FontWeight.w700, -.8),
      displaySmall: heading(base.displaySmall, FontWeight.w700, -.6),
      headlineLarge: heading(base.headlineLarge, FontWeight.w700, -.6),
      headlineMedium: heading(base.headlineMedium, FontWeight.w700, -.5),
      headlineSmall: heading(base.headlineSmall, FontWeight.w700, -.3),
      titleLarge: heading(base.titleLarge, FontWeight.w700, -.2),
      titleMedium: heading(base.titleMedium, FontWeight.w600, 0),
    );
  }

  static ThemeData _build(Brightness brightness, AppColorTheme colorTheme) =>
      _fromScheme(
        AppColorSchemes.build(
          brightness: brightness,
          seed: colorTheme.seed,
          primary: colorTheme.primary,
          bright: colorTheme.bright,
        ),
      );

  static ThemeData _fromScheme(ColorScheme colors) {
    final dark = colors.brightness == Brightness.dark;
    const minimumSize = WidgetStatePropertyAll(
      Size(AppSizes.minimumTouchTarget, AppSizes.minimumTouchTarget),
    );
    const radius = BorderRadius.all(Radius.circular(AppRadius.chip));
    const buttonShape = WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: radius),
    );
    final theme = ThemeData(
      brightness: colors.brightness,
      colorScheme: colors,
      fontFamily: fontFamily,
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: colors.surface,
      extensions: [AppPalette.derive(colors)],
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: dark ? 0 : 1,
        shadowColor: const Color(0x400B2016),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.tile)),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorColor: colors.primaryContainer,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.tile)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sheet)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      chipTheme: const ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: radius),
      ),
      filledButtonTheme: const FilledButtonThemeData(
        style: ButtonStyle(minimumSize: minimumSize, shape: buttonShape),
      ),
      outlinedButtonTheme: const OutlinedButtonThemeData(
        style: ButtonStyle(minimumSize: minimumSize, shape: buttonShape),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(minimumSize: minimumSize),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(minimumSize: minimumSize),
      ),
    );
    return theme.copyWith(
      textTheme: withHeadings(theme.textTheme),
      primaryTextTheme: withHeadings(theme.primaryTextTheme),
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
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    super.key,
  });

  final AppColorTheme colorTheme;
  final ValueChanged<AppColorTheme> onColorThemeChanged;

  /// Light, dark or following the device.
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  static AppColorThemeScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppColorThemeScope>();
    assert(scope != null, 'No AppColorThemeScope found in context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppColorThemeScope oldWidget) =>
      colorTheme != oldWidget.colorTheme || themeMode != oldWidget.themeMode;
}
