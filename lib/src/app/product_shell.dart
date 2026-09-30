part of 'teamzone_app.dart';

class _ProductShell extends StatefulWidget {
  const _ProductShell({
    required this.profile,
    required this.contextValue,
    required this.contexts,
    required this.onContextChanged,
    required this.onContextsChanged,
    required this.onTeamCreated,
    required this.onSignOut,
    required this.roster,
    required this.membership,
    required this.legal,
    required this.profileServices,
    required this.calendar,
    required this.calendarPreferences,
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
  final Future<void> Function(String teamId) onTeamCreated;
  final Future<void> Function() onSignOut;
  final RosterServices roster;
  final MembershipServices membership;
  final LegalServices legal;
  final ProfileServices profileServices;
  final CalendarServices calendar;
  final CalendarPreferences calendarPreferences;
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
  final GlobalKey<NavigatorState> _productNavigatorKey =
      GlobalKey<NavigatorState>();

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
  late final Future<bool> _supportAdminAccess;
  late Future<int> _pendingTeamRequests;
  // Your own profile picture for the menu; none on failure.
  late Future<_OwnSummary> _ownSummary = _loadOwnSummary();

  /// Your current name and picture for the menu. Reloaded after you edit
  /// your details; falls back to the name from sign-in.
  Future<_OwnSummary> _loadOwnSummary() async {
    try {
      final details = await widget.profileServices.getMyProfile().timeout(
        const Duration(seconds: 15),
      );
      String? avatar;
      if (details.hasAvatar) {
        try {
          avatar = await widget.profileServices.avatarUrl(details.profileId);
        } catch (_) {}
      }
      return (name: details.displayName, avatar: avatar);
    } catch (_) {
      return (name: null, avatar: null);
    }
  }

  void _refreshOwnProfile() {
    if (!mounted) return;
    setState(() {
      _ownSummary = _loadOwnSummary();
    });
  }

  late final GoRouter _router = GoRouter(
    navigatorKey: _productNavigatorKey,
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
        path: ProductRouteContract.publication,
        builder: (_, _) => _PublicationSelfServiceSurface(
          clubId: widget.contextValue.clubId,
          editorial: widget.editorial,
        ),
      ),
      GoRoute(
        path: ProductRouteContract.settings,
        builder: (_, _) => _ProfileSettingsSurface(
          editorial: widget.editorial,
          contexts: widget.contexts,
          roster: widget.roster,
          onContextsChanged: widget.onContextsChanged,
          legal: widget.legal,
          calendarPreferences: widget.calendarPreferences,
          profileServices: widget.profileServices,
          onOwnProfileChanged: _refreshOwnProfile,
          messaging: widget.messaging,
        ),
      ),
      GoRoute(
        path: ProductRouteContract.support,
        builder: (_, _) => _SupportAdminSurface(
          membership: widget.membership,
          profile: widget.profileServices,
        ),
      ),
      GoRoute(
        path: ProductRouteContract.assistant,
        builder: (_, _) => _AssistantCoachHoldingSurface(
          assistantIdentity: widget.assistantIdentity,
          assistantPresentation: widget.assistantPresentation,
          overview: widget.overview,
          contextValue: widget.contextValue,
          onNavigate: _navigateFromSurface,
        ),
      ),
      GoRoute(
        path: '${ProductRouteContract.calendar}/event/:eventId',
        builder: (_, state) => _EventDetailsPage(
          eventId: state.pathParameters['eventId']!,
          contextValue: widget.contextValue,
          calendar: widget.calendar,
          roster: widget.roster,
          match: widget.match,
          matchSpaceV2: widget.matchSpaceV2,
          onNavigate: (fallback) =>
              _router.canPop() ? _router.pop() : _router.go(fallback),
        ),
      ),
      GoRoute(
        path: '${ProductRouteContract.team}/member/:personId',
        builder: (_, state) => _RosterPersonDetailsPage(
          personId: state.pathParameters['personId']!,
          contextValue: widget.contextValue,
          roster: widget.roster,
          profileServices: widget.profileServices,
          onOwnProfileChanged: _refreshOwnProfile,
          personalSettings: () => _ProfileSettingsSurface(
            embedded: true,
            editorial: widget.editorial,
            contexts: widget.contexts,
            roster: widget.roster,
            onContextsChanged: widget.onContextsChanged,
            legal: widget.legal,
            calendarPreferences: widget.calendarPreferences,
            profileServices: widget.profileServices,
            onOwnProfileChanged: _refreshOwnProfile,
            messaging: widget.messaging,
          ),
          onBack: () => _router.canPop()
              ? _router.pop()
              : _router.go('${ProductRouteContract.team}?tab=roster'),
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
                  onTeamCreated: (teamId) async {
                    _router.go('/home');
                    await widget.onTeamCreated(teamId);
                  },
                  initialTab: state.uri.queryParameters['tab'],
                  initialAction: state.uri.queryParameters['action'],
                  profileServices: widget.profileServices,
                )
              : destination.path == '/calendar'
              ? _CalendarSurface(
                  contextValue: widget.contextValue,
                  contexts: widget.contexts,
                  calendar: widget.calendar,
                  calendarPreferences: widget.calendarPreferences,
                  match: widget.match,
                  // EventDetails is a child page of the current calendar
                  // workspace. Push it so closing/back reveals the same
                  // view, date and filters instead of rebuilding Agenda.
                  onNavigate: (path) {
                    _router.push(path);
                  },
                  matchSpaceV2: widget.matchSpaceV2,
                  initialAction: state.uri.queryParameters['action'],
                )
              : destination.path == '/inbox'
              ? _InboxSurface(
                  contextValue: widget.contextValue,
                  contexts: widget.contexts,
                  messaging: widget.messaging,
                  initialThreadId: state.uri.queryParameters['thread'],
                  initialAction: state.uri.queryParameters['action'],
                  onNavigate: _navigateFromSurface,
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
                  messaging: widget.messaging,
                  // Event details are a child of the page that opened them.
                  // Push preserves Home (and its current team context) for X
                  // and browser back; other shortcuts remain destinations.
                  onNavigate: _navigateFromSurface,
                ),
        ),
    ],
    errorBuilder: (_, _) => const _NotFoundSurface(),
  );

  void _navigateFromSurface(String path) {
    final location = ProductRouteContract.canonicalizeLocation(path);
    if (location.startsWith('${ProductRouteContract.calendar}/event/')) {
      _router.push(location);
    } else {
      _router.go(location);
    }
  }

  int _indexForBottomNav(String location) {
    final index = _bottomNavOrder.indexWhere(
      (path) => location.startsWith(path),
    );
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    // All imperative pages in this shell have standalone GoRoutes. Reflect
    // their top-most URI on web so pushed event/member pages can be copied
    // and opened directly without sacrificing return-to-origin on close.
    if (kIsWeb) GoRouter.optionURLReflectsImperativeAPIs = true;
    _supportAdminAccess = widget.membership
        .isSupportAdmin()
        .timeout(const Duration(seconds: 15))
        .catchError((_) => false);
    _pendingTeamRequests = _loadPendingTeamRequests();
    unawaited(
      Future.sync(widget.profileServices.recordActivity).catchError((_) {}),
    );
    _locationHistory.add(_router.routeInformationProvider.value.uri.toString());
    _router.routeInformationProvider.addListener(_recordLocation);
  }

  Future<int> _loadPendingTeamRequests() async {
    if (!widget.contextValue.can('club.memberships.manage')) return 0;
    try {
      final requests = await widget.membership
          .listTeamCreationRequests(clubId: widget.contextValue.clubId)
          .timeout(const Duration(seconds: 15));
      return requests.where((item) => item.state == 'pending').length;
    } catch (_) {
      return 0;
    }
  }

  void _refreshPendingTeamRequests() => setState(() {
    _pendingTeamRequests = _loadPendingTeamRequests();
  });

  @override
  void didUpdateWidget(covariant _ProductShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.clubId != widget.contextValue.clubId ||
        oldWidget.contextValue.id != widget.contextValue.id) {
      _pendingTeamRequests = _loadPendingTeamRequests();
    }
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
    // A pushed detail page has a real navigator entry. Pop that before the
    // synthetic history used by `.go()` destinations so browser/system back
    // restores the exact originating URI and keeps the page state alive.
    if (_router.canPop()) {
      // Respect the active route's PopScope (for example an editor with
      // unsaved changes) instead of forcibly removing the route.
      await _productNavigatorKey.currentState?.maybePop();
      return;
    }
    if (_locationHistory.length > 1) {
      _router.go(_locationHistory[_locationHistory.length - 2]);
      return;
    }
    // A cold deep link has no in-app history. Treat Home as the stable root
    // instead of asking to exit from whichever destination happened to be
    // opened externally.
    final currentPath = _router.routeInformationProvider.value.uri.path;
    if (currentPath != ProductRouteContract.home) {
      // The external entry point must not remain behind the stable Home root,
      // otherwise repeated back presses would loop between the two pages.
      _locationHistory.clear();
      _router.go(ProductRouteContract.home);
      return;
    }
    // Back on Home with no earlier page: ask before exiting instead of
    // closing immediately.
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
        final mediaSize = MediaQuery.sizeOf(context);
        final width = mediaSize.width;
        final usesSidebar = AppBreakpoints.usesNavigationRail(width);
        final showAssistantPanel = !_assistantUsesFab(context);
        // EventDetails is a full page with its own header (centered title,
        // close button) — showing the shell's own context-picker bar above
        // it as well would stack two app bars.
        final hidesShellAppBar =
            location.startsWith('${ProductRouteContract.calendar}/event/') ||
            location.startsWith('${ProductRouteContract.team}/member/');
        final navigationPanel = _AppNavigationPanel(
          profile: widget.profile,
          contextValue: widget.contextValue,
          contexts: widget.contexts,
          currentLocation: location,
          onNavigate: _router.go,
          onContextChanged: widget.onContextChanged,
          membership: widget.membership,
          supportAdminAccess: _supportAdminAccess,
          onContextsChanged: widget.onContextsChanged,
          onTeamCreated: widget.onTeamCreated,
          pendingTeamRequests: _pendingTeamRequests,
          onTeamRequestsChanged: _refreshPendingTeamRequests,
          onSignOut: widget.onSignOut,
          closeDrawer: usesSidebar
              ? null
              : () => _scaffoldKey.currentState?.closeDrawer(),
          ownSummary: _ownSummary,
          onOpenOwnProfile: () {
            _scaffoldKey.currentState?.closeDrawer();
            final hasTeamProfile =
                widget.contextValue.teamId != null &&
                widget.contextValue.rolePackage != 'guardian';
            if (!hasTeamProfile) {
              _router.go(ProductRouteContract.settings);
            } else if (!location.startsWith(
              ProductRouteContract.ownTeamProfile,
            )) {
              _router.push(ProductRouteContract.ownTeamProfile);
            }
          },
        );
        return PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: _handleSystemBack,
          child: Scaffold(
            key: _scaffoldKey,
            appBar: hidesShellAppBar
                ? null
                : AppBar(
                    automaticallyImplyLeading: false,
                    title: InkWell(
                      onTap: () => _showContextPicker(
                        context: context,
                        contexts: widget.contexts,
                        activeContext: widget.contextValue,
                        pendingTeamRequests: _pendingTeamRequests,
                        onContextChanged: widget.onContextChanged,
                        membership: widget.membership,
                        onContextsChanged: widget.onContextsChanged,
                        onTeamCreated: widget.onTeamCreated,
                        onTeamRequestsChanged: _refreshPendingTeamRequests,
                      ),
                      child: FutureBuilder<int>(
                        future: _pendingTeamRequests,
                        initialData: 0,
                        builder: (context, snapshot) => Badge.count(
                          count: snapshot.data ?? 0,
                          isLabelVisible: (snapshot.data ?? 0) > 0,
                          child: _ContextTwoLineLabel(
                            contextValue: widget.contextValue,
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      if (!usesSidebar)
                        IconButton(
                          tooltip: strings.feature('Öppna menyn'),
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                          icon: FutureBuilder<_OwnSummary>(
                            future: _ownSummary,
                            builder: (context, snapshot) {
                              final avatar = snapshot.data?.avatar;
                              return CircleAvatar(
                                radius: 16,
                                backgroundImage: avatar == null
                                    ? null
                                    : NetworkImage(avatar),
                                child: avatar == null
                                    ? const Icon(Icons.person, size: 18)
                                    : null,
                              );
                            },
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
            body: Column(
              children: [
                const BrowserOfflineNotice(),
                Expanded(
                  child: Row(
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
                                  onPressed: () => _router.push(
                                    ProductRouteContract.assistant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (showAssistantPanel &&
                          location != ProductRouteContract.assistant)
                        _AssistantCoachSidePanel(
                          contextValue: widget.contextValue,
                          onOpen: () =>
                              _router.push(ProductRouteContract.assistant),
                        ),
                    ],
                  ),
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
  required TeamZoneContext activeContext,
  required Future<int> pendingTeamRequests,
  required ValueChanged<TeamZoneContext> onContextChanged,
  required MembershipServices membership,
  required Future<void> Function() onContextsChanged,
  required Future<void> Function(String teamId) onTeamCreated,
  required VoidCallback onTeamRequestsChanged,
}) {
  final strings = AppStrings.of(context);
  final otherContexts = contexts
      .where((item) => item.id != activeContext.id)
      .toList(growable: false);
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
          ListTile(
            leading: const Icon(Icons.check_circle),
            title: Text(
              activeContext.teamName ?? activeContext.clubName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${strings.feature('Aktivt lag')} · ${activeContext.clubName} · ${_contextRolesLabel(strings, activeContext)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            selected: true,
          ),
          if (otherContexts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                strings.feature('Byt till'),
                style: Theme.of(sheetContext).textTheme.labelLarge,
              ),
            ),
          for (final item in otherContexts)
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(
                item.teamName ?? item.clubName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.teamName == null
                    ? _contextRolesLabel(strings, item)
                    : '${item.clubName} · ${_contextRolesLabel(strings, item)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                onContextChanged(item);
                Navigator.of(sheetContext).pop();
              },
            ),
          const Divider(height: 1),
          if (activeContext.rolePackage == 'leader' ||
              activeContext.can('club.memberships.manage'))
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(strings.feature('Skapa ytterligare lag')),
              subtitle: Text(
                strings.feature(
                  activeContext.can('club.memberships.manage')
                      ? 'Lägg till ett nytt lag i den aktiva klubben.'
                      : 'Skicka en förfrågan till klubbens administratör.',
                ),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                await _createTeamFromContextPicker(
                  context: context,
                  activeContext: activeContext,
                  membership: membership,
                  onTeamCreated: onTeamCreated,
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_business_outlined),
            title: Text(strings.feature('Skapa en ny klubb')),
            subtitle: Text(
              strings.feature(
                'Starta en helt separat klubb med ett första lag.',
              ),
            ),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await Future<void>.delayed(Duration.zero);
              if (!context.mounted) return;
              await _createClubFromContextPicker(
                context: context,
                membership: membership,
                onTeamCreated: onTeamCreated,
              );
            },
          ),
          if (activeContext.can('club.memberships.manage'))
            ListTile(
              leading: const Icon(Icons.approval_outlined),
              title: Text(strings.feature('Förfrågningar om nya lag')),
              trailing: FutureBuilder<int>(
                future: pendingTeamRequests,
                initialData: 0,
                builder: (context, snapshot) => Badge.count(
                  count: snapshot.data ?? 0,
                  isLabelVisible: (snapshot.data ?? 0) > 0,
                ),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Future<void>.delayed(Duration.zero);
                if (!context.mounted) return;
                await _showTeamCreationRequests(
                  context: context,
                  activeContext: activeContext,
                  membership: membership,
                  onContextsChanged: onContextsChanged,
                  onRequestsChanged: onTeamRequestsChanged,
                );
              },
            ),
          if (activeContext.can('club.memberships.manage'))
            FutureBuilder<ClubVerificationStatus>(
              future: membership.getClubVerificationStatus(
                clubId: activeContext.clubId,
              ),
              builder: (_, snapshot) {
                final status = snapshot.data?.status;
                return ListTile(
                  key: const ValueKey('context-club-verification'),
                  leading: Icon(
                    status == 'official'
                        ? Icons.verified
                        : Icons.verified_outlined,
                  ),
                  title: Text(
                    strings.feature(switch (status) {
                      'official' => 'Officiell klubb',
                      'pending' => 'Granskning pågår',
                      _ => 'Gör klubben officiell',
                    }),
                  ),
                  subtitle: Text(
                    status == 'official' || status == 'pending'
                        ? activeContext.clubName
                        : strings.feature(
                            'Ansök hos TeamZone om att verifiera klubben.',
                          ),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await Future<void>.delayed(Duration.zero);
                    if (!context.mounted) return;
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => _ClubVerificationSheet(
                        clubId: activeContext.clubId,
                        membership: membership,
                      ),
                    );
                  },
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: Text(strings.feature('Hitta klubb eller lag')),
            subtitle: Text(
              strings.feature('Sök, ansök eller hantera väntande ansökningar.'),
            ),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await Future<void>.delayed(Duration.zero);
              if (!context.mounted) return;
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _MembershipJoinSheet(
                  membership: membership,
                  onApproved: () => onContextsChanged(),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _createTeamFromContextPicker({
  required BuildContext context,
  required TeamZoneContext activeContext,
  required MembershipServices membership,
  required Future<void> Function(String teamId) onTeamCreated,
}) async {
  final strings = AppStrings.of(context);
  var draftName = '';
  final teamName = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.feature('Skapa ytterligare lag')),
      content: TextField(
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 120,
        onChanged: (value) => draftName = value,
        decoration: InputDecoration(
          labelText: strings.feature('Lagnamn'),
          helperText: activeContext.clubName,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          onPressed: () {
            final value = draftName.trim();
            if (value.isNotEmpty && value.length <= 120) {
              Navigator.pop(dialogContext, value);
            }
          },
          child: Text(strings.feature('Skapa lag')),
        ),
      ],
    ),
  );
  if (teamName == null || !context.mounted) return;
  try {
    if (activeContext.can('club.memberships.manage')) {
      final teamId = await membership
          .createTeam(
            clubId: activeContext.clubId,
            teamName: teamName,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      await onTeamCreated(teamId);
    } else {
      await membership
          .requestTeamCreation(
            clubId: activeContext.clubId,
            sourceAssignmentId: activeContext.id,
            teamName: teamName,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              activeContext.can('club.memberships.manage')
                  ? 'Laget har skapats.'
                  : 'Förfrågan är skickad till klubbens administratör.',
            ),
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature('Laget kunde inte skapas. Försök igen.'),
          ),
        ),
      );
    }
  }
}

Future<void> _createClubFromContextPicker({
  required BuildContext context,
  required MembershipServices membership,
  required Future<void> Function(String teamId) onTeamCreated,
}) async {
  final strings = AppStrings.of(context);
  final rootContext = context;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _CreateClubSheet(
      membership: membership,
      onCreated: (result) async {
        Navigator.of(sheetContext).pop();
        if (rootContext.mounted) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            SnackBar(content: Text(strings.feature('Klubben har skapats.'))),
          );
        }
        await onTeamCreated(result.teamId);
      },
    ),
  );
}

Future<void> _showTeamCreationRequests({
  required BuildContext context,
  required TeamZoneContext activeContext,
  required MembershipServices membership,
  required Future<void> Function() onContextsChanged,
  required VoidCallback onRequestsChanged,
}) async {
  final strings = AppStrings.of(context);
  List<TeamCreationRequest> requests;
  try {
    requests = await membership
        .listTeamCreationRequests(clubId: activeContext.clubId)
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.feature('Förfrågningarna kunde inte laddas.')),
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            ListTile(title: Text(strings.feature('Förfrågningar om nya lag'))),
            Expanded(
              child: requests.isEmpty
                  ? Center(child: Text(strings.feature('Inga förfrågningar.')))
                  : ListView(
                      children: [
                        for (final request in requests)
                          ListTile(
                            title: Text(request.teamName),
                            subtitle: Text(
                              '${request.requesterName} · ${strings.domainValue(request.state)}',
                            ),
                            trailing: request.state != 'pending'
                                ? null
                                : Wrap(
                                    children: [
                                      TextButton(
                                        onPressed: () async {
                                          await membership
                                              .decideTeamCreationRequest(
                                                requestId: request.id,
                                                approve: false,
                                                expectedRevision:
                                                    request.revision,
                                                idempotencyKey: _newUuid(),
                                              );
                                          onRequestsChanged();
                                          setSheetState(
                                            () => requests = requests
                                                .where(
                                                  (item) =>
                                                      item.id != request.id,
                                                )
                                                .toList(),
                                          );
                                        },
                                        child: Text(strings.feature('Avslå')),
                                      ),
                                      FilledButton(
                                        onPressed: () async {
                                          await membership
                                              .decideTeamCreationRequest(
                                                requestId: request.id,
                                                approve: true,
                                                expectedRevision:
                                                    request.revision,
                                                idempotencyKey: _newUuid(),
                                              );
                                          await onContextsChanged();
                                          onRequestsChanged();
                                          setSheetState(
                                            () => requests = requests
                                                .where(
                                                  (item) =>
                                                      item.id != request.id,
                                                )
                                                .toList(),
                                          );
                                        },
                                        child: Text(strings.feature('Godkänn')),
                                      ),
                                    ],
                                  ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
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
  final canManageRoster =
      contextValue.can('club.memberships.manage') ||
      contextValue.can('team.roster.manage');
  final actions = <_QuickAction>[];
  // Specific actions first — the whole point of this sheet is to skip the
  // page and land directly in the thing you actually want to do, not just
  // navigate faster (per feedback: "lite mer specifika genvägar, t ex
  // skapa nytt event, bjud in spelare, skicka meddelande").
  if (contextValue.can('event.manage')) {
    actions.add((
      icon: Icons.add_circle_outline,
      label: strings.feature('Skapa nytt event'),
      route: ProductRouteContract.calendarCreateEvent(),
    ));
  }
  actions.add((
    icon: _destinationFor(ProductRouteContract.calendar).icon,
    label: strings.destination(ProductRouteContract.calendar),
    route: ProductRouteContract.calendar,
  ));
  if (canManageRoster) {
    actions.add((
      icon: Icons.person_add_alt_1,
      label: strings.feature('Bjud in spelare'),
      route: ProductRouteContract.teamInvite(),
    ));
  }
  actions.add((
    icon: _destinationFor(ProductRouteContract.team).icon,
    label: canManageRoster
        ? strings.feature('Hantera laget')
        : strings.destination(ProductRouteContract.team),
    route: ProductRouteContract.team,
  ));
  actions.add((
    icon: Icons.edit_outlined,
    label: strings.feature('Skicka meddelande'),
    route: ProductRouteContract.inboxCompose(),
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
  if (contextValue.can('publication.manage') ||
      contextValue.can('team.roster.manage')) {
    actions.add((
      icon: Icons.public_outlined,
      label: strings.feature('Publika sidor'),
      route: ProductRouteContract.publication,
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
    required this.membership,
    required this.supportAdminAccess,
    required this.onContextsChanged,
    required this.onTeamCreated,
    required this.pendingTeamRequests,
    required this.onTeamRequestsChanged,
    required this.onSignOut,
    required this.closeDrawer,
    required this.onOpenOwnProfile,
    required this.ownSummary,
  });

  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final String currentLocation;
  final ValueChanged<String> onNavigate;
  final ValueChanged<TeamZoneContext> onContextChanged;
  final MembershipServices membership;
  final Future<bool> supportAdminAccess;
  final Future<void> Function() onContextsChanged;
  final Future<void> Function(String teamId) onTeamCreated;
  final Future<int> pendingTeamRequests;
  final VoidCallback onTeamRequestsChanged;
  final Future<void> Function() onSignOut;
  final VoidCallback onOpenOwnProfile;
  final Future<_OwnSummary> ownSummary;
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
        contextValue.can('publication.manage') ||
        contextValue.can('team.roster.manage');
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
      child: Theme(
        data: navigationTheme,
        child: _buildContent(context, strings, hasAdminLinks),
      ),
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
          const SizedBox(height: 12),
          // Opens your own profile in the active team; without a team
          // profile (no team, or a guardian) the account settings instead.
          Semantics(
            button: true,
            label: strings.feature('Min profil'),
            child: InkWell(
              key: const Key('drawer-own-profile'),
              borderRadius: BorderRadius.circular(16),
              onTap: onOpenOwnProfile,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    FutureBuilder<_OwnSummary>(
                      future: ownSummary,
                      builder: (context, snapshot) {
                        final avatar = snapshot.data?.avatar;
                        final name = snapshot.data?.name ?? profile.displayName;
                        return Column(
                          children: [
                            CircleAvatar(
                              key: const Key('drawer-own-avatar'),
                              radius: 36,
                              backgroundImage: avatar == null
                                  ? null
                                  : NetworkImage(avatar),
                              child: avatar == null
                                  ? const Icon(Icons.person, size: 40)
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name.isEmpty ? strings.signOut : name,
                              key: const Key('drawer-own-name'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        );
                      },
                    ),
                    Text(
                      _contextRolesLabel(strings, contextValue),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              onPressed: () => _showContextPicker(
                context: context,
                contexts: contexts,
                activeContext: contextValue,
                pendingTeamRequests: pendingTeamRequests,
                onContextChanged: onContextChanged,
                membership: membership,
                onContextsChanged: onContextsChanged,
                onTeamCreated: onTeamCreated,
                onTeamRequestsChanged: onTeamRequestsChanged,
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
                    child: FutureBuilder<int>(
                      future: pendingTeamRequests,
                      initialData: 0,
                      builder: (context, snapshot) => Badge.count(
                        count: snapshot.data ?? 0,
                        isLabelVisible: (snapshot.data ?? 0) > 0,
                        child: _ContextTwoLineLabel(contextValue: contextValue),
                      ),
                    ),
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
                  if (contextValue.can('publication.manage') ||
                      contextValue.can('team.roster.manage'))
                    _NavPanelRow(
                      icon: Icons.public_outlined,
                      label: strings.feature('Publika sidor'),
                      onTap: () => _go(ProductRouteContract.publication),
                    ),
                ],
                FutureBuilder<bool>(
                  future: supportAdminAccess,
                  builder: (context, snapshot) => snapshot.data == true
                      ? _NavPanelRow(
                          icon: Icons.support_agent_outlined,
                          label: strings.feature('Supportärenden'),
                          selected: currentLocation.startsWith(
                            ProductRouteContract.support,
                          ),
                          onTap: () => _go(ProductRouteContract.support),
                        )
                      : const SizedBox.shrink(),
                ),
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

bool _assistantUsesFab(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final isNativeTablet =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      size.shortestSide >= AppBreakpoints.tablet;
  return isNativeTablet || !AppBreakpoints.usesAssistantSidePanel(size.width);
}

/// What you are in a context. Your titles replace the plain leader role,
/// e.g. "Huvudtränare · Klubbfunktionär"; otherwise the roles, e.g.
/// "Klubbfunktionär · Ledare".
String _contextRolesLabel(AppStrings strings, TeamZoneContext context) {
  final titles = [
    ...context.titles.map((key) => _titleLabel(strings, key)),
    ...context.customTitles,
  ];
  return [
    ...titles,
    for (final role in context.roles)
      if (titles.isEmpty || role != 'leader') strings.domainValue(role),
  ].join(' · ');
}

typedef _OwnSummary = ({String? name, String? avatar});
