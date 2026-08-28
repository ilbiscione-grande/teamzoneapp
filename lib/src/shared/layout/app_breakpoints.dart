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
}
