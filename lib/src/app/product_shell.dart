part of 'teamzone_app.dart';

class _ProductShell extends StatefulWidget {
  const _ProductShell({
    required this.profile,
    required this.contextValue,
    required this.contexts,
    required this.onContextChanged,
    required this.onContextsChanged,
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
    required this.editorial,
    required this.assistantIdentity,
    required this.assistantPresentation,
    required this.matchSpaceV2,
    super.key,
  });

  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final ValueChanged<TeamZoneContext> onContextChanged;
  final Future<void> Function() onContextsChanged;
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
  final EditorialServices editorial;
  final AssistantIdentityServices assistantIdentity;
  final AssistantPresentationServices assistantPresentation;
  final bool matchSpaceV2;

  @override
  State<_ProductShell> createState() => _ProductShellState();
}

class _ProductShellState extends State<_ProductShell> {
  final RootBackButtonDispatcher _backButtonDispatcher =
      RootBackButtonDispatcher();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final GoRouter _router = GoRouter(
    initialLocation: _initialProductLocation(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    ),
    overridePlatformDefaultLocation: true,
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
        path: ProductRouteContract.editorial,
        builder: (_, _) => _EditorialSurface(
          contextValue: widget.contextValue,
          contexts: widget.contexts,
          editorial: widget.editorial,
        ),
      ),
      GoRoute(
        path: ProductRouteContract.settings,
        builder: (_, _) => _ProfileSettingsSurface(
          contexts: widget.contexts,
          roster: widget.roster,
          onContextsChanged: widget.onContextsChanged,
          legal: widget.legal,
        ),
      ),
      GoRoute(
        path: ProductRouteContract.assistant,
        builder: (_, _) => _AssistantCoachHoldingSurface(
          assistantIdentity: widget.assistantIdentity,
          assistantPresentation: widget.assistantPresentation,
          contextValue: widget.contextValue,
        ),
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
                  onNavigate: _router.go,
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

  int _indexForBottomNav(String location) {
    final index = _bottomNavOrder.indexWhere(
      (path) => location.startsWith(path),
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
        final width = MediaQuery.sizeOf(context).width;
        final usesSidebar = AppBreakpoints.usesNavigationRail(width);
        final showAssistantPanel = AppBreakpoints.usesAssistantSidePanel(
          width,
        );
        final navigationPanel = _AppNavigationPanel(
          profile: widget.profile,
          contextValue: widget.contextValue,
          contexts: widget.contexts,
          currentLocation: location,
          onNavigate: _router.go,
          onContextChanged: widget.onContextChanged,
          onSignOut: widget.onSignOut,
          closeOnNavigate: !usesSidebar,
        );
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: InkWell(
              onTap: () => _showContextPicker(
                context: context,
                contexts: widget.contexts,
                onContextChanged: widget.onContextChanged,
              ),
              child: _ContextTwoLineLabel(contextValue: widget.contextValue),
            ),
            actions: [
              if (!usesSidebar)
                IconButton(
                  tooltip: strings.feature('Öppna menyn'),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  icon: const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person, size: 18),
                  ),
                ),
            ],
          ),
          drawer: usesSidebar ? null : Drawer(child: navigationPanel),
          body: Row(
            children: [
              if (usesSidebar)
                SizedBox(
                  key: const Key('permanent-navigation-sidebar'),
                  width: 280,
                  child: Drawer(
                    shape: const RoundedRectangleBorder(),
                    child: navigationPanel,
                  ),
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
                        backButtonDispatcher: _backButtonDispatcher,
                      ),
                    ),
                    if (!showAssistantPanel &&
                        location != ProductRouteContract.assistant)
                      Positioned(
                        right: 16,
                        // Always cleared above the standard bottom-right FAB
                        // corner, not just above the phone bottom nav bar:
                        // several pages (roster, calendar, inbox, editorial,
                        // domain management) show their own FAB there via
                        // Scaffold's default endFloat position, and at the
                        // tablet breakpoint (sidebar shown, no bottom nav) a
                        // `bottom: 16` value put this FAB exactly on top of
                        // those, making both untappable. Found via the
                        // roster "Hantera" FAB failing to hit-test at 800×600
                        // after it was made icon-only (smaller, so its
                        // center landed inside the assistant FAB's circle).
                        bottom: 88,
                        child: _AssistantCoachMobileFab(
                          onPressed: () =>
                              _router.push(ProductRouteContract.assistant),
                        ),
                      ),
                  ],
                ),
              ),
              if (showAssistantPanel &&
                  location != ProductRouteContract.assistant)
                _AssistantCoachSidePanel(
                  contextValue: widget.contextValue,
                  onOpen: () => _router.push(ProductRouteContract.assistant),
                ),
            ],
          ),
          bottomNavigationBar: usesSidebar
              ? null
              : NavigationBar(
                  selectedIndex: _indexForBottomNav(location),
                  onDestinationSelected: (index) =>
                      _router.go(_bottomNavOrder[index]),
                  labelBehavior:
                      MediaQuery.textScalerOf(context).scale(1) >= 1.5
                      ? NavigationDestinationLabelBehavior.onlyShowSelected
                      : NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    for (final path in _bottomNavOrder)
                      NavigationDestination(
                        icon: Icon(_destinationFor(path).icon),
                        label: strings.destination(path),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

Future<void> _showContextPicker({
  required BuildContext context,
  required List<TeamZoneContext> contexts,
  required ValueChanged<TeamZoneContext> onContextChanged,
}) {
  final strings = AppStrings.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              strings.feature('Byt lag eller roll'),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final item in contexts)
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(
                item.teamName ?? item.clubName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.teamName == null
                    ? strings.domainValue(item.rolePackage)
                    : '${item.clubName} · ${strings.domainValue(item.rolePackage)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                onContextChanged(item);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    ),
  );
}

/// Team name (larger) on top, club name (smaller) underneath — used both as
/// the app bar's title and inside the navigation panel's team switcher.
class _ContextTwoLineLabel extends StatelessWidget {
  const _ContextTwoLineLabel({required this.contextValue});
  final TeamZoneContext contextValue;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          contextValue.teamName ?? contextValue.clubName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (contextValue.teamName != null)
          Text(
            contextValue.clubName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// One row (icon + label) inside the navigation panel, shared by the primary
/// destinations, development and the capability-gated admin items.
class _NavPanelRow extends StatelessWidget {
  const _NavPanelRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: onTap,
    ),
  );
}

/// Shared content for the mobile navigation drawer (opened via the app bar's
/// avatar) and the permanent tablet/desktop sidebar: profile, team switcher,
/// the five primary destinations, development, capability-gated admin links,
/// and settings/sign-out at the bottom.
class _AppNavigationPanel extends StatelessWidget {
  const _AppNavigationPanel({
    required this.profile,
    required this.contextValue,
    required this.contexts,
    required this.currentLocation,
    required this.onNavigate,
    required this.onContextChanged,
    required this.onSignOut,
    required this.closeOnNavigate,
  });

  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final String currentLocation;
  final ValueChanged<String> onNavigate;
  final ValueChanged<TeamZoneContext> onContextChanged;
  final Future<void> Function() onSignOut;
  final bool closeOnNavigate;

  void _go(BuildContext context, String path) {
    onNavigate(path);
    if (closeOnNavigate) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final hasAdminLinks =
        contextValue.can('club.billing.manage') ||
        _hasEconomyCapability(contextValue) ||
        _hasBoardCapability(contextValue) ||
        contextValue.can('publication.manage');
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const CircleAvatar(radius: 36, child: Icon(Icons.person, size: 40)),
          const SizedBox(height: 8),
          Text(
            profile.displayName.isEmpty ? strings.signOut : profile.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            strings.domainValue(contextValue.rolePackage),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              onPressed: () => _showContextPicker(
                context: context,
                contexts: contexts,
                onContextChanged: onContextChanged,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                alignment: Alignment.centerLeft,
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ContextTwoLineLabel(contextValue: contextValue),
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              key: const Key('app-navigation-panel-list'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final path in _drawerMainOrder)
                  _NavPanelRow(
                    icon: _destinationFor(path).icon,
                    label: strings.destination(path),
                    selected: currentLocation.startsWith(path),
                    onTap: () => _go(context, path),
                  ),
                _NavPanelRow(
                  icon: _destinationFor(ProductRouteContract.development).icon,
                  label: strings.destination(ProductRouteContract.development),
                  selected: currentLocation.startsWith(
                    ProductRouteContract.development,
                  ),
                  onTap: () => _go(context, ProductRouteContract.development),
                ),
                if (hasAdminLinks) ...[
                  const Divider(height: 1),
                  if (contextValue.can('club.billing.manage'))
                    _NavPanelRow(
                      icon: Icons.payments_outlined,
                      label: strings.feature('Abonnemang'),
                      onTap: () => _go(context, '/billing'),
                    ),
                  if (_hasEconomyCapability(contextValue))
                    _NavPanelRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: strings.feature('Ekonomi'),
                      onTap: () => _go(context, '/economy'),
                    ),
                  if (_hasBoardCapability(contextValue))
                    _NavPanelRow(
                      icon: Icons.badge_outlined,
                      label: strings.feature('Styrelse'),
                      onTap: () => _go(context, '/board'),
                    ),
                  if (contextValue.can('publication.manage'))
                    _NavPanelRow(
                      icon: Icons.newspaper_outlined,
                      label: strings.feature('Nyhetsredaktion'),
                      onTap: () => _go(context, ProductRouteContract.editorial),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _go(context, ProductRouteContract.settings),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(strings.feature('Inställningar')),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout),
                    label: Text(strings.signOut),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TeamZone',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
