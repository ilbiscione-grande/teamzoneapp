enum AppWindowClass { phone, tablet, desktop }

abstract final class AppBreakpoints {
  static const double tablet = 600;
  static const double desktop = 1024;

  static AppWindowClass classify(double width) => switch (width) {
    < tablet => AppWindowClass.phone,
    < desktop => AppWindowClass.tablet,
    _ => AppWindowClass.desktop,
  };

  static bool usesNavigationRail(double width) => width >= tablet;

  /// The assistant coach side panel only earns its own 288px column once the
  /// window is genuinely desktop-wide; at tablet widths it would leave the
  /// primary content column (already sharing space with the 280px navigation
  /// sidebar) too narrow, so tablet keeps the mobile-style floating button.
  static bool usesAssistantSidePanel(double width) => width >= desktop;
}
