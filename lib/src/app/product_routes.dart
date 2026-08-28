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
