part of 'teamzone_app.dart';

class _ProductShell extends StatefulWidget {
  const _ProductShell({
    required this.contextValue,
    required this.contexts,
    required this.onContextChanged,
    required this.onSignOut,
    required this.roster,
    required this.membership,
    required this.legal,
    required this.calendar,
    required this.overview,
    required this.messaging,
    required this.match,
    required this.development,
    required this.billing,
    required this.economy,
    required this.board,
    required this.matchSpaceV2,
    super.key,
  });

  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final ValueChanged<TeamZoneContext> onContextChanged;
  final Future<void> Function() onSignOut;
  final RosterServices roster;
  final MembershipServices membership;
  final LegalServices legal;
  final CalendarServices calendar;
  final OverviewServices overview;
  final MessagingServices messaging;
  final MatchServices match;
  final DevelopmentServices development;
  final BillingServices billing;
  final EconomyServices economy;
  final BoardServices board;
  final bool matchSpaceV2;

  @override
  State<_ProductShell> createState() => _ProductShellState();
}

class _ProductShellState extends State<_ProductShell> {
  late final GoRouter _router = GoRouter(
    initialLocation: _initialProductLocation(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    ),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(
        path: '/billing',
        builder: (_, state) => _BillingSurface(
          contextValue: widget.contextValue,
          billing: widget.billing,
          result: state.uri.queryParameters['result'],
        ),
      ),
      GoRoute(
        path: '/economy',
        builder: (_, _) => _EconomySurface(
          contextValue: widget.contextValue,
          economy: widget.economy,
        ),
      ),
      GoRoute(
        path: '/board',
        builder: (_, _) => _BoardSurface(
          contextValue: widget.contextValue,
          board: widget.board,
        ),
      ),
      GoRoute(
        path: ProductRouteContract.assistant,
        builder: (_, _) => const _AssistantCoachHoldingSurface(),
      ),
      for (final destination in _destinations)
        GoRoute(
          path: destination.path,
          builder: (_, state) => destination.path == '/team'
              ? _RosterSurface(
                  contextValue: widget.contextValue,
                  roster: widget.roster,
                  membership: widget.membership,
                  calendar: widget.calendar,
                  initialTab: state.uri.queryParameters['tab'],
                )
              : destination.path == '/calendar'
              ? _CalendarSurface(
                  contextValue: widget.contextValue,
                  contexts: widget.contexts,
                  calendar: widget.calendar,
                  match: widget.match,
                  matchSpaceV2: widget.matchSpaceV2,
                  initialEventId: state.uri.queryParameters['event'],
                )
              : destination.path == '/inbox'
              ? _InboxSurface(
                  contextValue: widget.contextValue,
                  messaging: widget.messaging,
                  initialThreadId: state.uri.queryParameters['thread'],
                  onNavigate: _router.go,
                )
              : destination.path == '/development'
              ? _DevelopmentSurface(
                  contextValue: widget.contextValue,
                  development: widget.development,
                )
              : _OverviewSurface(
                  destination: destination,
                  contextValue: widget.contextValue,
                  overview: widget.overview,
                  calendar: widget.calendar,
                  onNavigate: _router.go,
                ),
        ),
    ],
    errorBuilder: (_, _) => const _NotFoundSurface(),
  );

  int _indexForLocation(String location) {
    final index = _destinations.indexWhere(
      (item) => location.startsWith(item.path),
    );
    return index < 0 ? 0 : index;
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _router.routeInformationProvider,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final location = _router.routeInformationProvider.value.uri.path;
        final selectedIndex = _indexForLocation(location);
        return Scaffold(
          appBar: AppBar(
            title: DropdownButtonHideUnderline(
              child: DropdownButton<TeamZoneContext>(
                isExpanded: true,
                value: widget.contextValue,
                onChanged: (value) {
                  if (value != null) widget.onContextChanged(value);
                },
                items: [
                  for (final item in widget.contexts)
                    DropdownMenuItem(
                      value: item,
                      child: Tooltip(
                        message: item.teamName ?? item.clubName,
                        child: Text(
                          item.teamName ?? item.clubName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (widget.contextValue.can('club.billing.manage'))
                IconButton(
                  tooltip: AppStrings.of(context).feature('Abonnemang'),
                  onPressed: () => _router.go('/billing'),
                  icon: const Icon(Icons.payments_outlined),
                ),
              if (_hasEconomyCapability(widget.contextValue))
                IconButton(
                  tooltip: AppStrings.of(context).feature('Ekonomi'),
                  onPressed: () => _router.go('/economy'),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                ),
              if (_hasBoardCapability(widget.contextValue))
                IconButton(
                  tooltip: AppStrings.of(context).feature('Styrelse'),
                  onPressed: () => _router.go('/board'),
                  icon: const Icon(Icons.badge_outlined),
                ),
              IconButton(
                tooltip: strings.feature('Integritetsinställningar'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  builder: (_) =>
                      _MarketingPreferenceSheet(legal: widget.legal),
                ),
                icon: const Icon(Icons.privacy_tip_outlined),
              ),
              IconButton(
                tooltip: strings.signOut,
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Row(
            children: [
              if (AppBreakpoints.usesNavigationRail(
                MediaQuery.sizeOf(context).width,
              ))
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: _goTo,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final item in _destinations)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        label: Text(strings.destination(item.path)),
                      ),
                  ],
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Router(
                        routerDelegate: _router.routerDelegate,
                        routeInformationParser: _router.routeInformationParser,
                        routeInformationProvider:
                            _router.routeInformationProvider,
                      ),
                    ),
                    if (!AppBreakpoints.usesNavigationRail(
                          MediaQuery.sizeOf(context).width,
                        ) &&
                        location != ProductRouteContract.assistant)
                      Positioned(
                        right: 16,
                        bottom: 88,
                        child: _AssistantCoachMobileFab(
                          onPressed: () =>
                              _router.push(ProductRouteContract.assistant),
                        ),
                      ),
                  ],
                ),
              ),
              if (AppBreakpoints.usesNavigationRail(
                    MediaQuery.sizeOf(context).width,
                  ) &&
                  location != ProductRouteContract.assistant)
                _AssistantCoachSidePanel(
                  onOpen: () => _router.push(ProductRouteContract.assistant),
                ),
            ],
          ),
          bottomNavigationBar:
              !AppBreakpoints.usesNavigationRail(
                MediaQuery.sizeOf(context).width,
              )
              ? NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: _goTo,
                  destinations: [
                    for (final item in _destinations)
                      NavigationDestination(
                        icon: Icon(item.icon),
                        label: strings.destination(item.path),
                      ),
                  ],
                )
              : null,
        );
      },
    );
  }

  void _goTo(int index) => _router.go(_destinations[index].path);
}
