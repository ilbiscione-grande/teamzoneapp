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
  _Destination(ProductRouteContract.statistics, Icons.query_stats_outlined),
  _Destination(ProductRouteContract.development, Icons.trending_up_outlined),
];

_Destination _destinationFor(String path) =>
    _destinations.firstWhere((item) => item.path == path);

// The phone bottom bar keeps Home in the visual center; the drawer/sidebar
// on tablet, desktop and inside the mobile navigation drawer instead follows
// reading order (Home first). Both intentionally leave out development,
// which appears as its own row below the five primary destinations.
const _bottomNavOrder = [
  ProductRouteContract.team,
  ProductRouteContract.calendar,
  ProductRouteContract.home,
  ProductRouteContract.inbox,
  ProductRouteContract.statistics,
];

const _drawerMainOrder = [
  ProductRouteContract.home,
  ProductRouteContract.calendar,
  ProductRouteContract.team,
  ProductRouteContract.inbox,
  ProductRouteContract.statistics,
];
