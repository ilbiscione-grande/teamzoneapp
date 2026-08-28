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

abstract final class AppTheme {
  static const Color lightSeed = Color(0xFF176B46);
  static const Color darkSeed = Color(0xFF6DDBA7);

  static ThemeData light() => _build(Brightness.light, lightSeed);
  static ThemeData dark() => _build(Brightness.dark, darkSeed);

  static ThemeData _build(Brightness brightness, Color seed) {
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      brightness: brightness,
      colorScheme: colors,
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
