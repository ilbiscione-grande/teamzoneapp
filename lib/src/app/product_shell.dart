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

  // Every distinct location the user has navigated to, oldest first, so
  // system back can step back through previously visited pages instead of
  // exiting the app immediately (GoRouter's `.go()` — used by the bottom
  // nav and drawer — replaces the current location rather than pushing a
  // history entry, so without this there is nothing for the platform back
  // button to pop once a page has been reached that way). Kept in sync by
  // `_recordLocation`, which also collapses a location change back to the
  // second-to-last entry into a pop instead of growing the list, so GoRouter's
  // own push/pop (e.g. the assistant surface) and this shell's own
  // `_handleSystemBack` don't leave duplicate entries a user would have to
  // press back through twice.
  final List<String> _locationHistory = [];

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
                  profile: widget.profile,
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
  void initState() {
    super.initState();
    _locationHistory.add(_router.routeInformationProvider.value.uri.toString());
    _router.routeInformationProvider.addListener(_recordLocation);
  }

  void _recordLocation() {
    final location = _router.routeInformationProvider.value.uri.toString();
    if (_locationHistory.isNotEmpty && _locationHistory.last == location) {
      return;
    }
    if (_locationHistory.length >= 2 &&
        _locationHistory[_locationHistory.length - 2] == location) {
      // Returned to the entry right before the current one — a pop (either
      // GoRouter's own, e.g. the assistant surface, or our own
      // _handleSystemBack going back a step) rather than a new page.
      _locationHistory.removeLast();
      return;
    }
    _locationHistory.add(location);
  }

  Future<void> _handleSystemBack(bool didPop, Object? result) async {
    if (didPop) return;
    if (_locationHistory.length > 1) {
      _router.go(_locationHistory[_locationHistory.length - 2]);
      return;
    }
    // Back on the very first page opened this session: ask before exiting
    // instead of closing immediately.
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.feature('Stäng TeamZone?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.close),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await SystemNavigator.pop();
    }
  }

  @override
  void dispose() {
    _router.routeInformationProvider.removeListener(_recordLocation);
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
        final showAssistantPanel = AppBreakpoints.usesAssistantSidePanel(width);
        final navigationPanel = _AppNavigationPanel(
          profile: widget.profile,
          contextValue: widget.contextValue,
          contexts: widget.contexts,
          currentLocation: location,
          onNavigate: _router.go,
          onContextChanged: widget.onContextChanged,
          onSignOut: widget.onSignOut,
          closeDrawer: usesSidebar
              ? null
              : () => _scaffoldKey.currentState?.closeDrawer(),
        );
        return PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: _handleSystemBack,
          child: Scaffold(
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
            drawer: usesSidebar
                ? null
                : Drawer(
                    backgroundColor: Colors.transparent,
                    child: navigationPanel,
                  ),
            body: Row(
              children: [
                if (usesSidebar)
                  SizedBox(
                    key: const Key('permanent-navigation-sidebar'),
                    width: 280,
                    child: Drawer(
                      backgroundColor: Colors.transparent,
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
                          routeInformationParser:
                              _router.routeInformationParser,
                          routeInformationProvider:
                              _router.routeInformationProvider,
                          backButtonDispatcher: _backButtonDispatcher,
                        ),
                      ),
                      if (!showAssistantPanel &&
                          location != ProductRouteContract.assistant)
                        // Always the standard bottom-right FAB position, not
                        // conditional on the phone bottom nav bar (Scaffold's
                        // body already excludes that bar's own area, so this
                        // never overlaps it). Kept the same position
                        // regardless of which page is showing, rather than
                        // moving up only when that page also has its own FAB
                        // there: pages whose own FAB is reached via a nested
                        // Navigator.push (e.g. domain management) aren't
                        // reflected in `location`, so a page-aware height here
                        // couldn't detect them reliably. Pages that do have
                        // their own FAB instead move THEIRS up out of the way
                        // via assistantFabClearanceLocation.
                        Positioned(
                          right: 16,
                          bottom: 16,
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
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final navigationBar = NavigationBar(
                        selectedIndex: _indexForBottomNav(location),
                        onDestinationSelected: (index) =>
                            _router.go(_bottomNavOrder[index]),
                        labelBehavior:
                            MediaQuery.textScalerOf(context).scale(1) >= 1.5
                            ? NavigationDestinationLabelBehavior
                                  .onlyShowSelected
                            : NavigationDestinationLabelBehavior.alwaysShow,
                        destinations: [
                          for (final path in _bottomNavOrder)
                            NavigationDestination(
                              icon: Icon(_destinationFor(path).icon),
                              label: strings.destination(path),
                            ),
                        ],
                      );
                      // A transparent region over just the Home button,
                      // sized by evenly dividing the bar's width (matching
                      // NavigationBar's own even item spacing). Swiping up
                      // opens the role-aware quick actions sheet; an
                      // ordinary tap is left alone — HitTestBehavior
                      // .translucent still lets the NavigationBar underneath
                      // enter the same gesture arena, so a tap (no drag
                      // beyond touch slop) resolves to its own tap
                      // recognizer as normal.
                      final homeIndex = _bottomNavOrder.indexOf(
                        ProductRouteContract.home,
                      );
                      final itemWidth =
                          constraints.maxWidth / _bottomNavOrder.length;
                      return Stack(
                        children: [
                          navigationBar,
                          Positioned(
                            left: itemWidth * homeIndex,
                            width: itemWidth,
                            top: 0,
                            bottom: 0,
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onVerticalDragEnd: (details) {
                                if ((details.primaryVelocity ?? 0) < -250) {
                                  _showQuickActionsMenu(
                                    context: context,
                                    contextValue: widget.contextValue,
                                    onNavigate: _router.go,
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
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

/// One row in the swipe-up quick actions sheet: an icon, a label and the
/// route it navigates to.
typedef _QuickAction = ({IconData icon, String label, String route});

/// Builds the role-aware shortcut list for the swipe-up quick actions
/// sheet: "a shortcut to every important function for that particular
/// person" (a coach gets team-management/event shortcuts, a player gets
/// event/inbox shortcuts, and so on) — driven by the same capabilities
/// already used to gate the drawer's admin links, not a separate
/// per-role-package list, so it stays correct for scoped/partial roles
/// (e.g. a team-only leader) without extra cases.
List<_QuickAction> _quickActionsFor(
  BuildContext context,
  TeamZoneContext contextValue,
) {
  final strings = AppStrings.of(context);
  final actions = <_QuickAction>[
    (
      icon: _destinationFor(ProductRouteContract.calendar).icon,
      label: strings.destination(ProductRouteContract.calendar),
      route: ProductRouteContract.calendar,
    ),
  ];
  if (contextValue.can('event.manage')) {
    actions.add((
      icon: Icons.add_circle_outline,
      label: strings.feature('Planera aktivitet'),
      route: ProductRouteContract.calendar,
    ));
  }
  actions.add((
    icon: _destinationFor(ProductRouteContract.team).icon,
    label: contextValue.can('club.memberships.manage')
        ? strings.feature('Hantera laget')
        : strings.destination(ProductRouteContract.team),
    route: ProductRouteContract.team,
  ));
  actions.add((
    icon: _destinationFor(ProductRouteContract.inbox).icon,
    label: strings.feature('Öppna inkorgen'),
    route: ProductRouteContract.inbox,
  ));
  if (contextValue.can('event.manage') ||
      contextValue.can('event.attendance.manage')) {
    actions.add((
      icon: _destinationFor(ProductRouteContract.statistics).icon,
      label: strings.destination(ProductRouteContract.statistics),
      route: ProductRouteContract.statistics,
    ));
  }
  if (contextValue.can('club.billing.manage')) {
    actions.add((
      icon: Icons.payments_outlined,
      label: strings.feature('Abonnemang'),
      route: ProductRouteContract.billing,
    ));
  }
  if (_hasEconomyCapability(contextValue)) {
    actions.add((
      icon: Icons.account_balance_wallet_outlined,
      label: strings.feature('Ekonomi'),
      route: ProductRouteContract.economy,
    ));
  }
  if (_hasBoardCapability(contextValue)) {
    actions.add((
      icon: Icons.badge_outlined,
      label: strings.feature('Styrelse'),
      route: ProductRouteContract.board,
    ));
  }
  if (contextValue.can('publication.manage')) {
    actions.add((
      icon: Icons.newspaper_outlined,
      label: strings.feature('Nyhetsredaktion'),
      route: ProductRouteContract.editorial,
    ));
  }
  return actions;
}

/// The swipe-up quick actions sheet, opened from the Home button in the
/// phone bottom nav (see the GestureDetector built alongside NavigationBar
/// in _ProductShellState.build).
Future<void> _showQuickActionsMenu({
  required BuildContext context,
  required TeamZoneContext contextValue,
  required ValueChanged<String> onNavigate,
}) {
  final strings = AppStrings.of(context);
  final actions = _quickActionsFor(context, contextValue);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              strings.feature('Genvägar'),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final action in actions)
            ListTile(
              leading: Icon(action.icon),
              title: Text(action.label),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onNavigate(action.route);
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
    required this.closeDrawer,
  });

  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final String currentLocation;
  final ValueChanged<String> onNavigate;
  final ValueChanged<TeamZoneContext> onContextChanged;
  final Future<void> Function() onSignOut;
  // Null on tablet/desktop, where this panel is a permanent sidebar rather
  // than a dismissible drawer. Closes via the Scaffold's own ScaffoldState
  // (see the GlobalKey in _ProductShellState), not Navigator.pop: a
  // Scaffold's Drawer is not a route on the ambient Navigator, so popping it
  // that way silently did nothing — found via a physical walkthrough
  // ("draget stängs inte när man trycker på en meny-rad").
  final VoidCallback? closeDrawer;

  void _go(String path) {
    onNavigate(path);
    closeDrawer?.call();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final hasAdminLinks =
        contextValue.can('club.billing.manage') ||
        _hasEconomyCapability(contextValue) ||
        _hasBoardCapability(contextValue) ||
        contextValue.can('publication.manage');
    // The panel always renders in the current theme's accent color rather
    // than following light/dark system mode: it's a deep, dark gradient in
    // every color theme (lighter accent at the top fading toward near-black
    // at the bottom), so its own content is themed dark regardless of the
    // rest of the app's brightness.
    final colorTheme = AppColorThemeScope.of(context).colorTheme;
    final navigationTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colorTheme.seed,
        brightness: Brightness.dark,
      ),
      fontFamily: AppTheme.fontFamily,
      useMaterial3: true,
    );
    return DecoratedBox(
      decoration: BoxDecoration(gradient: colorTheme.menuGradient),
      child: Theme(data: navigationTheme, child: _buildContent(context, strings, hasAdminLinks)),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppStrings strings,
    bool hasAdminLinks,
  ) {
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
                    onTap: () => _go(path),
                  ),
                _NavPanelRow(
                  icon: _destinationFor(ProductRouteContract.development).icon,
                  label: strings.destination(ProductRouteContract.development),
                  selected: currentLocation.startsWith(
                    ProductRouteContract.development,
                  ),
                  onTap: () => _go(ProductRouteContract.development),
                ),
                if (hasAdminLinks) ...[
                  const Divider(height: 1),
                  if (contextValue.can('club.billing.manage'))
                    _NavPanelRow(
                      icon: Icons.payments_outlined,
                      label: strings.feature('Abonnemang'),
                      onTap: () => _go('/billing'),
                    ),
                  if (_hasEconomyCapability(contextValue))
                    _NavPanelRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: strings.feature('Ekonomi'),
                      onTap: () => _go('/economy'),
                    ),
                  if (_hasBoardCapability(contextValue))
                    _NavPanelRow(
                      icon: Icons.badge_outlined,
                      label: strings.feature('Styrelse'),
                      onTap: () => _go('/board'),
                    ),
                  if (contextValue.can('publication.manage'))
                    _NavPanelRow(
                      icon: Icons.newspaper_outlined,
                      label: strings.feature('Nyhetsredaktion'),
                      onTap: () => _go(ProductRouteContract.editorial),
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
                    onPressed: () => _go(ProductRouteContract.settings),
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

/// `Scaffold.floatingActionButtonLocation` for any page with its own FAB
/// that shares the screen with the persistent Min assistent FAB (below the
/// desktop breakpoint, where the assistant is a FAB rather than a side
/// panel — see AppBreakpoints.usesAssistantSidePanel): shifts the page's
/// FAB up by the assistant FAB's height plus a gap, so it doesn't sit under
/// the assistant FAB, which always keeps the standard bottom-right spot.
/// At the desktop breakpoint there is no assistant FAB to clear, so the
/// caller should pass this only when
/// `!AppBreakpoints.usesAssistantSidePanel(width)`.
class _AboveAssistantFabLocation extends FloatingActionButtonLocation {
  const _AboveAssistantFabLocation();

  static const double _clearance = 72; // FAB height (56) + gap (16)

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final standard = FloatingActionButtonLocation.endFloat.getOffset(
      scaffoldGeometry,
    );
    return Offset(standard.dx, standard.dy - _clearance);
  }
}

const _aboveAssistantFabLocation = _AboveAssistantFabLocation();
