part of 'teamzone_app.dart';

String _initialProductLocation(String platformRoute) {
  return ProductRouteContract.canonicalInitialLocation(platformRoute);
}

class _Destination {
  const _Destination(this.path, this.icon);

  final String path;
  final IconData icon;
}

const _destinations = [
  _Destination(ProductRouteContract.home, Icons.home_outlined),
  _Destination(ProductRouteContract.team, Icons.groups_outlined),
  _Destination(ProductRouteContract.calendar, Icons.calendar_month_outlined),
  _Destination(ProductRouteContract.inbox, Icons.inbox_outlined),
  _Destination(ProductRouteContract.workspaces, Icons.dashboard_outlined),
  _Destination(ProductRouteContract.development, Icons.trending_up_outlined),
];

_Destination _destinationFor(String path) =>
    _destinations.firstWhere((item) => item.path == path);

// The phone bottom bar keeps Home in the visual center. Four buttons are the
// same for everyone; the fifth, "Mer", opens the destinations the role and
// capabilities give (see _moreActionsFor). The drawer/sidebar on tablet,
// desktop and inside the mobile navigation drawer follows reading order
// (Home first) and lists workspaces and admin areas as their own rows.
const _morePath = 'teamzone:more';
const _bottomNavOrder = [
  ProductRouteContract.team,
  ProductRouteContract.calendar,
  ProductRouteContract.home,
  ProductRouteContract.inbox,
  _morePath,
];

const _drawerMainOrder = [
  ProductRouteContract.home,
  ProductRouteContract.calendar,
  ProductRouteContract.team,
  ProductRouteContract.inbox,
];
