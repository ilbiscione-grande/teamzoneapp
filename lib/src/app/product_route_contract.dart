class ProductRouteContract {
  const ProductRouteContract._();

  static const home = '/home';
  static const team = '/team';
  static const calendar = '/calendar';
  static const inbox = '/inbox';
  static const statistics = '/statistics';
  static const development = '/development';
  static const assistant = '/assistant';
  static const billing = '/billing';
  static const economy = '/economy';
  static const board = '/board';
  static const editorial = '/editorial';

  static const primaryPaths = {
    home,
    team,
    calendar,
    inbox,
    statistics,
    development,
  };

  static const auxiliaryPaths = {billing, economy, board, assistant, editorial};
  static const canonicalPaths = {...primaryPaths, ...auxiliaryPaths};

  /// Stable deep link for EventDetails. Planning sub-features can later add
  /// their own query parameter without changing the event identity contract.
  static String calendarEvent(String eventId) =>
      Uri(path: calendar, queryParameters: {'event': eventId}).toString();

  static String canonicalInitialLocation(String platformRoute) {
    final uri = Uri.tryParse(platformRoute);
    final path = uri?.path ?? platformRoute;
    if (!canonicalPaths.contains(path)) return home;
    if (path == team || path == calendar || path == inbox) {
      return uri?.toString() ?? path;
    }
    return path;
  }

  static bool isCanonical(String path) => canonicalPaths.contains(path);
}
