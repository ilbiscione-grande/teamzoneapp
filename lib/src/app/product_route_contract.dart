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
  static const publication = '/publication';
  static const settings = '/settings';
  static const support = '/support';

  static const primaryPaths = {
    home,
    team,
    calendar,
    inbox,
    statistics,
    development,
  };

  static const auxiliaryPaths = {
    billing,
    economy,
    board,
    assistant,
    editorial,
    publication,
    settings,
    support,
  };
  static const canonicalPaths = {...primaryPaths, ...auxiliaryPaths};

  /// Stable deep link for EventDetails — its own page (a real path segment,
  /// not a ?event= query param on /calendar) since EventDetails stopped
  /// being a dialog/bottom sheet opened from within the calendar page.
  /// The id is percent-encoded so it round-trips even if it ever contained
  /// characters a raw path segment can't hold (a literal '/', say) — real
  /// event ids are server-generated UUIDs, but the identity contract
  /// shouldn't quietly depend on that.
  static String calendarEvent(String eventId) =>
      '$calendar/event/${Uri.encodeComponent(eventId)}';

  /// Stable deep link for a roster member's own details page.
  static String teamMember(String personId) =>
      '$team/member/${Uri.encodeComponent(personId)}';

  /// Deep links that land on a destination and immediately trigger one
  /// specific action there (rather than just opening the page), used by the
  /// swipe-up quick actions sheet. Each destination reads its own
  /// `action` query parameter once and opens the matching flow — see
  /// `initialAction` on the calendar/team/inbox surfaces.
  static String calendarCreateEvent() =>
      Uri(path: calendar, queryParameters: {'action': 'create'}).toString();
  static String teamInvite() =>
      Uri(path: team, queryParameters: {'action': 'invite'}).toString();
  static String inboxCompose() =>
      Uri(path: inbox, queryParameters: {'action': 'compose'}).toString();

  /// Older server projections used /calendar?event=... before EventDetails
  /// became a page. Keep those links actionable without changing unrelated
  /// calendar query parameters or accepting an external URL as navigation.
  static String canonicalizeLocation(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.path != calendar) {
      return location;
    }
    final eventId = uri.queryParameters['event'];
    if (eventId == null || eventId.isEmpty) return location;
    return calendarEvent(eventId);
  }

  static String canonicalInitialLocation(String platformRoute) {
    final location = canonicalizeLocation(platformRoute);
    final uri = Uri.tryParse(location);
    final path = uri?.path ?? location;
    if (path.startsWith('$calendar/event/')) return path;
    if (path.startsWith('$team/member/')) return path;
    if (!canonicalPaths.contains(path)) return home;
    if (path == team || path == calendar || path == inbox) {
      return uri?.toString() ?? path;
    }
    return path;
  }

  static bool isCanonical(String path) =>
      canonicalPaths.contains(path) ||
      path.startsWith('$calendar/event/') ||
      path.startsWith('$team/member/');
}
