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
    this.push = const UnconfiguredPushServices(),
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
  final PushServices push;

  @override
  State<_ProductShell> createState() => _ProductShellState();
}

class _ProductShellState extends State<_ProductShell> {
  final RootBackButtonDispatcher _backButtonDispatcher =
      RootBackButtonDispatcher();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<NavigatorState> _productNavigatorKey =
      GlobalKey<NavigatorState>();
  // The page area right under the app bar, see _scrollsUnderAppBar.
  final GlobalKey _pageAreaKey = GlobalKey();

  /// The app bar only takes its scrolled-under colour when the page itself
  /// scrolls beneath it. A list under a fixed header (the calendar grid,
  /// a pinned filter row) never reaches the app bar, so its scrolling must
  /// not recolour it.
  bool _scrollsUnderAppBar(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final scrollable = notification.context?.findRenderObject();
    final page = _pageAreaKey.currentContext?.findRenderObject();
    if (scrollable is! RenderBox ||
        page is! RenderBox ||
        !scrollable.attached ||
        !page.attached) {
      return true;
    }
    final gap =
        scrollable.localToGlobal(Offset.zero).dy -
        page.localToGlobal(Offset.zero).dy;
    return gap < 1;
  }

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
  int _assistantTaskRevision = 0;
  String? _renderedPageLocation;
  late final Future<bool> _supportAdminAccess;
  late Future<int> _pendingTeamRequests;
  late Future<AssistantIdentityPreference> _assistantPreference;
  // Your own profile picture for the menu; none on failure.
  late Future<_OwnSummary> _ownSummary = _loadOwnSummary();
  // Your name for Home's greeting: the one in the active team, else the
  // account's; never the login address.
  final ValueNotifier<String?> _ownName = ValueNotifier<String?>(null);

  /// VH-03: the child chosen on Home from another team, shown after the
  /// switch to that team.
  ({String contextId, String childId})? _guardianChildAfterSwitch;
  // REF-02: Domartillsättning/Domarersättning in the menu for the active club.
  late Future<RefereeSummary> _refereeSummary = _loadRefereeSummary();
  // The club's public page when published, for "Mer" and "Gå till".
  String? _publicUrl;
  RefereeSummary _refereeSummaryValue = const RefereeSummary();

  Future<void> _loadPublicPage() async {
    final clubId = widget.contextValue.clubId;
    try {
      final url = await widget.editorial
          .publicClubPage(clubId)
          .timeout(const Duration(seconds: 15));
      if (mounted && widget.contextValue.clubId == clubId) {
        setState(() => _publicUrl = url);
      }
    } catch (error) {
      AppErrors.caught('product_shell._loadPublicPage', error);
    }
  }

  /// The referee board's club for the active context, if any.
  ({String id, String name, bool canManage, bool canPay, int pendingReports})?
  get _refereeClub => _refereeSummaryValue.coordinatorClubs
      .where((club) => club.id == widget.contextValue.clubId)
      .firstOrNull;

  String? get _refereeLabel {
    final club = _refereeClub;
    if (club == null) return null;
    return AppStrings.of(
      context,
    ).feature(club.canManage ? 'Domartillsättning' : 'Domarersättning');
  }

  /// Opens a destination from "Mer" or the quick actions: the router, the
  /// public page in the browser, the referee board or the own profile.
  void _openAction(String route) {
    if (route.startsWith('http')) {
      unawaited(
        launchUrl(Uri.parse(route), mode: LaunchMode.externalApplication),
      );
    } else if (route == _refereeBoardRoute) {
      final club = _refereeClub;
      if (club != null) unawaited(_openRefereeBoard(club));
    } else if (route == _ownProfileRoute) {
      _openOwnProfile();
    } else {
      _router.go(route);
    }
  }

  void _openOwnProfile() {
    _scaffoldKey.currentState?.closeDrawer();
    final location = _router.routeInformationProvider.value.uri.toString();
    final hasTeamProfile =
        widget.contextValue.teamId != null &&
        widget.contextValue.rolePackage != 'guardian';
    if (!hasTeamProfile) {
      _router.go(ProductRouteContract.settings);
    } else if (!location.startsWith(ProductRouteContract.ownTeamProfile)) {
      _router.push(ProductRouteContract.ownTeamProfile);
    }
  }

  List<_QuickAction> _moreActions(BuildContext context) => _moreActionsFor(
    context,
    widget.contextValue,
    publicUrl: _publicUrl,
    refereeLabel: _refereeLabel,
  );

  Future<RefereeSummary> _loadRefereeSummary() async {
    // Not in the middle of the build that first asks for it.
    await Future<void>.value();
    RefereeSummary summary;
    try {
      summary = await widget.calendar.referees.summary().timeout(
        const Duration(seconds: 15),
      );
    } catch (error) {
      AppErrors.caught('product_shell._loadRefereeSummary', error);
      summary = const RefereeSummary();
    }
    if (mounted) setState(() => _refereeSummaryValue = summary);
    return summary;
  }

  /// Opens the referee board for the active club; the matches start with
  /// the active team.
  Future<void> _openRefereeBoard(
    ({String id, String name, bool canManage, bool canPay, int pendingReports})
    club,
  ) async {
    _scaffoldKey.currentState?.closeDrawer();
    final navigator = _productNavigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ClubRefereeBoardPage(
          services: widget.calendar.referees,
          clubId: club.id,
          clubName: club.name,
          canManage: club.canManage,
          canPay: club.canPay,
          teamId: widget.contextValue.teamId,
          teamName: widget.contextValue.teamName,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _refereeSummary = _loadRefereeSummary();
    });
  }

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
        } catch (error) {
          AppErrors.caught('product_shell._loadOwnSummary', error);
        }
      }
      // The name the own profile in the active team shows, else the
      // account's name, else the login address rather than nothing.
      // A club context: your name in the club and your board offices.
      final club = await _ownClubSummary();
      if (club != null && widget.contextValue.teamId == null) {
        _ownName.value = club.name;
        return (
          name: club.name ?? details.displayName,
          avatar: avatar,
          title: club.title,
        );
      }
      final teamName = await _ownNameInTeam();
      _ownName.value = teamName != null && teamName.trim().isNotEmpty
          ? teamName
          : details.displayName.trim().isNotEmpty
          ? details.displayName
          : null;
      final name = teamName != null && teamName.trim().isNotEmpty
          ? teamName
          : details.displayName.trim().isNotEmpty
          ? details.displayName
          : details.loginEmail ?? details.contactEmail;
      // DR-01: your board office after your role in the team.
      final office = club?.title;
      return (
        name: name,
        avatar: avatar,
        title: office == null || !mounted
            ? null
            : '${_contextRolesLabel(AppStrings.of(context), widget.contextValue)} · $office',
      );
    } catch (error) {
      AppErrors.caught('product_shell._loadOwnSummary', error);

      return (name: null, avatar: null, title: null);
    }
  }

  /// In a club context: your name in the club and your board offices
  /// ("Ordförande"); null in a team context or when unknown.
  Future<({String? name, String? title})?> _ownClubSummary() async {
    final overview = widget.overview;
    // The club context itself, or the one a team context carries duties from.
    final clubContextId = widget.contextValue.teamId == null
        ? widget.contextValue.id
        : widget.contextValue.clubContextId;
    if (clubContextId == null || overview is! ClubHomeServices) return null;
    try {
      final home = await (overview as ClubHomeServices).loadClubHome(
        clubContextId,
      );
      if (!mounted) return null;
      final name = home.ownName?.trim();
      return (
        name: name == null || name.isEmpty ? null : name,
        title: _boardOfficesLabel(AppStrings.of(context), home.ownOffices),
      );
    } catch (error) {
      AppErrors.caught('product_shell._ownClubSummary', error);
      return null;
    }
  }

  /// Your own person's name in the active team; null without one.
  Future<String?> _ownNameInTeam() async {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) return null;
    try {
      final roles = await widget.roster
          .listTeamRoles(clubId: widget.contextValue.clubId, teamId: teamId)
          .timeout(const Duration(seconds: 15));
      return roles.roles.where((role) => role.isSelf).firstOrNull?.name;
    } catch (error) {
      AppErrors.caught('product_shell._ownNameInTeam', error);
      return null;
    }
  }

  void _refreshOwnProfile() {
    if (!mounted) return;
    setState(() {
      _ownSummary = _loadOwnSummary();
    });
  }

  StreamSubscription<String>? _pushTaps;
  AppLifecycleListener? _pushResume;
  bool _offeringPush = false;

  /// Push (FCM): keeps this device registered, opens tapped notifications,
  /// and offers notifications the first time there is something unread.
  Future<void> _startPush() async {
    final push = widget.push;
    if (!push.supported) return;
    try {
      await push.registerIfAllowed();
      _pushTaps = push.openedRoutes.listen(_openPushRoute);
      final initial = await push.initialRoute();
      if (initial != null) _openPushRoute(initial);
      await _maybeOfferPush();
      // Something unread may arrive while the app is in the background.
      _pushResume = AppLifecycleListener(
        onResume: () => unawaited(
          _maybeOfferPush().catchError(
            (Object error) =>
                AppErrors.caught('product_shell._maybeOfferPush', error),
          ),
        ),
      );
    } catch (error) {
      AppErrors.caught('product_shell._startPush', error);
    }
  }

  /// Event pages are pushed like any opened event; the inbox is a tab.
  void _openPushRoute(String route) {
    if (!mounted || PushRoutes.safe(route) == null) return;
    route.startsWith(ProductRouteContract.inbox)
        ? _router.go(route)
        : unawaited(_router.push(route));
  }

  Future<void> _maybeOfferPush() async {
    if (_offeringPush) return;
    _offeringPush = true;
    try {
      await _offerPushOnce();
    } finally {
      _offeringPush = false;
    }
  }

  Future<void> _offerPushOnce() async {
    final push = widget.push;
    if (await push.wasOffered()) return;
    if (await push.permission() != PushPermission.notDetermined) return;
    final center = await widget.messaging.listNotifications();
    if (center.unreadCount == 0 || !mounted) return;
    await push.markOffered();
    if (!mounted) return;
    final strings = AppStrings.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('push-offer'),
        icon: const Icon(Icons.notifications_active_outlined),
        title: Text(
          strings.feature('Få notiser om kallelser och meddelanden?'),
        ),
        content: Text(
          strings.feature(
            'TeamZone kan meddela dig när du får en kallelse, en påminnelse eller ett nytt meddelande. Notisen visar typ av aktivitet, lag och tid – aldrig namn eller meddelandetext. Du kan ändra det i Inställningar.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.feature('Inte nu')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.feature('Tillåt notiser')),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    // Message pushes also follow the inbox setting; turning push on here
    // turns that on too.
    if (await push.requestAndRegister()) {
      await widget.messaging.setPushEnabled(true, _newUuid());
    }
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
        builder: (_, state) => _ProfileSettingsSurface(
          openProfile: state.uri.queryParameters['tab'] == 'profile',
          editorial: widget.editorial,
          contexts: widget.contexts,
          roster: widget.roster,
          onContextsChanged: widget.onContextsChanged,
          legal: widget.legal,
          calendarPreferences: widget.calendarPreferences,
          profileServices: widget.profileServices,
          onOwnProfileChanged: _refreshOwnProfile,
          messaging: widget.messaging,
          membership: widget.membership,
        ),
      ),
      GoRoute(
        path: ProductRouteContract.support,
        builder: (_, _) => _SupportAdminSurface(
          membership: widget.membership,
          profile: widget.profileServices,
          messaging: widget.messaging,
          assistant: widget.overview is AssistantTaskSupportServices
              ? widget.overview as AssistantTaskSupportServices
              : null,
        ),
      ),
      GoRoute(
        path: ProductRouteContract.assistant,
        builder: (_, state) => _AssistantCoachHoldingSurface(
          page: AssistantPageContext(
            state.uri.queryParameters['from'] ?? '/home',
          ),
          contexts: widget.contexts,
          calendar: widget.calendar,
          onOpenTask: _openAssistantTask,
          onOpenSettings: () => _openAssistant(settings: true),
          settingsOnly: state.uri.queryParameters['settings'] == '1',
          assistantIdentity: widget.assistantIdentity,
          assistantPresentation: widget.assistantPresentation,
          overview: widget.overview,
          contextValue: _contextForLocation(
            state.uri.queryParameters['from'] ?? '/home',
          ),
          onNavigate: _navigateFromSurface,
        ),
      ),
      GoRoute(
        path: '${ProductRouteContract.calendar}/event/:eventId',
        builder: (_, state) {
          final requestedContext = state.uri.queryParameters['context'];
          if (requestedContext != null &&
              !widget.contexts.any(
                (value) => value.matchesId(requestedContext),
              )) {
            return const _NotFoundSurface();
          }
          return _EventDetailsPage(
            eventId: state.pathParameters['eventId']!,
            key: ValueKey(
              '${state.pathParameters['eventId']}:${state.uri.queryParameters['context']}:${state.uri.queryParameters['tab']}:${state.uri.queryParameters['decline']}',
            ),
            initialParticipants:
                state.uri.queryParameters['tab'] == 'participants',
            initialPreparation:
                state.uri.queryParameters['tab'] == 'preparation',
            // "Kan inte…" on a callup notification.
            initialDeclineCallupId: state.uri.queryParameters['decline'],
            onChanged: () => setState(() => _assistantTaskRevision++),
            contextValue: _contextForLocation(state.uri.toString()),
            calendar: widget.calendar,
            roster: widget.roster,
            match: widget.match,
            matchSpaceV2: widget.matchSpaceV2,
            onNavigate: (fallback) =>
                _router.canPop() ? _router.pop() : _router.go(fallback),
          );
        },
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
            membership: widget.membership,
          ),
          onBack: () => _router.canPop()
              ? _router.pop()
              : _router.go('${ProductRouteContract.team}?tab=roster'),
        ),
      ),
      // Statistik moved to Laget; old links keep working.
      GoRoute(
        path: ProductRouteContract.statistics,
        redirect: (_, _) => ProductRouteContract.teamStatistics,
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
                  clubHome: widget.overview is ClubHomeServices
                      ? widget.overview as ClubHomeServices
                      : null,
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
                  initialEventType: state.uri.queryParameters['type'],
                )
              : destination.path == '/inbox'
              ? _InboxSurface(
                  contextValue: widget.contextValue,
                  contexts: widget.contexts,
                  messaging: widget.messaging,
                  membership: widget.membership,
                  roster: widget.roster,
                  supportAdminAccess: _supportAdminAccess,
                  initialThreadId: state.uri.queryParameters['thread'],
                  initialPoolInterestId: state.uri.queryParameters['pool'],
                  initialPoolListingId: state.uri.queryParameters['poolad'],
                  initialAction: state.uri.queryParameters['action'],
                  initialRecipients: [
                    for (final id
                        in (state.uri.queryParameters['to'] ?? '').split(','))
                      if (id.isNotEmpty) id,
                  ],
                  onNavigate: _navigateFromSurface,
                )
              : destination.path == ProductRouteContract.workspaces
              ? _WorkspacesSurface(
                  contextValue: widget.contextValue,
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
                  ownName: _ownName,
                  roster: widget.roster,
                  guardianContexts: [
                    for (final item in widget.contexts)
                      if (item.rolePackage == 'guardian') item,
                  ],
                  guardianChildAfterSwitch: _guardianChildAfterSwitch,
                  onGuardianChildElsewhere: (target, childId) {
                    _guardianChildAfterSwitch = (
                      contextId: target.id,
                      childId: childId,
                    );
                    widget.onContextChanged(target);
                  },
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

  TeamZoneContext _contextForLocation(String location) {
    final id = Uri.tryParse(location)?.queryParameters['context'];
    return widget.contexts.where((value) => value.matchesId(id)).firstOrNull ??
        widget.contextValue;
  }

  String get _currentPageLocation =>
      _router.routerDelegate.currentConfiguration.isEmpty
      ? _router.routeInformationProvider.value.uri.toString()
      : _router.state.uri.toString();

  void _onPageChanged() {
    final location = _currentPageLocation;
    if (_renderedPageLocation == location) return;
    _renderedPageLocation = location;
    // The nested Router also reports its initial state during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _openAssistant({bool settings = false}) async {
    final current = Uri.parse(_currentPageLocation);
    final source = current.path == ProductRouteContract.assistant
        ? current.queryParameters['from'] ?? '/home'
        : _currentPageLocation;
    await _router.push(
      Uri(
        path: ProductRouteContract.assistant,
        queryParameters: {'from': source, if (settings) 'settings': '1'},
      ).toString(),
    );
    if (mounted) {
      setState(() {
        _assistantTaskRevision++;
        _assistantPreference = widget.assistantIdentity.getPreference();
      });
    }
  }

  Future<void> _openAssistantTask(AssistantTask task) async {
    // Webtools (the booking manager) opens outside the app.
    if (task.route.startsWith('https://')) {
      await launchUrl(
        Uri.parse(task.route),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    if (task.isPersonalConflict) {
      await _openPersonalConflict(task);
      return;
    }
    if (task.task.kind == 'calendar_conflict') {
      await _editAssistantConflict(task);
      return;
    }
    if (!task.isMatchFollowup) {
      await _router.push(task.route);
      return;
    }
    final event = await widget.calendar.getEventDetails(task.eventId);
    final team = event.teams
        .where((value) => value['team_id'] == task.context.teamId)
        .firstOrNull;
    final canManage =
        team != null &&
        (team['relation'] == 'primary' ||
            (team['capabilities'] as List? ?? const []).contains('co_manage'));
    if (!mounted) return;
    if (task.stale ||
        !task.context.can('match.live') ||
        !canManage ||
        !event.can('match_live') ||
        event.type != 'match' ||
        event.archivedAt != null ||
        !['scheduled', 'completed'].contains(event.state) ||
        event.endsAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Matchen kan inte följas upp här längre. Uppgifterna uppdateras.',
          ),
        ),
      );
      return;
    }
    final snapshot = await widget.match.getSnapshot(event.id);
    if (!mounted) return;
    final label =
        '${event.title} · ${task.context.teamName} · ${task.context.clubName}';
    bool? saved;
    if (snapshot?.state != 'completed') {
      saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RegisterResultDialog(
          event: event,
          match: widget.match,
          snapshot: snapshot,
          contextLabel: label,
        ),
      );
    } else {
      final report = await widget.match.getReport(event.id);
      if (!mounted) return;
      if (!report.canEdit || report.body.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Matchrapporten är redan skriven eller kan inte redigeras. Uppgifterna uppdateras.',
            ),
          ),
        );
        return;
      }
      saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WrittenReportDialog(
          eventId: event.id,
          match: widget.match,
          report: report,
          contextLabel: label,
        ),
      );
    }
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            snapshot?.state == 'completed'
                ? 'Matchrapporten är sparad.'
                : 'Slutresultatet är sparat. Matchen är avslutad.',
          ),
        ),
      );
    }
  }

  Future<void> _openPersonalConflict(AssistantTask task) async {
    final service = widget.overview;
    if (service is! PersonalCalendarConflictServices ||
        task.overlappingEvent == null) {
      return;
    }
    final fresh = await (service as PersonalCalendarConflictServices)
        .loadPersonalCalendarConflicts();
    if (!mounted) return;
    if (!(fresh['tasks'] as List).any(
      (row) => row['route'] == task.task.route,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Den personliga krocken är inte längre aktuell. Listan uppdateras.',
          ),
        ),
      );
      return;
    }
    final events = [
      await widget.calendar.getEventDetails(task.eventId),
      await widget.calendar.getEventDetails(task.overlappingEvent!.id),
    ];
    if (!mounted) return;
    bool canEdit(EventDetails event) {
      final context = task.contextForEvent(event.id);
      return context.can('event.manage') &&
          event.can('revise') &&
          event.archivedAt == null &&
          event.state == 'scheduled' &&
          event.teams.any(
            (team) =>
                team['team_id'] == context.teamId &&
                (team['relation'] == 'primary' ||
                    (team['capabilities'] as List? ?? const []).contains(
                      'co_manage',
                    )),
          );
    }

    final choice = await showDialog<(EventDetails, bool)>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(
          AppStrings.of(context).feature('Hantera din kalenderkrock'),
        ),
        children: [
          for (final event in events) ...[
            ListTile(
              title: Text(event.title),
              subtitle: Text(task.eventContextLabel(event.id)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop((event, false)),
              child: Text(
                AppStrings.of(context).feature('Öppna aktivitet och svara'),
              ),
            ),
            if (canEdit(event))
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop((event, true)),
                child: Text(AppStrings.of(context).feature('Ändra tid')),
              ),
          ],
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final (selected, edit) = choice;
    if (!edit) {
      await _router.push(
        Uri(
          path: ProductRouteContract.calendarEvent(selected.id),
          queryParameters: {
            'context': task.contextForEvent(selected.id).id,
            'tab': 'participants',
          },
        ).toString(),
      );
      return;
    }
    final event = await widget.calendar.getEventDetails(selected.id);
    if (!mounted || !canEdit(event)) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AssistantEventTimeDialog(
        event: event,
        calendar: widget.calendar,
        teamLabel: task.eventContextLabel(event.id),
      ),
    );
  }

  Future<void> _editAssistantConflict(AssistantTask task) async {
    if (task.stale ||
        !task.context.can('event.manage') ||
        task.overlappingEvent == null) {
      return;
    }
    final first = await widget.calendar.getEventDetails(task.eventId);
    final second = await widget.calendar.getEventDetails(
      task.overlappingEvent!.id,
    );
    if (!mounted) return;
    if (first.state != 'scheduled' ||
        second.state != 'scheduled' ||
        first.archivedAt != null ||
        second.archivedAt != null ||
        !first.startsAt.isBefore(second.endsAt) ||
        !second.startsAt.isBefore(first.endsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Krocken är inte längre aktuell. Uppgifterna uppdateras.',
          ),
        ),
      );
      return;
    }
    bool canEdit(EventDetails event) =>
        event.can('revise') &&
        event.teams.any(
          (team) =>
              team['team_id'] == task.context.teamId &&
              (team['relation'] == 'primary' ||
                  (team['capabilities'] as List? ?? const []).contains(
                    'co_manage',
                  )),
        );
    final selected = await showDialog<EventDetails>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(
          AppStrings.of(context).feature('Vilken aktivitet vill du flytta?'),
        ),
        children: [
          for (final event in [first, second])
            ListTile(
              title: Text(event.title),
              subtitle: Text(
                '${task.context.clubName} · ${task.context.teamName}${canEdit(event) ? '' : ' · Kan endast visas'}',
              ),
              enabled: canEdit(event),
              onTap: () => Navigator.of(dialogContext).pop(event),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final event = await widget.calendar.getEventDetails(selected.id);
    if (!mounted) return;
    if (!canEdit(event) ||
        event.archivedAt != null ||
        event.state != 'scheduled') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aktiviteten kan inte ändras längre. Uppdatera och försök igen.',
          ),
        ),
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AssistantEventTimeDialog(
        event: event,
        calendar: widget.calendar,
        teamLabel: '${task.context.clubName} · ${task.context.teamName}',
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(
              context,
            ).feature('Tiden är sparad. Kalenderkrocken kontrolleras igen.'),
          ),
        ),
      );
    }
  }

  void _navigateFromSurface(String path) {
    // Home's cards may name the referee board.
    if (path == _refereeBoardRoute) {
      _openAction(path);
      return;
    }
    final location = ProductRouteContract.canonicalizeLocation(path);
    if (location.startsWith('${ProductRouteContract.calendar}/event/')) {
      _router.push(location);
    } else {
      _router.go(location);
    }
  }

  int _indexForBottomNav(String location, List<String> order) {
    final index = order.indexWhere((path) => location.startsWith(path));
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_startPush()),
    );
    unawaited(_loadPublicPage());
    // All imperative pages in this shell have standalone GoRoutes. Reflect
    // their top-most URI on web so pushed event/member pages can be copied
    // and opened directly without sacrificing return-to-origin on close.
    if (kIsWeb) GoRouter.optionURLReflectsImperativeAPIs = true;
    _supportAdminAccess = widget.membership
        .isSupportAdmin()
        .timeout(const Duration(seconds: 15))
        .catchError((_) => false);
    _pendingTeamRequests = _loadPendingTeamRequests();
    _assistantPreference = widget.assistantIdentity.getPreference();
    unawaited(
      Future.sync(widget.profileServices.recordActivity).catchError((_) {}),
    );
    _locationHistory.add(_router.routeInformationProvider.value.uri.toString());
    _router.routeInformationProvider.addListener(_recordLocation);
    _router.routerDelegate.addListener(_onPageChanged);
  }

  Future<int> _loadPendingTeamRequests() async {
    if (!widget.contextValue.can('club.memberships.manage')) return 0;
    try {
      final requests = await widget.membership
          .listTeamCreationRequests(clubId: widget.contextValue.clubId)
          .timeout(const Duration(seconds: 15));
      return requests.where((item) => item.state == 'pending').length;
    } catch (error) {
      AppErrors.caught('product_shell._loadPendingTeamRequests', error);

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
      _refereeSummary = _loadRefereeSummary();
      _publicUrl = null;
      unawaited(_loadPublicPage());
      _ownSummary = _loadOwnSummary();
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
    unawaited(_pushTaps?.cancel());
    _pushResume?.dispose();
    _router.routeInformationProvider.removeListener(_recordLocation);
    _router.routerDelegate.removeListener(_onPageChanged);
    _router.dispose();
    _ownName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _router.routeInformationProvider,
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final location = Uri.parse(_currentPageLocation).path;
        final mediaSize = MediaQuery.sizeOf(context);
        final width = mediaSize.width;
        final usesSidebar = AppBreakpoints.usesNavigationRail(width);
        final showAssistantPanel = !_assistantUsesFab(context);
        // EventDetails is a full page with its own header (centered title,
        // close button) — showing the shell's own context-picker bar above
        // it as well would stack two app bars.
        // On phones Min assistent opens full screen: its own app bar and
        // back button, without the shell bar or bottom navigation.
        final assistantFullscreen =
            !showAssistantPanel && location == ProductRouteContract.assistant;
        final hidesShellAppBar =
            assistantFullscreen ||
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
          onContextsChanged: widget.onContextsChanged,
          onTeamCreated: widget.onTeamCreated,
          pendingTeamRequests: _pendingTeamRequests,
          onTeamRequestsChanged: _refreshPendingTeamRequests,
          refereeSummary: _refereeSummary,
          onOpenRefereeBoard: _openRefereeBoard,
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
                    notificationPredicate: _scrollsUnderAppBar,
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
                          key: _pageAreaKey,
                          children: [
                            Positioned.fill(
                              // The shell handles back itself (see
                              // _handleSystemBack). Without this, the nested
                              // router's "nothing to pop" on Home, Kalender,
                              // Laget and Inkorg reaches the app, and Android's
                              // predictive back (targetSdk 36) closes the app.
                              child:
                                  NotificationListener<NavigationNotification>(
                                    onNotification: (notification) {
                                      if (notification.canHandlePop) {
                                        return false;
                                      }
                                      const NavigationNotification(
                                        canHandlePop: true,
                                      ).dispatch(context);
                                      return true;
                                    },
                                    child: Router(
                                      routerDelegate: _router.routerDelegate,
                                      routeInformationParser:
                                          _router.routeInformationParser,
                                      routeInformationProvider:
                                          _router.routeInformationProvider,
                                      backButtonDispatcher:
                                          _backButtonDispatcher,
                                    ),
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
                              Positioned.fill(
                                child: DraggableAssistantFab(
                                  child: AssistantTaskBadge(
                                    hideWhenEmpty: true,
                                    refreshToken: (
                                      _assistantTaskRevision,
                                      _currentPageLocation,
                                      widget.contexts,
                                      widget.contextValue.id,
                                    ),
                                    load: () => loadAssistantTasks(
                                      contexts: widget.contexts,
                                      activeContext: _contextForLocation(
                                        _currentPageLocation,
                                      ),
                                      overview: widget.overview,
                                      loadEvent:
                                          widget.calendar.getEventDetails,
                                    ),
                                    child: _AssistantCoachMobileFab(
                                      onPressed: _openAssistant,
                                      preference: _assistantPreference,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (showAssistantPanel &&
                          location != ProductRouteContract.assistant)
                        _AssistantCoachSidePanel(
                          contextValue: _contextForLocation(
                            _currentPageLocation,
                          ),
                          tasks: AssistantTaskSections(
                            key: ValueKey(_assistantTaskRevision),
                            contexts: widget.contexts,
                            activeContext: _contextForLocation(
                              _currentPageLocation,
                            ),
                            page: AssistantPageContext(_currentPageLocation),
                            overview: widget.overview,
                            loadEvent: widget.calendar.getEventDetails,
                            preparation: widget.calendar.preparation,
                            calendar: widget.calendar,
                            onOpen: _openAssistantTask,
                          ),
                          onOpen: _openAssistant,
                          onSettings: () => _openAssistant(settings: true),
                          preference: _assistantPreference,
                          onRefresh: () =>
                              setState(() => _assistantTaskRevision++),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: usesSidebar || assistantFullscreen
                ? null
                : LayoutBuilder(
                    builder: (context, constraints) {
                      const order = _bottomNavOrder;
                      final more = _moreActions(context);
                      final inMore = more.any(
                        (action) =>
                            action.route.startsWith('/') &&
                            Uri.parse(location).path ==
                                Uri.parse(action.route).path &&
                            !order.contains(Uri.parse(action.route).path),
                      );
                      final navigationBar = NavigationBar(
                        selectedIndex: inMore
                            ? order.indexOf(_morePath)
                            : _indexForBottomNav(location, order),
                        onDestinationSelected: (index) =>
                            order[index] == _morePath
                            ? _showMoreMenu(
                                context: context,
                                actions: more,
                                onOpen: _openAction,
                              )
                            : _router.go(order[index]),
                        labelBehavior:
                            MediaQuery.textScalerOf(context).scale(1) >= 1.5
                            ? NavigationDestinationLabelBehavior
                                  .onlyShowSelected
                            : NavigationDestinationLabelBehavior.alwaysShow,
                        destinations: [
                          for (final path in order)
                            NavigationDestination(
                              key: path == _morePath
                                  ? const Key('bottom-nav-more')
                                  : null,
                              icon: Icon(
                                path == _morePath
                                    ? Icons.more_horiz
                                    : _destinationFor(path).icon,
                              ),
                              label: path == _morePath
                                  ? strings.feature('Mer')
                                  : strings.destination(path),
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
                      final homeIndex = order.indexOf(
                        ProductRouteContract.home,
                      );
                      final itemWidth = constraints.maxWidth / order.length;
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
                                    currentLocation: _currentPageLocation,
                                    onNavigate: _openAction,
                                    publicUrl: _publicUrl,
                                    refereeLabel: _refereeLabel,
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
  final groups = groupContextsForPicker(contexts, activeContext);
  final colors = Theme.of(context).colorScheme;
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
          // Each club as a title, as in the inbox, with its teams below:
          // the active team first, then the active club, then A–Ö.
          for (final group in groups) ...[
            Padding(
              key: ValueKey('context-club-${group.clubName}'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Material(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          group.clubName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        '${group.contexts.length}',
                        style: Theme.of(sheetContext).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            for (final item in group.contexts)
              item.id == activeContext.id
                  ? ListTile(
                      key: ValueKey('context-${item.id}'),
                      leading: const Icon(Icons.check_circle),
                      title: Text(
                        item.teamName ?? strings.feature('Hela klubben'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${strings.feature('Aktivt lag')} · ${_contextRolesLabel(strings, item)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: true,
                    )
                  : ListTile(
                      key: ValueKey('context-${item.id}'),
                      leading: const Icon(Icons.swap_horiz),
                      title: Text(
                        item.teamName ?? strings.feature('Hela klubben'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _contextRolesLabel(strings, item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        onContextChanged(item);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
          ],
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
  } catch (error) {
    AppErrors.caught('product_shell._createTeamFromContextPicker', error);

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
  } catch (error) {
    AppErrors.caught('product_shell._showTeamCreationRequests', error);

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

/// One shortcut in the swipe-up quick actions sheet: an icon, a label and
/// the route it navigates to. A route with an `?action=` starts doing
/// something on its page; one without just opens a destination.
typedef _QuickAction = ({IconData icon, String label, String route});

extension on _QuickAction {
  bool get startsAction =>
      Uri.parse(route).queryParameters.containsKey('action');

  /// The destination the shortcut belongs to, e.g. '/team'.
  String get page => Uri.parse(route).path;
}

/// Builds the role-aware shortcut list for the swipe-up quick actions
/// sheet: "a shortcut to every important function for that particular
/// person" (a coach gets team-management/event shortcuts, a player gets
/// event/inbox shortcuts, and so on) — driven by the same capabilities
/// already used to gate the drawer's admin links, not a separate
/// per-role-package list, so it stays correct for scoped/partial roles
/// (e.g. a team-only leader) without extra cases.
///
/// Within each page the first action is that page's main one: it is what
/// the sheet leads with on pages that have no actions of their own.
/// Special routes the shell opens itself rather than through the router.
const _refereeBoardRoute = 'teamzone:referee-board';
const _clubTeamRequestsRoute = '/team?action=team-requests';
const _ownProfileRoute = 'teamzone:own-profile';

/// What the fifth button "Mer" holds, by role and capability. Leaders find
/// Utveckling and Statistik under Arbetsytor.
List<_QuickAction> _moreActionsFor(
  BuildContext context,
  TeamZoneContext contextValue, {
  String? publicUrl,
  String? refereeLabel,
}) {
  final strings = AppStrings.of(context);
  final leader =
      contextValue.rolePackage == 'leader' ||
      contextValue.rolePackages.contains('leader');
  return [
    // Utveckling is reached through Arbetsytor until the workspaces open
    // for more roles.
    if (leader)
      (
        icon: _destinationFor(ProductRouteContract.workspaces).icon,
        label: strings.destination(ProductRouteContract.workspaces),
        route: ProductRouteContract.workspaces,
      ),
    if (contextValue.can('event.manage') ||
        contextValue.can('event.attendance.manage'))
      (
        icon: Icons.query_stats_outlined,
        label: strings.feature('Lagstatistik'),
        route: ProductRouteContract.teamStatistics,
      ),
    if (_hasEconomyCapability(contextValue))
      (
        icon: Icons.account_balance_wallet_outlined,
        label: strings.feature('Ekonomi'),
        route: ProductRouteContract.economy,
      ),
    if (_hasBoardCapability(contextValue))
      (
        icon: Icons.badge_outlined,
        label: strings.feature('Styrelse'),
        route: ProductRouteContract.board,
      ),
    if (refereeLabel != null)
      (
        icon: Icons.assignment_ind_outlined,
        label: refereeLabel,
        route: _refereeBoardRoute,
      ),
    if (contextValue.can('club.billing.manage'))
      (
        icon: Icons.payments_outlined,
        label: strings.feature('Abonnemang'),
        route: ProductRouteContract.billing,
      ),
    if (contextValue.can('publication.manage'))
      (
        icon: Icons.newspaper_outlined,
        label: strings.feature('Nyhetsredaktion'),
        route: ProductRouteContract.editorial,
      ),
    if (contextValue.can('publication.manage') ||
        contextValue.can('team.roster.manage'))
      (
        icon: Icons.public_outlined,
        label: strings.feature('Publika sidor'),
        route: ProductRouteContract.publication,
      ),
    if (publicUrl != null)
      (
        icon: Icons.language,
        label: strings.feature('Vår publika sida'),
        route: publicUrl,
      ),
    (
      icon: Icons.person_outline,
      label: strings.feature('Min profil'),
      route: _ownProfileRoute,
    ),
    (
      icon: Icons.settings_outlined,
      label: strings.destination(ProductRouteContract.settings),
      route: ProductRouteContract.settings,
    ),
  ];
}

/// The "Mer" sheet: the fifth button's destinations as a grid.
Future<void> _showMoreMenu({
  required BuildContext context,
  required List<_QuickAction> actions,
  required ValueChanged<String> onOpen,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) {
    final theme = Theme.of(sheetContext);
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('more-menu'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.of(sheetContext).feature('Mer'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 480 ? 4 : 3;
                final width =
                    (constraints.maxWidth - 8 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in actions)
                      SizedBox(
                        width: width,
                        child: _QuickActionTile(
                          action: action,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            onOpen(action.route);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  },
);

List<_QuickAction> _quickActionsFor(
  BuildContext context,
  TeamZoneContext contextValue, {
  String? publicUrl,
  String? refereeLabel,
}) {
  final strings = AppStrings.of(context);
  final canManageRoster =
      contextValue.can('club.memberships.manage') ||
      contextValue.can('team.roster.manage');
  final canManageEvents = contextValue.can('event.manage');
  final canAnnounce =
      contextValue.rolePackage == 'leader' ||
      contextValue.can('club.memberships.manage');
  return [
    // Calendar.
    if (canManageEvents) ...[
      (
        icon: Icons.add_circle_outline,
        label: strings.feature('Skapa nytt event'),
        route: ProductRouteContract.calendarCreateEvent(),
      ),
      (
        icon: Icons.directions_run,
        label: strings.feature('Ny träning'),
        route: ProductRouteContract.calendarCreateEvent(type: 'training'),
      ),
      (
        icon: Icons.sports_soccer,
        label: strings.feature('Ny match'),
        route: ProductRouteContract.calendarCreateEvent(type: 'match'),
      ),
    ],
    // Team.
    if (canManageRoster) ...[
      (
        icon: Icons.person_add_alt_1,
        label: strings.feature('Bjud in spelare'),
        route: ProductRouteContract.teamInvite(),
      ),
      (
        icon: Icons.shield_outlined,
        label: strings.feature('Ledare och roller'),
        route: ProductRouteContract.teamRoles(),
      ),
      (
        icon: Icons.assignment_outlined,
        label: strings.feature('Kontaktuppdatering'),
        route: ProductRouteContract.teamIntake(),
      ),
    ],
    if (contextValue.can('club.memberships.manage'))
      (
        icon: Icons.how_to_reg_outlined,
        label: strings.feature('Medlemsansökningar'),
        route: ProductRouteContract.teamApplications(),
      ),
    // Inbox.
    (
      icon: Icons.edit_outlined,
      label: strings.feature('Skicka meddelande'),
      route: ProductRouteContract.inboxCompose(),
    ),
    if (canAnnounce)
      (
        icon: Icons.campaign_outlined,
        label: strings.feature('Nytt informationsmeddelande'),
        route: ProductRouteContract.inboxAnnouncement(),
      ),
    // Destinations.
    (
      icon: _destinationFor(ProductRouteContract.calendar).icon,
      label: strings.destination(ProductRouteContract.calendar),
      route: ProductRouteContract.calendar,
    ),
    (
      icon: _destinationFor(ProductRouteContract.team).icon,
      label: canManageRoster
          ? strings.feature('Hantera laget')
          : strings.destination(ProductRouteContract.team),
      route: ProductRouteContract.team,
    ),
    (
      icon: _destinationFor(ProductRouteContract.inbox).icon,
      label: strings.feature('Öppna inkorgen'),
      route: ProductRouteContract.inbox,
    ),
    // Everything under "Mer" too: workspaces, statistics, club areas, the
    // public page, the profile and the settings.
    ..._moreActionsFor(
      context,
      contextValue,
      publicUrl: publicUrl,
      refereeLabel: refereeLabel,
    ),
  ];
}

/// Splits the actions for the page the user is on: that page's own actions
/// lead ("Gör nu"); elsewhere each page's main action does. Every other
/// action stays reachable under "Fler genvägar".
({List<_QuickAction> doNow, List<_QuickAction> more, List<_QuickAction> goTo})
_groupQuickActions(List<_QuickAction> actions, String currentLocation) {
  final current = Uri.parse(currentLocation).path;
  final startsAction = [
    for (final action in actions)
      if (action.startsAction) action,
  ];
  var doNow = [
    for (final action in startsAction)
      if (current == action.page || current.startsWith('${action.page}/'))
        action,
  ];
  if (doNow.isEmpty) {
    final seenPages = <String>{};
    doNow = [
      for (final action in startsAction)
        if (seenPages.add(action.page)) action,
    ];
  }
  return (
    doNow: doNow,
    more: [
      for (final action in startsAction)
        if (!doNow.contains(action)) action,
    ],
    goTo: [
      for (final action in actions)
        if (!action.startsAction) action,
    ],
  );
}

/// The swipe-up quick actions sheet, opened from the Home button in the
/// phone bottom nav (see the GestureDetector built alongside NavigationBar
/// in _ProductShellState.build).
Future<void> _showQuickActionsMenu({
  required BuildContext context,
  required TeamZoneContext contextValue,
  required String currentLocation,
  required ValueChanged<String> onNavigate,
  String? publicUrl,
  String? refereeLabel,
}) {
  final strings = AppStrings.of(context);
  final groups = _groupQuickActions(
    _quickActionsFor(
      context,
      contextValue,
      publicUrl: publicUrl,
      refereeLabel: refereeLabel,
    ),
    currentLocation,
  );
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      void open(_QuickAction action) {
        Navigator.of(sheetContext).pop();
        onNavigate(action.route);
      }

      Widget sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  strings.feature('Genvägar'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 16),
              if (groups.doNow.isNotEmpty) ...[
                sectionTitle(strings.feature('Gör nu')),
                for (final action in groups.doNow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () => open(action),
                      icon: Icon(action.icon),
                      label: Text(action.label),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              if (groups.more.isNotEmpty) ...[
                sectionTitle(strings.feature('Fler genvägar')),
                // One scrolling row, so "Gör nu" keeps the room.
                SingleChildScrollView(
                  key: const Key('quick-actions-more'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      for (final action in groups.more)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: Icon(action.icon, size: 18),
                            label: Text(action.label),
                            onPressed: () => open(action),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (groups.goTo.isNotEmpty) ...[
                sectionTitle(strings.feature('Gå till')),
                SingleChildScrollView(
                  key: const Key('quick-actions-go-to'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final action in groups.goTo)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 96,
                            child: _QuickActionTile(
                              action: action,
                              onTap: () => open(action),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// One destination in the quick actions grid: a tonal icon over its label.
class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action, required this.onTap});
  final _QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.secondaryContainer,
                foregroundColor: theme.colorScheme.onSecondaryContainer,
                child: Icon(action.icon, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    required this.onContextsChanged,
    required this.onTeamCreated,
    required this.pendingTeamRequests,
    required this.onTeamRequestsChanged,
    required this.onSignOut,
    required this.closeDrawer,
    required this.onOpenOwnProfile,
    required this.ownSummary,
    this.refereeSummary,
    this.onOpenRefereeBoard,
  });

  /// REF-02: the clubs where the person is domaransvarig or pays referees.
  final Future<RefereeSummary>? refereeSummary;
  final void Function(
    ({String id, String name, bool canManage, bool canPay, int pendingReports})
    club,
  )?
  onOpenRefereeBoard;

  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final String currentLocation;
  final ValueChanged<String> onNavigate;
  final ValueChanged<TeamZoneContext> onContextChanged;
  final MembershipServices membership;
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
        _hasBoardCapability(contextValue);
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
                              name.trim().isEmpty
                                  ? strings.feature('Min profil')
                                  : name,
                              key: const Key('drawer-own-name'),
                              textAlign: TextAlign.center,
                              // A login address as the name stays on one line.
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        );
                      },
                    ),
                    FutureBuilder<_OwnSummary>(
                      future: ownSummary,
                      builder: (context, snapshot) => Text(
                        snapshot.data?.title ??
                            _contextRolesLabel(strings, contextValue),
                        key: const Key('drawer-own-roles'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
                if (contextValue.rolePackage == 'leader' ||
                    contextValue.rolePackages.contains('leader'))
                  _NavPanelRow(
                    icon: _destinationFor(ProductRouteContract.workspaces).icon,
                    label: strings.destination(ProductRouteContract.workspaces),
                    selected: currentLocation.startsWith(
                      ProductRouteContract.workspaces,
                    ),
                    onTap: () => _go(ProductRouteContract.workspaces),
                  ),
                // REF-02: one row for the active club's referees.
                if (refereeSummary != null && onOpenRefereeBoard != null)
                  FutureBuilder<RefereeSummary>(
                    future: refereeSummary,
                    builder: (context, snapshot) {
                      final club = snapshot.data?.coordinatorClubs
                          .where((item) => item.id == contextValue.clubId)
                          .firstOrNull;
                      if (club == null) return const SizedBox.shrink();
                      final label = strings.feature(
                        club.canManage
                            ? 'Domartillsättning'
                            : 'Domarersättning',
                      );
                      return Tooltip(
                        message: label,
                        child: ListTile(
                          key: const Key('drawer-referee-board'),
                          leading: Icon(
                            club.canManage
                                ? Icons.assignment_ind_outlined
                                : Icons.payments_outlined,
                          ),
                          title: Text(label),
                          trailing: club.canManage && club.pendingReports > 0
                              ? Badge.count(count: club.pendingReports)
                              : null,
                          onTap: () => onOpenRefereeBoard!(club),
                        ),
                      );
                    },
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
/// Min assistent's button on the right edge, draggable up and down when it
/// is in the way. The place is kept on this device as a share of the
/// height, so it survives other screen sizes. Only the button takes
/// touches; the rest of the area passes them to the page.
class DraggableAssistantFab extends StatefulWidget {
  const DraggableAssistantFab({super.key, required this.child});
  final Widget child;

  @override
  State<DraggableAssistantFab> createState() => DraggableAssistantFabState();
}

class DraggableAssistantFabState extends State<DraggableAssistantFab> {
  static const _key = 'assistant_fab_position';
  static const _margin = 16.0;
  static const _buttonHeight = 64.0;

  /// 0 = the standard bottom place, 1 = as high as it goes.
  double _share = 0;
  double? _dragBottom;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getDouble(_key);
      if (saved != null && mounted) {
        setState(() => _share = saved.clamp(0.0, 1.0));
      }
    } catch (error) {
      AppErrors.caught('product_shell.DraggableAssistantFab.restore', error);
    }
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setDouble(_key, _share);
    } catch (error) {
      AppErrors.caught('product_shell.DraggableAssistantFab.save', error);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final range = (box.maxHeight - _buttonHeight - 2 * _margin).clamp(
        0.0,
        double.infinity,
      );
      final bottom = _dragBottom ?? _margin + _share * range;
      return Stack(
        children: [
          Positioned(
            right: _margin,
            bottom: bottom,
            child: Semantics(
              hint: AppStrings.of(
                context,
              ).feature('Dra uppåt eller nedåt för att flytta assistenten'),
              child: GestureDetector(
                key: const ValueKey('assistant-fab-drag'),
                onVerticalDragStart: (_) =>
                    setState(() => _dragBottom = bottom),
                onVerticalDragUpdate: (details) => setState(
                  () => _dragBottom = (_dragBottom! - details.delta.dy).clamp(
                    _margin,
                    _margin + range,
                  ),
                ),
                onVerticalDragEnd: (_) {
                  setState(() {
                    _share = range == 0
                        ? 0
                        : ((_dragBottom! - _margin) / range).clamp(0.0, 1.0);
                    _dragBottom = null;
                  });
                  unawaited(_save());
                },
                child: widget.child,
              ),
            ),
          ),
        ],
      );
    },
  );
}

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
/// "Huvudtränare" rather than "Ledare · Klubbfunktionär": your main title
/// (or first title) replaces the leader roles; playing is still shown.
/// The team picker's order: the active club first with the active team at
/// the top, then its club-wide context and its other teams A–Ö; then the
/// other clubs A–Ö, each with its club-wide context first and teams A–Ö.
List<({String clubName, List<TeamZoneContext> contexts})>
groupContextsForPicker(List<TeamZoneContext> contexts, TeamZoneContext active) {
  // Swedish order: å, ä and ö after z, in that order.
  String key(String value) => value
      .toLowerCase()
      .replaceAll('å', '{a')
      .replaceAll('ä', '{b')
      .replaceAll('ö', '{c');
  final byClub = <String, List<TeamZoneContext>>{};
  final names = <String, String>{};
  for (final item in contexts) {
    byClub.putIfAbsent(item.clubId, () => []).add(item);
    names[item.clubId] = item.clubName;
  }
  byClub.putIfAbsent(active.clubId, () => [active]);
  names.putIfAbsent(active.clubId, () => active.clubName);
  int rank(TeamZoneContext item) => item.id == active.id
      ? 0
      : item.teamName == null
      ? 1
      : 2;
  final clubIds = byClub.keys.toList()
    ..sort((a, b) {
      if (a == active.clubId) return -1;
      if (b == active.clubId) return 1;
      return key(names[a]!).compareTo(key(names[b]!));
    });
  return [
    for (final clubId in clubIds)
      (
        clubName: names[clubId]!,
        contexts: byClub[clubId]!.toList()
          ..sort((a, b) {
            final byRank = rank(a).compareTo(rank(b));
            if (byRank != 0) return byRank;
            return key(a.teamName ?? '').compareTo(key(b.teamName ?? ''));
          }),
      ),
  ];
}

String _contextRolesLabel(AppStrings strings, TeamZoneContext context) {
  final titles = [
    ...context.titles.map((key) => _titleLabel(strings, key)),
    ...context.customTitles,
  ];
  if (titles.isEmpty) {
    return context.roles.map(strings.domainValue).join(' · ');
  }
  final main = context.mainTitle == null
      ? titles.first
      : _titleLabel(strings, context.mainTitle!);
  return [
    main,
    if (context.roles.contains('player')) strings.domainValue('player'),
  ].join(' · ');
}

/// Title: your board offices in a club context, shown instead of the role.
typedef _OwnSummary = ({String? name, String? avatar, String? title});
