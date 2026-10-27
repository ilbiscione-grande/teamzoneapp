import 'package:flutter/material.dart';

/// Corner radii shared by cards, tiles and buttons.
abstract final class AppRadius {
  static const double chip = 12;
  static const double tile = 16;
  static const double card = 18;
  static const double sheet = 24;
}

/// The colors the home-page reference uses beyond the Material
/// ColorScheme: the soft accent tiles behind icons and selected states,
/// the pale red tile for matches and declines, and the card shadow.
///
/// Read with `AppPalette.of(context)`; installed by [AppTheme] for both
/// brightnesses, so every page gets the same tokens.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.accent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.danger,
    required this.dangerSoft,
    required this.onDangerSoft,
    required this.warning,
    required this.muted,
    required this.cardShadow,
  });

  /// Icons, links and highlighted text: the deep green in light mode, the
  /// brighter green in dark mode.
  final Color accent;

  /// Soft mint tile behind an icon, or a selected state.
  final Color accentSoft;
  final Color onAccentSoft;

  /// Matches and declines only.
  final Color danger;
  final Color dangerSoft;
  final Color onDangerSoft;

  /// An unanswered callup.
  final Color warning;

  /// Secondary text such as the date under a heading.
  final Color muted;

  /// The subtle shadow under light-mode cards (none in dark mode).
  final List<BoxShadow> cardShadow;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ??
      AppPalette.derive(Theme.of(context).colorScheme);

  /// Tokens derived from a ColorScheme, for themes built outside [AppTheme]
  /// (tests, a module's own seed).
  factory AppPalette.derive(ColorScheme colors) {
    final dark = colors.brightness == Brightness.dark;
    final danger = dark ? const Color(0xFFF87171) : const Color(0xFFD64545);
    return AppPalette(
      accent: colors.primary,
      accentSoft: colors.primaryContainer,
      onAccentSoft: colors.onPrimaryContainer,
      danger: danger,
      dangerSoft: dark
          ? Color.lerp(colors.surfaceContainerLow, danger, .2)!
          : const Color(0xFFFDECEC),
      onDangerSoft: dark ? const Color(0xFFFCA5A5) : const Color(0xFFC03535),
      warning: dark ? const Color(0xFFFBBF24) : const Color(0xFFB7791F),
      muted: colors.onSurfaceVariant,
      cardShadow: dark
          ? const []
          : const [
              BoxShadow(
                color: Color(0x0F0B2016),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: Color(0x0A0B2016),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
    );
  }

  @override
  AppPalette copyWith({
    Color? accent,
    Color? accentSoft,
    Color? onAccentSoft,
    Color? danger,
    Color? dangerSoft,
    Color? onDangerSoft,
    Color? warning,
    Color? muted,
    List<BoxShadow>? cardShadow,
  }) => AppPalette(
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    onAccentSoft: onAccentSoft ?? this.onAccentSoft,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    onDangerSoft: onDangerSoft ?? this.onDangerSoft,
    warning: warning ?? this.warning,
    muted: muted ?? this.muted,
    cardShadow: cardShadow ?? this.cardShadow,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccentSoft: Color.lerp(onAccentSoft, other.onAccentSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      onDangerSoft: Color.lerp(onDangerSoft, other.onDangerSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      cardShadow: t < .5 ? cardShadow : other.cardShadow,
    );
  }
}

/// The app's ColorSchemes: Material's seed-derived roles, with the
/// neutral surfaces replaced by the reference look — near-white page and
/// white cards in light mode, green-black page and dark green cards in
/// dark mode — tinted by the theme's own accent so every color theme
/// shares the same structure.
abstract final class AppColorSchemes {
  /// [primary] is the light-mode accent (the deep green); [bright] the
  /// dark-mode one (the brighter green).
  static ColorScheme build({
    required Brightness brightness,
    required Color seed,
    required Color primary,
    required Color bright,
  }) {
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    Color tint(Color neutral, Color accent, double amount) =>
        Color.lerp(neutral, accent, amount)!;
    if (brightness == Brightness.light) {
      final middle = Color.lerp(primary, bright, .5)!;
      final soft = tint(Colors.white, middle, .12);
      return base.copyWith(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: soft,
        onPrimaryContainer: tint(primary, Colors.black, .2),
        secondaryContainer: soft,
        onSecondaryContainer: tint(primary, Colors.black, .2),
        surface: tint(const Color(0xFFF7F8F8), primary, .02),
        onSurface: tint(const Color(0xFF111614), primary, .08),
        onSurfaceVariant: tint(const Color(0xFF5E6662), primary, .08),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: tint(const Color(0xFFF1F3F2), primary, .03),
        surfaceContainerHigh: tint(const Color(0xFFEBEEEC), primary, .04),
        surfaceContainerHighest: tint(const Color(0xFFE4E8E6), primary, .05),
        outline: tint(const Color(0xFFA3ABA7), primary, .06),
        outlineVariant: tint(const Color(0xFFE2E6E4), primary, .05),
        surfaceTint: Colors.transparent,
      );
    }
    final card = tint(const Color(0xFF111213), bright, .10);
    final soft = tint(card, bright, .16);
    return base.copyWith(
      primary: bright,
      onPrimary: tint(const Color(0xFF07100B), bright, .1),
      primaryContainer: soft,
      onPrimaryContainer: tint(bright, Colors.white, .25),
      secondaryContainer: soft,
      onSecondaryContainer: tint(bright, Colors.white, .25),
      surface: tint(const Color(0xFF0B0E0E), bright, .06),
      onSurface: tint(const Color(0xFFEDF1EF), bright, .04),
      onSurfaceVariant: tint(const Color(0xFF9AA39F), bright, .12),
      surfaceContainerLowest: tint(const Color(0xFF080A0A), bright, .05),
      surfaceContainerLow: card,
      surfaceContainer: tint(card, bright, .04),
      surfaceContainerHigh: tint(card, bright, .08),
      surfaceContainerHighest: tint(card, bright, .12),
      outline: tint(const Color(0xFF59625E), bright, .12),
      outlineVariant: tint(card, bright, .12),
      surfaceTint: Colors.transparent,
    );
  }
}
