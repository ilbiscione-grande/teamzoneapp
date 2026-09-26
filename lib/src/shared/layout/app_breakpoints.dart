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

  /// Width gate for the assistant side panel. The product shell additionally
  /// excludes native tablets regardless of orientation: their contextual
  /// right column belongs to the active page and the assistant stays a FAB.
  static bool usesAssistantSidePanel(double width) => width >= desktop;
}
