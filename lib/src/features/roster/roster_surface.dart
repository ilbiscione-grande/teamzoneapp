part of '../../app/teamzone_app.dart';

class _RosterSurface extends StatefulWidget {
  const _RosterSurface({
    required this.contextValue,
    required this.roster,
    required this.membership,
    required this.calendar,
    required this.onTeamCreated,
    this.initialTab,
    this.initialAction,
    this.profileServices = const UnconfiguredProfileServices(),
  });

  final TeamZoneContext contextValue;
  final RosterServices roster;
  final MembershipServices membership;
  final CalendarServices calendar;
  final Future<void> Function(String teamId) onTeamCreated;
  final ProfileServices profileServices;
  final String? initialTab;
  // Set by the swipe-up quick actions sheet's "Bjud in spelare" shortcut
  // (ProductRouteContract.teamInvite) to open the invitations/team-codes
  // sheet immediately on arrival — see _openInitialAction.
  final String? initialAction;

  @override
  State<_RosterSurface> createState() => _RosterSurfaceState();
}

class _RosterSurfaceState extends State<_RosterSurface> {
  late final AsyncDataController<List<RosterPersonSummary>> _data;
  late final AppListController<RosterPersonSummary> _list;
  List<RosterPersonSummary>? _syncedPeople;
  late int _selectedTab = _teamTabIndex(widget.initialTab);
  late Future<TeamRoles> _teamRoles = _loadTeamRoles();
  late Future<Map<String, String>> _avatars = _loadAvatars();

  /// Members' profile pictures; the list falls back to initials without.
  Future<Map<String, String>> _loadAvatars() async {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) return const {};
    try {
      return await widget.profileServices
          .teamAvatarUrls(clubId: widget.contextValue.clubId, teamId: teamId)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return const {};
    }
  }

  Future<TeamRoles> _loadTeamRoles() {
    final teamId = widget.contextValue.teamId;
    final roles = teamId == null
        ? Future<TeamRoles>.error(StateError('No team'))
        : Future.sync(
            () => widget.roster
                .listTeamRoles(
                  clubId: widget.contextValue.clubId,
                  teamId: teamId,
                )
                .timeout(const Duration(seconds: 15)),
          );
    // Builders show the failure; it may settle before any of them listens.
    return roles..ignore();
  }

  void _refreshTeamRoles() {
    if (!mounted) return;
    setState(() {
      _teamRoles = _loadTeamRoles();
      _avatars = _loadAvatars();
    });
  }

  void _openTeamRoles() => _openTeamRolesSheet(
    context,
    contextValue: widget.contextValue,
    roster: widget.roster,
    people: _data.state.data ?? const [],
    onChanged: () {
      _refreshTeamRoles();
      unawaited(_data.refresh());
    },
  ).then((_) => _refreshTeamRoles());

  @override
  void initState() {
    super.initState();
    _data = AsyncDataController<List<RosterPersonSummary>>(
      scopeKey: widget.contextValue.id,
      loader: _reload,
      isEmpty: (people) => people.isEmpty,
    );
    _list = AppListController<RosterPersonSummary>(
      searchText: (person) => [
        person.displayName,
        person.ageClass,
        person.teamName,
      ].whereType<String>().join(' '),
    )..setSort((a, b) => a.displayName.compareTo(b.displayName));
    _data.addListener(_syncList);
    unawaited(_data.load());
    _openInitialAction();
  }

  bool _openedInitialAction = false;

  /// Opens a capability-checked management sheet requested by a team deep
  /// link. This supports both invitations and the separate application queue.
  void _openInitialAction() {
    final action = widget.initialAction;
    if ((action != 'invite' && action != 'applications') ||
        _openedInitialAction) {
      return;
    }
    final canManage = action == 'applications'
        ? widget.contextValue.can('club.memberships.manage')
        : widget.contextValue.can('club.memberships.manage') ||
              widget.contextValue.can('team.roster.manage');
    if (!canManage) return;
    _openedInitialAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => action == 'applications'
            ? _MembershipReviewSheet(
                contextValue: widget.contextValue,
                membership: widget.membership,
                onApproved: _data.refresh,
              )
            : _InvitationAdminSheet(
                contextValue: widget.contextValue,
                roster: widget.roster,
                people: _data.state.data ?? const [],
              ),
      );
    });
  }

  void _syncList() {
    final people = _data.state.data;
    if (identical(people, _syncedPeople)) return;
    _syncedPeople = people;
    _list.replaceItems(people ?? const []);
  }

  Future<void> _showInvitations() async {
    if (!widget.contextValue.can('club.memberships.manage') &&
        !widget.contextValue.can('team.roster.manage')) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _InvitationAdminSheet(
        contextValue: widget.contextValue,
        roster: widget.roster,
        people: _data.state.data ?? const [],
      ),
    );
  }

  Future<void> _showMembershipReviews() async {
    if (!widget.contextValue.can('club.memberships.manage') &&
        !widget.contextValue.can('team.roster.manage')) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MembershipReviewSheet(
        contextValue: widget.contextValue,
        membership: widget.membership,
        onApproved: _data.refresh,
      ),
    );
  }

  Future<List<RosterPersonSummary>> _reload() {
    if (widget.contextValue.teamId == null) return Future.value(const []);
    return widget.roster.listPeople(
      clubId: widget.contextValue.clubId,
      teamId: widget.contextValue.teamId,
    );
  }

  Future<void> _createTeam() async {
    final strings = AppStrings.of(context);
    var draftName = '';
    final teamName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.feature('Skapa ytterligare lag')),
        content: TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => draftName = value,
          decoration: InputDecoration(labelText: strings.feature('Lagnamn')),
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
    if (teamName == null || !mounted) return;
    try {
      final teamId = await widget.membership
          .createTeam(
            clubId: widget.contextValue.clubId,
            teamName: teamName,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      await widget.onTeamCreated(teamId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.feature('Laget har skapats.'))),
        );
      }
    } catch (_) {
      if (mounted) {
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

  @override
  void didUpdateWidget(covariant _RosterSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) {
      _data.replaceScope(scopeKey: widget.contextValue.id, loader: _reload);
      _teamRoles = _loadTeamRoles();
      _avatars = _loadAvatars();
    }
    if (oldWidget.initialTab != widget.initialTab) {
      _selectedTab = _teamTabIndex(widget.initialTab);
    }
    if (oldWidget.initialAction != widget.initialAction) {
      _openedInitialAction = false;
      _openInitialAction();
    }
  }

  @override
  void dispose() {
    _data.removeListener(_syncList);
    _data.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (widget.contextValue.teamId == null) {
      return _NoTeamMembershipSurface(
        onManageConnections: () =>
            GoRouter.of(context).go(ProductRouteContract.settings),
      );
    }
    return DefaultTabController(
      key: ValueKey(_selectedTab),
      length: 3,
      initialIndex: _selectedTab,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: Semantics(
              container: true,
              label: strings.feature('Lagets innehåll'),
              child: TabBar(
                tabs: [
                  Tab(text: strings.feature('Översikt')),
                  Tab(text: strings.feature('Trupp')),
                  Tab(text: strings.feature('Kalender')),
                ],
                onTap: _selectTab,
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _TeamOverviewSurface(
                  contextValue: widget.contextValue,
                  roster: widget.roster,
                  onNavigate: (path) => GoRouter.of(context).go(path),
                  onOpenApplications: _showMembershipReviews,
                  onOpenInvitations: _showInvitations,
                  calendar: widget.calendar,
                ),
                _buildRoster(context),
                _TeamEventList(
                  contextValue: widget.contextValue,
                  calendar: widget.calendar,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectTab(int index) {
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
    const names = ['overview', 'roster', 'calendar'];
    // Keep the selected team tab as the current browser-history entry. A
    // subsequently pushed detail page can then return to this exact tab,
    // while tab changes themselves do not create a trail of near-identical
    // team pages.
    GoRouter.of(context).pushReplacement('/team?tab=${names[index]}');
  }

  Widget _buildRoster(BuildContext context) {
    final canManageClub = widget.contextValue.can('club.memberships.manage');
    final canManage =
        canManageClub || widget.contextValue.can('team.roster.manage');
    final canView = widget.contextValue.can('team.roster.view') || canManage;
    final canOpenPersonDetails = widget.contextValue.rolePackage != 'guardian';
    const supportedRoles = {'player', 'leader', 'guardian', 'club_functionary'};
    if (!canView || !supportedRoles.contains(widget.contextValue.rolePackage)) {
      return _StateCard(
        icon: Icons.lock_outline,
        title: AppStrings.of(context).feature('Truppen är inte tillgänglig'),
        message: AppStrings.of(
          context,
        ).feature('Din roll saknar behörighet att visa den här truppen.'),
        action: OutlinedButton.icon(
          onPressed: () =>
              GoRouter.of(context).go(ProductRouteContract.settings),
          icon: const Icon(Icons.settings_outlined),
          label: Text(AppStrings.of(context).feature('Inställningar')),
        ),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([_data, _list]),
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final state = _data.state;
        if (state.phase == AsyncDataPhase.loading) {
          return AppLoadingIndicator(label: strings.loading);
        }
        if (state.phase == AsyncDataPhase.failed) {
          return _StateCard(
            icon: Icons.sync_problem,
            title: AppStrings.of(context).feature('Truppen kunde inte laddas'),
            message: AppStrings.of(
              context,
            ).feature('Försök igen. Inga råa backendfel visas.'),
            action: FilledButton(
              onPressed: _data.load,
              child: Text(AppStrings.of(context).feature('Försök igen')),
            ),
          );
        }
        final allPeople = _list.visibleItems;
        final rosterList = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SearchBar(
                leading: const Icon(Icons.search),
                hintText: strings.feature('Sök i truppen'),
                onChanged: _list.setQuery,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  _RosterFilterChip(
                    label: strings.feature('Alla'),
                    selected: _list.filterKey == null,
                    onSelected: () => _setRosterStatusFilter(null),
                  ),
                  _RosterFilterChip(
                    label: strings.feature('Aktiva'),
                    selected: _list.filterKey == 'active',
                    onSelected: () => _setRosterStatusFilter('active'),
                  ),
                  _RosterFilterChip(
                    label: strings.feature('Tidigare'),
                    selected: _list.filterKey == 'other',
                    onSelected: () => _setRosterStatusFilter('other'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<TeamRoles>(
                future: _teamRoles,
                builder: (context, rolesSnapshot) {
                  final leaders = _leaderEntries(rolesSnapshot.data);
                  // Someone who leads the team is listed as a leader, not
                  // also as a former player (a new leader starts from an
                  // ended player assignment, and a player may become leader).
                  final leaderIds = {
                    for (final role
                        in rolesSnapshot.data?.roles ?? const <TeamRole>[])
                      if (role.role != 'player') role.personId,
                  };
                  final people = allPeople
                      .where(
                        (person) =>
                            person.assignmentState == 'active' ||
                            !leaderIds.contains(person.id),
                      )
                      .toList();
                  if (people.isEmpty && leaders.isEmpty) {
                    return _StateCard(
                      icon: Icons.search_off,
                      title: strings.feature('Inga matchande personer'),
                      message: strings.feature(
                        'Ändra sökningen eller rensa filtret.',
                      ),
                      action: TextButton(
                        onPressed: _list.clearQueryAndFilter,
                        child: Text(
                          strings.feature(
                            _list.query.isNotEmpty
                                ? 'Rensa sökning'
                                : 'Rensa filter',
                          ),
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      _refreshTeamRoles();
                      await _data.refresh();
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (state.isStale)
                          ListTile(
                            leading: const Icon(Icons.cloud_off),
                            title: Text(strings.offlineData),
                            subtitle: state.lastUpdated == null
                                ? null
                                : Text(strings.lastUpdated(state.lastUpdated!)),
                          ),
                        if (leaders.isNotEmpty)
                          _rosterGroupHeader(
                            strings.feature('Spelare'),
                            people.length,
                          ),
                        if (people.isEmpty && leaders.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              strings.feature('Inga spelare i truppen ännu.'),
                            ),
                          ),
                        for (final person in people) ...[
                          ListTile(
                            key: ValueKey('roster-player-${person.id}'),
                            leading: _RosterAvatar(
                              avatars: _avatars,
                              personId: person.id,
                              name: person.displayName,
                            ),
                            title: Text(person.displayName),
                            subtitle: Text(
                              [
                                _mainPositionLabel(
                                  strings,
                                  rolesSnapshot.data?.roles
                                      .where(
                                        (role) => role.personId == person.id,
                                      )
                                      .firstOrNull,
                                ),
                                person.teamName,
                              ].whereType<String>().join(' · '),
                            ),
                            trailing: canOpenPersonDetails
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: canOpenPersonDetails
                                ? () => _openPersonDetails(person)
                                : null,
                          ),
                          const Divider(),
                        ],
                        if (_list.hasMore)
                          TextButton.icon(
                            onPressed: _list.loadMore,
                            icon: const Icon(Icons.expand_more),
                            label: Text(strings.feature('Visa fler')),
                          ),
                        if (leaders.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _rosterGroupHeader(
                            strings.feature('Ledare'),
                            leaders.length,
                          ),
                          for (final (leader, roles) in leaders) ...[
                            ListTile(
                              key: ValueKey('roster-leader-${leader.personId}'),
                              leading: _RosterAvatar(
                                avatars: _avatars,
                                personId: leader.personId,
                                name: leader.name,
                              ),
                              title: Text(
                                leader.isSelf
                                    ? '${leader.name} (${strings.feature('du')})'
                                    : leader.name,
                              ),
                              subtitle: Text(
                                _leadTitleLabel(strings, leader) ??
                                    roles
                                        .map(
                                          (role) => _roleLabel(strings, role),
                                        )
                                        .join(' · '),
                              ),
                              trailing: canOpenPersonDetails
                                  ? const Icon(Icons.chevron_right)
                                  : null,
                              onTap: canOpenPersonDetails
                                  ? () => _openPersonProfile(leader.personId)
                                  : null,
                            ),
                            const Divider(),
                          ],
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
        return Scaffold(
          floatingActionButtonLocation: _assistantUsesFab(context)
              ? _aboveAssistantFabLocation
              : null,
          body: state.phase == AsyncDataPhase.empty
              ? FutureBuilder<TeamRoles>(
                  future: _teamRoles,
                  // Keep the search and filter chips whenever a leader exists
                  // or a filter is active, so a filter that matches nobody
                  // can always be changed back.
                  builder: (context, rolesSnapshot) =>
                      _list.filterKey != null ||
                          _list.query.isNotEmpty ||
                          (rolesSnapshot.data?.roles.any(
                                (role) => role.role != 'player',
                              ) ??
                              false)
                      ? rosterList
                      : Column(
                          children: [
                            Expanded(
                              child: _StateCard(
                                icon: Icons.groups_outlined,
                                title: AppStrings.of(
                                  context,
                                ).feature('Ingen i truppen ännu'),
                                message: AppStrings.of(context).feature(
                                  'Rosterposter visas här när de har skapats.',
                                ),
                                // A brand-new team's empty roster used to have no action
                                // here at all, unlike every other empty/blocked state on
                                // this screen. Found via a physical walkthrough of a
                                // freshly created team. Points at Inställningar, not
                                // straight at the code dialog: "Använd kod" was removed
                                // from the Trupp tab entirely and consolidated into the
                                // profile settings page (see profile_settings_surface.dart).
                                action: OutlinedButton.icon(
                                  onPressed: () => GoRouter.of(
                                    context,
                                  ).go(ProductRouteContract.settings),
                                  icon: const Icon(Icons.settings_outlined),
                                  label: Text(
                                    AppStrings.of(
                                      context,
                                    ).feature('Inställningar'),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                )
              : rosterList,
          floatingActionButton: canManage
              ? FloatingActionButton(
                  // A single FAB here, not a stack: this screen used to show
                  // "Medlemsansökningar" and "Hantera" as two separate
                  // stacked FloatingActionButtons, which overlapped and
                  // clipped the persistent Min assistent FAB (fixed
                  // `bottom: 88` in product_shell.dart) and, on shorter
                  // rosters, the roster list's own row actions underneath.
                  // "Medlemsansökningar" is now a menu entry below instead
                  // of a second floating button. Icon-only (no label) keeps
                  // it visually small next to the persistent assistant FAB.
                  heroTag: 'manage-roster',
                  tooltip: AppStrings.of(context).feature('Hantera'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    // Every sheet in this flow uses the root navigator: the
                    // persistent Min assistent FAB lives in a Stack sibling
                    // of the page Router in product_shell.dart, so a sheet
                    // pushed on the page's own (nested) navigator paints
                    // *below* that FAB instead of above it. Pushing on the
                    // root navigator puts the sheet in the same Overlay as
                    // the FAB, above it, like _openPersonDetails already
                    // does for the person-details sheet.
                    useRootNavigator: true,
                    builder: (sheetContext) => SafeArea(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.shield_outlined),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Ledare och roller'),
                              ),
                              subtitle: Text(
                                AppStrings.of(context).feature(
                                  'Lägg till ledare, även dig själv eller klubbens befintliga ledare.',
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _openTeamRoles();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.how_to_reg_outlined),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Medlemsansökningar'),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                showModalBottomSheet<void>(
                                  context: context,
                                  useRootNavigator: true,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => _MembershipReviewSheet(
                                    contextValue: widget.contextValue,
                                    membership: widget.membership,
                                    onApproved: _data.refresh,
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              key: const ValueKey('open-intake'),
                              leading: const Icon(Icons.assignment_outlined),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Kontaktuppdatering'),
                              ),
                              subtitle: Text(
                                AppStrings.of(context).feature(
                                  'Tillfällig sida med QR-kod där personer fyller i sina uppgifter.',
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => _IntakeSurface(
                                      contextValue: widget.contextValue,
                                      roster: widget.roster,
                                      onPeopleAdded: () {
                                        unawaited(_data.refresh());
                                        _refreshTeamRoles();
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.mark_email_unread_outlined,
                              ),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Inbjudningar och lagkoder'),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                showModalBottomSheet<void>(
                                  context: context,
                                  useRootNavigator: true,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => _InvitationAdminSheet(
                                    contextValue: widget.contextValue,
                                    roster: widget.roster,
                                    people: _data.state.data ?? const [],
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.compare_arrows),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Representation i andra lag'),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                showModalBottomSheet<void>(
                                  context: context,
                                  useRootNavigator: true,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => _PlayEligibilitySheet(
                                    contextValue: widget.contextValue,
                                    roster: widget.roster,
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.swap_horiz),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Flytta spelare'),
                              ),
                              subtitle: Text(
                                AppStrings.of(context).feature(
                                  'Flytta inom klubben med bevarad historik.',
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                showModalBottomSheet<void>(
                                  context: context,
                                  useRootNavigator: true,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => _IntraClubMoveSheet(
                                    contextValue: widget.contextValue,
                                    roster: widget.roster,
                                  ),
                                ).then((_) => _data.refresh());
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.archive_outlined),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Arkivering och personuppgifter'),
                              ),
                              subtitle: Text(
                                AppStrings.of(context).feature(
                                  'Avsluta en lagtillhörighet med namngiven historik eller begär skyddad anonymisering.',
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                showModalBottomSheet<void>(
                                  context: context,
                                  useRootNavigator: true,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => _RosterLifecycleSheet(
                                    contextValue: widget.contextValue,
                                    roster: widget.roster,
                                  ),
                                ).then((_) => _data.refresh());
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.shield_outlined),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Rosteråtgärder'),
                              ),
                              subtitle: Text(
                                AppStrings.of(context).feature(
                                  'Skapa, invite, guardian och transfer körs som scopeade serverkommandon.',
                                ),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(Icons.group_add_outlined),
                              title: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Lägg till person'),
                              ),
                              subtitle: Text(
                                AppStrings.of(context).feature(
                                  'Skapa en klubbägd rosterprofil i det här laget.',
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _openRosterPersonForm();
                              },
                            ),
                            if (canManageClub) ...[
                              ListTile(
                                key: const ValueKey('manage-club-badge'),
                                leading: const Icon(Icons.shield_outlined),
                                title: Text(
                                  AppStrings.of(context).feature('Klubbmärke'),
                                ),
                                subtitle: Text(
                                  AppStrings.of(
                                    context,
                                  ).feature('Visas på klubbens medlemskort.'),
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  showDialog<void>(
                                    context: context,
                                    useRootNavigator: true,
                                    builder: (_) => _ClubBadgeDialog(
                                      profile: widget.profileServices,
                                      clubId: widget.contextValue.clubId,
                                      clubName: widget.contextValue.clubName,
                                    ),
                                  );
                                },
                              ),
                              ListTile(
                                key: const ValueKey('club-colors'),
                                leading: const Icon(Icons.palette_outlined),
                                title: Text(
                                  AppStrings.of(
                                    context,
                                  ).feature('Klubbens färger'),
                                ),
                                subtitle: Text(
                                  AppStrings.of(context).feature(
                                    'Färger på klubbens publika sidor.',
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  showDialog<bool>(
                                    context: context,
                                    useRootNavigator: true,
                                    builder: (_) => _ClubColorsDialog(
                                      profile: widget.profileServices,
                                      clubId: widget.contextValue.clubId,
                                      clubName: widget.contextValue.clubName,
                                    ),
                                  );
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.group_add_outlined),
                                title: Text(
                                  AppStrings.of(
                                    context,
                                  ).feature('Skapa ytterligare lag'),
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _createTeam();
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.verified_outlined),
                                title: Text(
                                  AppStrings.of(
                                    context,
                                  ).feature('Klubbverifiering'),
                                ),
                                subtitle: Text(
                                  AppStrings.of(context).feature(
                                    'Se officiell status eller skicka underlag till TeamZone.',
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  showModalBottomSheet<void>(
                                    context: context,
                                    useRootNavigator: true,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    builder: (_) => _ClubVerificationSheet(
                                      clubId: widget.contextValue.clubId,
                                      membership: widget.membership,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: const Icon(Icons.person_add_alt_1),
                )
              : null,
        );
      },
    );
  }

  /// Leaders and functionaries for the squad list, one entry per person,
  /// filtered by the same search as the players. They are always active, so
  /// the "Tidigare" filter hides them.
  List<(TeamRole, List<String>)> _leaderEntries(TeamRoles? data) {
    if (data == null || _list.filterKey == 'other') return const [];
    final query = _list.query.trim().toLowerCase();
    final byPerson = <String, (TeamRole, List<String>)>{};
    for (final role in data.roles.where((role) => role.role != 'player')) {
      if (query.isNotEmpty && !role.name.toLowerCase().contains(query)) {
        continue;
      }
      final entry = byPerson.putIfAbsent(role.personId, () => (role, []));
      entry.$2.add(role.role);
    }
    return byPerson.values.toList();
  }

  Widget _rosterGroupHeader(String label, int count) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(
        '${label.toUpperCase()} ($count)',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
    ),
  );

  void _openRosterPersonForm() {
    _openRosterPersonEditor(
      context,
      contextValue: widget.contextValue,
      roster: widget.roster,
      onSaved: () async {
        // A new person can be a leader straight away.
        _refreshTeamRoles();
        await _data.refresh();
      },
    );
  }

  void _setRosterStatusFilter(String? status) {
    _list.setFilter(key: null, predicate: null);
    if (status == 'active') {
      _list.setFilter(
        key: 'active',
        predicate: (person) => person.assignmentState == 'active',
      );
    } else if (status == 'other') {
      _list.setFilter(
        key: 'other',
        predicate: (person) => person.assignmentState != 'active',
      );
    }
  }

  void _openPersonDetails(RosterPersonSummary person) =>
      _openPersonProfile(person.id);

  /// Players and leaders share one profile page. Roles, titles and
  /// permissions can change there, so the squad reloads on return.
  void _openPersonProfile(String personId) {
    GoRouter.of(context).push(ProductRouteContract.teamMember(personId)).then((
      _,
    ) {
      if (!mounted) return;
      _refreshTeamRoles();
      unawaited(_data.refresh());
    });
  }
}

class _NoTeamMembershipSurface extends StatelessWidget {
  const _NoTeamMembershipSurface({required this.onManageConnections});

  final VoidCallback onManageConnections;

  @override
  Widget build(BuildContext context) => _StateCard(
    icon: Icons.groups_outlined,
    title: AppStrings.of(context).feature('Du är inte kopplad till något lag'),
    message: AppStrings.of(context).feature(
      'När du blir tillagd i ett lag visas lagets översikt, trupp och kalender här.',
    ),
    action: FilledButton.icon(
      onPressed: onManageConnections,
      icon: const Icon(Icons.settings_outlined),
      label: Text(AppStrings.of(context).feature('Inställningar')),
    ),
  );
}

class _RosterFilterChip extends StatelessWidget {
  const _RosterFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
  );
}

class _RosterLifecycleSheet extends StatefulWidget {
  const _RosterLifecycleSheet({
    required this.contextValue,
    required this.roster,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  @override
  State<_RosterLifecycleSheet> createState() => _RosterLifecycleSheetState();
}

class _RosterLifecycleSheetState extends State<_RosterLifecycleSheet> {
  late Future<RosterLifecycleOptions> _load = _reload();
  bool _pending = false;
  bool _showArchived = false;
  Future<RosterLifecycleOptions> _reload() => widget.roster
      .getRosterLifecycle(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));
  void _refresh() => setState(() {
    _load = _reload();
  });

  Future<String?> _reason(String title, String message) async {
    var reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).feature(title)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.of(context).feature(message)),
            const SizedBox(height: 12),
            TextField(
              maxLength: 240,
              onChanged: (value) => reason = value,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).feature('Anledning'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.of(context).feature('Bekräfta')),
          ),
        ],
      ),
    );
    final value = reason.trim();
    return confirmed == true && value.length >= 2 ? value : null;
  }

  Future<void> _showActionError(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).feature(title)),
        content: Text(AppStrings.of(context).feature(message)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.of(context).feature('Stäng')),
          ),
        ],
      ),
    );
  }

  Future<void> _archive(RosterLifecyclePerson person) async {
    final reason = await _reason(
      'Avsluta i laget',
      'Personen flyttas till Arkiverade. Namn, matcher, närvaro och annan historik bevaras.',
    );
    if (reason == null || !mounted) return;
    setState(() => _pending = true);
    try {
      await widget.roster.archiveTeamAssignment(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
        personId: person.personId,
        assignmentId: person.assignmentId,
        expectedRevision: person.assignmentRevision,
        reason: reason,
        idempotencyKey: _newUuid(),
      );
      _refresh();
    } catch (error, stackTrace) {
      debugPrint('TEAM-08 archive failed: $error\n$stackTrace');
      await _showActionError(
        'Arkivera från laget',
        'Åtgärden kunde inte sparas. Ladda om och försök igen.',
      );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _restore(RosterLifecyclePerson person) async {
    final reason = await _reason(
      'Återaktivera i laget',
      'En ny aktiv lagtillhörighetsperiod skapas. Den tidigare perioden och all historik lämnas oförändrade.',
    );
    if (reason == null || !mounted) return;
    setState(() => _pending = true);
    try {
      await widget.roster.restoreArchivedTeamAssignment(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
        personId: person.personId,
        assignmentId: person.assignmentId,
        expectedRevision: person.assignmentRevision,
        reason: reason,
        idempotencyKey: _newUuid(),
      );
      if (!mounted) return;
      setState(() {
        _showArchived = false;
        _load = _reload();
      });
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppStrings.of(context).feature('Återaktivera i laget')),
          content: Text(
            AppStrings.of(context).feature(
              'Återaktiveringen kunde inte sparas. Personen kan redan vara aktiv i ett annat lag.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).feature('Stäng')),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _requestErasure(RosterLifecyclePerson person) async {
    final reason = await _reason(
      'Begär anonymisering',
      'En annan klubbansvarig måste godkänna. Namn och personliga rekord kan inte längre kopplas till personen. Lagets neutrala verksamhetshistorik bevaras.',
    );
    if (reason == null || !mounted) return;
    setState(() => _pending = true);
    try {
      await widget.roster.requestClubPersonErasure(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
        personId: person.personId,
        reason: reason,
        idempotencyKey: _newUuid(),
      );
      _refresh();
    } catch (error, stackTrace) {
      debugPrint('TEAM-08 erasure request failed: $error\n$stackTrace');
      try {
        final reconciled = await _reload();
        final wasCommitted = reconciled.requests.any(
          (request) =>
              request.personId == person.personId &&
              request.state == 'requested',
        );
        if (wasCommitted && mounted) {
          setState(() {
            _load = Future.value(reconciled);
          });
          return;
        }
      } catch (reconcileError, reconcileStackTrace) {
        debugPrint(
          'TEAM-08 erasure request reconciliation failed: '
          '$reconcileError\n$reconcileStackTrace',
        );
      }
      await _showActionError(
        'Begär anonymisering',
        'Anonymiseringsbegäran kunde inte skapas. Kontrollera om det redan finns en väntande begäran för personen.',
      );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _approve(ClubErasureRequest request) async {
    final reason = await _reason(
      'Godkänn anonymisering',
      'Du måste vara en annan klubbansvarig än den som startade begäran. Namnet och personens egna rekord anonymiseras permanent. Lagets historiska fakta bevaras.',
    );
    if (reason == null || !mounted) return;
    setState(() => _pending = true);
    try {
      await widget.roster.approveClubPersonErasure(
        requestId: request.id,
        expectedRevision: request.revision,
        reason: reason,
        idempotencyKey: _newUuid(),
      );
      _refresh();
    } catch (error, stackTrace) {
      debugPrint('TEAM-08 erasure approval failed: $error\n$stackTrace');
      try {
        final reconciled = await _reload();
        final wasCommitted = reconciled.requests.any(
          (item) => item.id == request.id && item.state == 'completed',
        );
        if (wasCommitted && mounted) {
          setState(() {
            _load = Future.value(reconciled);
          });
          return;
        }
      } catch (reconcileError, reconcileStackTrace) {
        debugPrint(
          'TEAM-08 erasure approval reconciliation failed: '
          '$reconcileError\n$reconcileStackTrace',
        );
      }
      await _showActionError(
        'Godkänn anonymisering',
        'Godkännandet nekades. Kontrollera behörighet och att initiatorn är en annan användare.',
      );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .88,
    child: FutureBuilder<RosterLifecycleOptions>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(
            label: AppStrings.of(context).feature('Laddar livscykel'),
          );
        }
        if (!snapshot.hasData) {
          return _StateCard(
            icon: Icons.sync_problem,
            title: AppStrings.of(
              context,
            ).feature('Livscykeln kunde inte laddas'),
            message: AppStrings.of(context).feature('Försök igen.'),
          );
        }
        final data = snapshot.data!;
        final visiblePeople = data.people
            .where(
              (person) => _showArchived
                  ? person.assignmentState != 'active'
                  : person.assignmentState == 'active',
            )
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              AppStrings.of(context).feature('Arkivering och personuppgifter'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.of(context).feature(
                'Avsluta i laget bevarar namn och historik. Anonymisering tar bort identiteten och kräver två separata ansvariga. Global kontoradering granskas alltid av TeamZone.',
              ),
            ),
            const Divider(),
            Text(
              AppStrings.of(context).feature('Personer'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(AppStrings.of(context).feature('Aktiva')),
                  icon: const Icon(Icons.groups_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(AppStrings.of(context).feature('Arkiverade')),
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
              selected: {_showArchived},
              onSelectionChanged: _pending
                  ? null
                  : (selection) =>
                        setState(() => _showArchived = selection.first),
            ),
            const SizedBox(height: 8),
            if (visiblePeople.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  AppStrings.of(context).feature(
                    _showArchived
                        ? 'Inga arkiverade personer.'
                        : 'Inga aktiva personer.',
                  ),
                ),
              ),
            for (final person in visiblePeople)
              ListTile(
                title: Text(person.personName),
                subtitle: Text(
                  AppStrings.of(context).domainValue(person.assignmentState),
                ),
                trailing: person.canArchive || person.canReactivate
                    ? PopupMenuButton<String>(
                        enabled: !_pending,
                        onSelected: (value) {
                          if (value == 'archive') _archive(person);
                          if (value == 'restore') _restore(person);
                          if (value == 'erase') _requestErasure(person);
                        },
                        itemBuilder: (_) => [
                          if (person.canArchive)
                            PopupMenuItem(
                              value: 'archive',
                              child: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Avsluta i laget'),
                              ),
                            ),
                          if (person.canReactivate)
                            PopupMenuItem(
                              value: 'restore',
                              child: Text(
                                AppStrings.of(
                                  context,
                                ).feature('Återaktivera i laget'),
                              ),
                            ),
                          PopupMenuItem(
                            value: 'erase',
                            child: Text(
                              AppStrings.of(
                                context,
                              ).feature('Begär anonymisering'),
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            const Divider(),
            Text(
              AppStrings.of(context).feature('Anonymiseringsbegäranden'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (data.requests.isEmpty)
              Text(
                AppStrings.of(
                  context,
                ).feature('Inga pågående anonymiseringsbegäranden.'),
              ),
            for (final request in data.requests)
              ListTile(
                title: Text(request.personName),
                subtitle: Text(
                  AppStrings.of(context).domainValue(request.state),
                ),
                // The backend is authoritative for club-level approval. A
                // club functionary may currently be viewing the team through
                // a leader context, so the active role package must not hide
                // an otherwise valid decision action.
                trailing: request.canApprove
                    ? TextButton(
                        onPressed: _pending ? null : () => _approve(request),
                        child: Text(AppStrings.of(context).feature('Godkänn')),
                      )
                    : null,
              ),
          ],
        );
      },
    ),
  );
}

class _IntraClubMoveSheet extends StatefulWidget {
  const _IntraClubMoveSheet({
    required this.contextValue,
    required this.roster,
    this.initialPersonId,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final String? initialPersonId;
  @override
  State<_IntraClubMoveSheet> createState() => _IntraClubMoveSheetState();
}

class _IntraClubMoveSheetState extends State<_IntraClubMoveSheet> {
  late Future<IntraClubMoveOptions> _load = _reload();
  final Set<String> _selectedPersonIds = {};
  static const _reasons = <String>[
    'Byte av ordinarie lag',
    'Åldersanpassning',
    'Omorganisation inom klubben',
    'Flytt beslutad av lagansvarig',
  ];
  bool _pending = false;
  bool _selectionInitialized = false;
  String? _targetTeamId;
  String _reason = _reasons.first;

  Future<IntraClubMoveOptions> _reload() => widget.roster
      .getIntraClubMoveOptions(
        clubId: widget.contextValue.clubId,
        sourceTeamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));

  Future<void> _move(IntraClubMoveOptions options) async {
    if (_pending ||
        !options.canMove ||
        _selectedPersonIds.isEmpty ||
        _targetTeamId == null) {
      return;
    }
    final effectiveAt = DateTime.now();
    setState(() => _pending = true);
    var movedCount = 0;
    var failedCount = 0;
    final selectedPeople = options.people
        .where((person) => _selectedPersonIds.contains(person.personId))
        .toList();
    try {
      for (final person in selectedPeople) {
        try {
          await widget.roster.movePlayerWithinClub(
            clubId: widget.contextValue.clubId,
            sourceTeamId: person.sourceTeamId,
            targetTeamId: _targetTeamId!,
            personId: person.personId,
            assignmentId: person.assignmentId,
            effectiveAt: effectiveAt,
            expectedRevision: person.assignmentRevision,
            reason: _reason,
            idempotencyKey: _newUuid(),
          );
          movedCount += 1;
        } catch (_) {
          failedCount += 1;
        }
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Flytta spelare')),
        content: Text(
          AppStrings.of(context).playerMoveResult(movedCount, failedCount),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.of(context).feature('Stäng')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _selectedPersonIds.clear();
    _selectionInitialized = false;
    if (movedCount > 0) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _load = _reload();
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .85,
    child: FutureBuilder<IntraClubMoveOptions>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(
            label: AppStrings.of(context).feature('Laddar flyttunderlag'),
          );
        }
        if (!snapshot.hasData) {
          return _StateCard(
            icon: Icons.sync_problem,
            title: AppStrings.of(
              context,
            ).feature('Flyttunderlaget kunde inte laddas'),
            message: AppStrings.of(context).feature('Försök igen.'),
          );
        }
        final options = snapshot.data!;
        if (!_selectionInitialized) {
          _selectionInitialized = true;
          _targetTeamId = options.teams.firstOrNull?.id;
          final initialPersonId = widget.initialPersonId;
          if (initialPersonId != null &&
              options.people.any(
                (person) => person.personId == initialPersonId,
              )) {
            _selectedPersonIds.add(initialPersonId);
          }
        }
        return Column(
          children: [
            ListTile(
              title: Text(AppStrings.of(context).feature('Flytta spelare')),
              subtitle: Text(
                AppStrings.of(context).feature(
                  'Välj en eller flera spelare. Tidigare lagtillhörighet och historik bevaras.',
                ),
              ),
              trailing: IconButton(
                tooltip: AppStrings.of(context).feature('Stäng'),
                onPressed: _pending ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: options.canMove
                  ? ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: options.people
                          .map(
                            (person) => CheckboxListTile(
                              value: _selectedPersonIds.contains(
                                person.personId,
                              ),
                              title: Text(person.personName),
                              subtitle: Text(person.sourceTeamName),
                              onChanged: _pending
                                  ? null
                                  : (selected) => setState(() {
                                      if (selected == true) {
                                        _selectedPersonIds.add(person.personId);
                                      } else {
                                        _selectedPersonIds.remove(
                                          person.personId,
                                        );
                                      }
                                    }),
                            ),
                          )
                          .toList(),
                    )
                  : _StateCard(
                      icon: Icons.swap_horiz,
                      title: AppStrings.of(
                        context,
                      ).feature('Ingen flytt är möjlig'),
                      message: AppStrings.of(context).feature(
                        'Det behövs en aktiv spelare och minst ett annat aktivt lag i klubben.',
                      ),
                    ),
            ),
            if (options.canMove)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(),
                      DropdownButtonFormField<String>(
                        initialValue: _targetTeamId,
                        decoration: InputDecoration(
                          labelText: AppStrings.of(
                            context,
                          ).feature('Flytta till lag'),
                        ),
                        items: options.teams
                            .map(
                              (team) => DropdownMenuItem(
                                value: team.id,
                                child: Text(team.name),
                              ),
                            )
                            .toList(),
                        onChanged: _pending
                            ? null
                            : (value) => setState(() => _targetTeamId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _reason,
                        decoration: InputDecoration(
                          labelText: AppStrings.of(
                            context,
                          ).feature('Anledning'),
                        ),
                        items: _reasons
                            .map(
                              (reason) => DropdownMenuItem(
                                value: reason,
                                child: Text(
                                  AppStrings.of(context).feature(reason),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _pending || _selectedPersonIds.isEmpty
                            ? null
                            : (value) => setState(() {
                                if (value != null) _reason = value;
                              }),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              _pending ||
                                  _selectedPersonIds.isEmpty ||
                                  _targetTeamId == null
                              ? null
                              : () => _move(options),
                          icon: _pending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.swap_horiz),
                          label: Text(
                            _selectedPersonIds.length > 1
                                ? AppStrings.of(
                                    context,
                                  ).movePlayersAction(_selectedPersonIds.length)
                                : AppStrings.of(
                                    context,
                                  ).feature('Flytta spelare'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _PlayEligibilitySheet extends StatefulWidget {
  const _PlayEligibilitySheet({
    required this.contextValue,
    required this.roster,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  @override
  State<_PlayEligibilitySheet> createState() => _PlayEligibilitySheetState();
}

class _PlayEligibilitySheetState extends State<_PlayEligibilitySheet> {
  late Future<List<PlayEligibilitySummary>> _load = _reload();
  bool _pending = false;

  Future<List<PlayEligibilitySummary>> _reload() => widget.roster
      .listPlayEligibilities(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));

  void _refresh() => setState(() {
    _load = _reload();
  });

  Future<void> _create() async {
    List<RosterPersonSummary> people;
    setState(() => _pending = true);
    try {
      people = await widget.roster
          .listPlayEligibilityCandidates(
            clubId: widget.contextValue.clubId,
            teamId: widget.contextValue.teamId!,
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      if (mounted) {
        await _showCandidateMessage(
          'Spelare från andra lag kunde inte laddas. Försök igen.',
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _pending = false);
    }
    if (!mounted) return;
    if (people.isEmpty) {
      await _showCandidateMessage(
        'Det finns inga aktiva spelare i klubbens andra lag.',
      );
      return;
    }
    var personId = people.first.id;
    var kind = 'development';
    var validity = 'season';
    var boundary = DateTime(DateTime.now().year + 1, 6, 30);
    var sourceNote = 'Beslut av lagansvarig';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).feature('Ny representation')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: personId,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Person'),
                  ),
                  items: people
                      .map(
                        (person) => DropdownMenuItem(
                          value: person.id,
                          child: Text(
                            '${person.displayName} · ${person.teamName ?? ''}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => personId = value ?? personId),
                ),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Typ'),
                  ),
                  items: const ['development', 'dispensation', 'loan', 'guest']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            AppStrings.of(context).domainValue(value),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => kind = value ?? kind),
                ),
                DropdownButtonFormField<String>(
                  initialValue: validity,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Giltighet'),
                  ),
                  items: const ['season', 'fixed', 'indefinite']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            AppStrings.of(context).domainValue(value),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() {
                    validity = value ?? validity;
                    boundary = validity == 'indefinite'
                        ? DateTime.now().add(const Duration(days: 90))
                        : validity == 'fixed'
                        ? DateTime.now().add(const Duration(days: 30))
                        : DateTime(DateTime.now().year + 1, 6, 30);
                  }),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    AppStrings.of(context).feature(
                      validity == 'indefinite'
                          ? 'Granskas senast'
                          : 'Gäller till',
                    ),
                  ),
                  subtitle: Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(boundary),
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                      initialDate: boundary,
                    );
                    if (value != null) setDialogState(() => boundary = value);
                  },
                ),
                TextFormField(
                  initialValue: sourceNote,
                  onChanged: (value) => sourceNote = value,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(
                      context,
                    ).feature('Beslutsunderlag'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppStrings.of(context).feature('Skapa')),
            ),
          ],
        ),
      ),
    );
    final note = sourceNote.trim();
    if (confirmed != true || note.length < 2) return;
    setState(() => _pending = true);
    try {
      final endOfDay = DateTime(
        boundary.year,
        boundary.month,
        boundary.day,
        23,
        59,
        59,
      );
      await widget.roster.createPlayEligibility(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
        personId: personId,
        kind: kind,
        validityKind: validity,
        startsAt: DateTime.now().toUtc(),
        endsAt: validity == 'indefinite' ? null : endOfDay,
        seasonEndsOn: validity == 'season' ? boundary : null,
        reviewDueAt: validity == 'indefinite' ? endOfDay : null,
        sourceNote: note,
        idempotencyKey: _newUuid(),
      );
      _refresh();
    } catch (_) {
      if (mounted) {
        await _showCandidateMessage(
          'Representationen kunde inte sparas. Kontrollera lag, period och överlapp.',
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _showCandidateMessage(String message) => showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppStrings.of(context).feature('Ny representation')),
      content: Text(AppStrings.of(context).feature(message)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(AppStrings.of(context).feature('Stäng')),
        ),
      ],
    ),
  );

  Future<void> _end(PlayEligibilitySummary item) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await widget.roster.endPlayEligibility(
        eligibilityId: item.id,
        expectedRevision: item.revision,
        idempotencyKey: _newUuid(),
      );
      _refresh();
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _decide(PlayEligibilitySummary item, bool approve) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await widget.roster.decidePlayEligibility(
        eligibilityId: item.id,
        approve: approve,
        expectedRevision: item.revision,
        idempotencyKey: _newUuid(),
      );
      _refresh();
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .88,
    child: Column(
      children: [
        ListTile(
          title: Text(
            AppStrings.of(context).feature('Representation i andra lag'),
          ),
          subtitle: Text(
            AppStrings.of(
              context,
            ).feature('Ordinarie lag och historik ändras inte.'),
          ),
          trailing: FilledButton.icon(
            onPressed: _pending ? null : _create,
            icon: const Icon(Icons.add),
            label: Text(AppStrings.of(context).feature('Ny')),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<PlayEligibilitySummary>>(
            future: _load,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return AppLoadingIndicator(
                  label: AppStrings.of(
                    context,
                  ).feature('Laddar representationer'),
                );
              }
              if (!snapshot.hasData) {
                return _StateCard(
                  icon: Icons.sync_problem,
                  title: AppStrings.of(
                    context,
                  ).feature('Representationerna kunde inte laddas'),
                  message: AppStrings.of(context).feature('Försök igen.'),
                );
              }
              if (snapshot.data!.isEmpty) {
                return _StateCard(
                  icon: Icons.compare_arrows,
                  title: AppStrings.of(
                    context,
                  ).feature('Inga representationer'),
                  message: AppStrings.of(context).feature(
                    'Spelare kan få tidsbegränsad rätt att representera ett annat lag.',
                  ),
                );
              }
              return ListView(
                children: [
                  for (final item in snapshot.data!)
                    ListTile(
                      title: Text(item.personName),
                      subtitle: Text(
                        [
                          AppStrings.of(context).domainValue(item.kind),
                          AppStrings.of(context).domainValue(item.validityKind),
                          AppStrings.of(context).domainValue(item.state),
                          if (item.homeTeamId == widget.contextValue.teamId &&
                              item.targetTeamId != widget.contextValue.teamId)
                            '${AppStrings.of(context).feature('begärd av')} '
                                '${item.targetTeamName}'
                          else if (item.homeTeamName != null &&
                              item.homeTeamId != widget.contextValue.teamId)
                            '${AppStrings.of(context).feature('från')} '
                                '${item.homeTeamName}',
                        ].join(' · '),
                      ),
                      trailing: item.canDecide
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: _pending
                                      ? null
                                      : () => _decide(item, false),
                                  child: Text(
                                    AppStrings.of(context).feature('Avslå'),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: _pending
                                      ? null
                                      : () => _decide(item, true),
                                  child: Text(
                                    AppStrings.of(context).feature('Godkänn'),
                                  ),
                                ),
                              ],
                            )
                          : item.canEnd
                          ? TextButton(
                              onPressed: _pending ? null : () => _end(item),
                              child: Text(
                                AppStrings.of(context).feature('Avsluta'),
                              ),
                            )
                          : null,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _InvitationAdminSheet extends StatefulWidget {
  const _InvitationAdminSheet({
    required this.contextValue,
    required this.roster,
    required this.people,
    this.initialPersonId,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final List<RosterPersonSummary> people;
  // Set when opened directly from a player's profile: jumps straight to the
  // targeted-invite form with this person preselected instead of the menu.
  final String? initialPersonId;
  @override
  State<_InvitationAdminSheet> createState() => _InvitationAdminSheetState();
}

enum _InviteStep { menu, list, form, confirm }

enum _InviteKind { targeted, guardian, teamCode }

class _InvitationAdminSheetState extends State<_InvitationAdminSheet> {
  late Future<List<InvitationAdminItem>> _load = _reload();
  bool _pending = false;

  var _step = _InviteStep.menu;
  _InviteKind? _kind;
  String? _createdToken;

  // Bjud in ny spelare (targeted invitation).
  String? _targetedPersonId;
  String _targetedEmail = '';
  String? _targetedEmailError;

  // Koppla vårdnadshavare (guardian invitation).
  String? _guardianPersonId;
  String? _guardianChildId;

  // Skapa lagkod (team code).
  String _teamCodeRole = 'player';

  // Former/archived roster people (assignmentState != 'active') can't
  // sensibly claim an identity, be called up as a guardian, or represent
  // another team — every person picker in this sheet stays scoped to the
  // active roster only.
  List<RosterPersonSummary> get _activePeople => widget.people
      .where((person) => person.assignmentState == 'active')
      .toList(growable: false);

  // A targeted invite claims a roster identity — pointless (and refused by
  // the server as a conflict once redeemed) for someone who already has an
  // account linked to it. Guardian invites don't use this: an
  // already-claimed guardian legitimately gets invited again for a second
  // child, so _guardianCandidates stays on _activePeople.
  List<RosterPersonSummary> get _invitablePeople => _activePeople
      .where((person) => !person.accountLinked)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final initialPersonId = widget.initialPersonId;
    if (initialPersonId != null &&
        _invitablePeople.any((person) => person.id == initialPersonId)) {
      _kind = _InviteKind.targeted;
      _step = _InviteStep.form;
      _targetedPersonId = initialPersonId;
    }
  }

  List<RosterPersonSummary> get _children => _activePeople
      .where((person) => person.safeguardingRequired)
      .toList(growable: false);

  List<RosterPersonSummary> get _guardianCandidates => _activePeople
      .where((person) => person.id != _guardianChildId)
      .toList(growable: false);

  Future<List<InvitationAdminItem>> _reload() => widget.roster
      .listInvitationAdmin(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));

  void _refresh() => setState(() {
    _load = _reload();
  });

  void _openForm(_InviteKind kind) {
    setState(() {
      _kind = kind;
      _step = _InviteStep.form;
      switch (kind) {
        case _InviteKind.targeted:
          _targetedPersonId = _invitablePeople.isEmpty
              ? null
              : _invitablePeople.first.id;
          _targetedEmail = '';
          _targetedEmailError = null;
        case _InviteKind.guardian:
          final children = _children;
          _guardianChildId = children.isEmpty ? null : children.first.id;
          final guardians = _guardianCandidates;
          _guardianPersonId = guardians.isEmpty ? null : guardians.first.id;
        case _InviteKind.teamCode:
          _teamCodeRole = 'player';
      }
    });
  }

  void _backToMenu() => setState(() {
    _step = _InviteStep.menu;
    _kind = null;
    _createdToken = null;
  });

  void _backOneStep() => setState(() {
    if (_createdToken != null) {
      _backToMenu();
      return;
    }
    _step = switch (_step) {
      _InviteStep.confirm => _InviteStep.form,
      _InviteStep.form => _InviteStep.menu,
      _InviteStep.list => _InviteStep.menu,
      _InviteStep.menu => _InviteStep.menu,
    };
    if (_step == _InviteStep.menu) _kind = null;
  });

  bool get _canAdvanceFromForm => switch (_kind) {
    _InviteKind.targeted => _targetedPersonId != null,
    _InviteKind.guardian =>
      _guardianPersonId != null &&
          _guardianChildId != null &&
          _guardianPersonId != _guardianChildId,
    _InviteKind.teamCode => true,
    null => false,
  };

  void _advanceFromForm() {
    if (_kind == _InviteKind.targeted) {
      final normalized = _targetedEmail.trim();
      final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized);
      if (!valid) {
        setState(
          () => _targetedEmailError = AppStrings.of(
            context,
          ).feature('Ange en giltig e-postadress.'),
        );
        return;
      }
    }
    if (!_canAdvanceFromForm) return;
    setState(() => _step = _InviteStep.confirm);
  }

  Future<void> _confirmCreate() async {
    if (_pending || _kind == null) return;
    setState(() => _pending = true);
    final token = '${_newUuid()}${_newUuid()}';
    try {
      switch (_kind!) {
        case _InviteKind.targeted:
          await widget.roster.issueTargetedInvitation(
            personId: _targetedPersonId!,
            intendedEmail: _targetedEmail.trim(),
            token: token,
            expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
            idempotencyKey: _newUuid(),
          );
        case _InviteKind.guardian:
          await widget.roster.issueGuardianInvitation(
            guardianPersonId: _guardianPersonId!,
            childPersonId: _guardianChildId!,
            token: token,
            expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
            idempotencyKey: _newUuid(),
          );
        case _InviteKind.teamCode:
          await widget.roster.issueTeamCode(
            clubId: widget.contextValue.clubId,
            teamId: widget.contextValue.teamId!,
            requestedRole: _teamCodeRole,
            token: token,
            expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
            maxUses: 100,
            idempotencyKey: _newUuid(),
          );
      }
      if (!mounted) return;
      setState(() => _createdToken = token);
      _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Inbjudan kunde inte skapas.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _copyCreatedToken() async {
    final token = _createdToken;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(context).feature('Inbjudningskoden har kopierats.'),
        ),
      ),
    );
  }

  Future<void> _revoke(InvitationAdminItem item) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await widget.roster.revokeInvitation(
        kind: item.kind,
        invitationId: item.id,
        expectedRevision: item.revision,
        idempotencyKey: _newUuid(),
      );
      _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Inbjudan kunde inte återkallas.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _showTeamCode(InvitationAdminItem item) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      final code = await widget.roster.revealTeamCode(codeId: item.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppStrings.of(dialogContext).feature('Lagkod')),
          content: SelectableText(code),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppStrings.of(
                        dialogContext,
                      ).feature('Lagkoden har kopierats.'),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: Text(AppStrings.of(dialogContext).feature('Kopiera')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(dialogContext).feature('Stäng')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Lagkoden kan inte visas. Återkalla den och skapa en ny kod.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _endRelation(InvitationAdminItem item) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await widget.roster.endGuardianRelation(
        relationId: item.id,
        expectedRevision: item.revision,
        idempotencyKey: _newUuid(),
      );
      _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Guardianrelationen kunde inte avslutas.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Widget _stepHeader(String title) => Row(
    children: [
      if (_step != _InviteStep.menu)
        IconButton(
          onPressed: _pending ? null : _backOneStep,
          icon: const Icon(Icons.arrow_back),
          tooltip: AppStrings.of(context).feature('Tillbaka'),
        ),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    ],
  );

  Widget _buildMenuStep(BuildContext context) => ListView(
    children: [
      ListTile(
        title: Text(
          AppStrings.of(context).feature('Inbjudningar och lagkoder'),
        ),
        subtitle: Text(
          AppStrings.of(context).feature(
            'Välj vad du vill skapa. Nästa steg förklarar vad som händer '
            'innan något skapas.',
          ),
        ),
      ),
      _BigChoiceCard(
        icon: Icons.person_add_alt_outlined,
        title: AppStrings.of(context).feature('Bjud in ny spelare'),
        subtitle: AppStrings.of(context).feature(
          'Skicka en personlig länk till en vald rosterpost via e-post.',
        ),
        onTap: _pending ? null : () => _openForm(_InviteKind.targeted),
      ),
      _BigChoiceCard(
        icon: Icons.family_restroom_outlined,
        title: AppStrings.of(context).feature('Koppla vårdnadshavare'),
        subtitle: AppStrings.of(
          context,
        ).feature('Länka en vuxen till ett barn som redan finns i truppen.'),
        onTap: _pending ? null : () => _openForm(_InviteKind.guardian),
      ),
      _BigChoiceCard(
        icon: Icons.qr_code_outlined,
        title: AppStrings.of(context).feature('Skapa lagkod'),
        subtitle: AppStrings.of(context).feature(
          'En delbar kod som flera kan använda för att ansöka om en roll.',
        ),
        onTap: _pending ? null : () => _openForm(_InviteKind.teamCode),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.mail_outline),
        title: Text(
          AppStrings.of(context).feature('Aktiva inbjudningar och koder'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => _step = _InviteStep.list),
      ),
    ],
  );

  Widget _buildListStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepHeader(
        AppStrings.of(context).feature('Aktiva inbjudningar och koder'),
      ),
      Expanded(
        child: FutureBuilder<List<InvitationAdminItem>>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return AppLoadingIndicator(
                label: AppStrings.of(context).feature('Laddar inbjudningar'),
              );
            }
            if (!snapshot.hasData) {
              return _StateCard(
                icon: Icons.sync_problem,
                title: AppStrings.of(
                  context,
                ).feature('Inbjudningarna kunde inte laddas'),
                message: AppStrings.of(context).feature('Försök igen.'),
              );
            }
            if (snapshot.data!.isEmpty) {
              return _StateCard(
                icon: Icons.mail_outline,
                title: AppStrings.of(context).feature('Inga inbjudningar'),
                message: AppStrings.of(context).feature(
                  'Skapa en riktad inbjudan, guardianinbjudan eller lagkod.',
                ),
              );
            }
            final active = snapshot.data!
                .where((item) => item.isActive)
                .toList(growable: false);
            final inactive = snapshot.data!
                .where((item) => !item.isActive)
                .toList(growable: false);
            Widget invitationTile(InvitationAdminItem item) => ListTile(
              title: Text(item.subjectName),
              subtitle: item.expiresAt == null
                  ? null
                  : Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(item.expiresAt!.toLocal()),
                    ),
              leading: Chip(
                avatar: Icon(
                  item.isActive
                      ? Icons.schedule_outlined
                      : Icons.history_outlined,
                  size: 18,
                ),
                label: Text(
                  AppStrings.of(context).domainValue(item.displayState),
                ),
              ),
              trailing: item.kind == 'team_code' && item.canRevoke
                  ? Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: AppStrings.of(context).feature('Visa kod'),
                          onPressed: _pending
                              ? null
                              : () => _showTeamCode(item),
                          icon: const Icon(Icons.visibility_outlined),
                        ),
                        IconButton(
                          tooltip: AppStrings.of(context).feature('Återkalla'),
                          onPressed: _pending ? null : () => _revoke(item),
                          icon: const Icon(Icons.block_outlined),
                        ),
                      ],
                    )
                  : item.canEndRelation
                  ? TextButton(
                      onPressed: _pending ? null : () => _endRelation(item),
                      child: Text(AppStrings.of(context).feature('Avsluta')),
                    )
                  : item.canRevoke
                  ? TextButton(
                      onPressed: _pending ? null : () => _revoke(item),
                      child: Text(AppStrings.of(context).feature('Återkalla')),
                    )
                  : null,
            );
            return ListView(
              children: [
                if (active.isNotEmpty) ...[
                  _InvitationSectionHeader(
                    label: AppStrings.of(
                      context,
                    ).feature('Aktiva inbjudningar'),
                    count: active.length,
                  ),
                  ...active.map(invitationTile),
                ],
                if (inactive.isNotEmpty) ...[
                  _InvitationSectionHeader(
                    label: AppStrings.of(
                      context,
                    ).feature('Tidigare inbjudningar'),
                    count: inactive.length,
                  ),
                  ...inactive.map(invitationTile),
                ],
              ],
            );
          },
        ),
      ),
    ],
  );

  Widget _buildFormStep(BuildContext context) {
    final strings = AppStrings.of(context);
    late final String title;
    late final String explanation;
    late final Widget fields;
    switch (_kind!) {
      case _InviteKind.targeted:
        title = strings.feature('Bjud in ny spelare');
        if (_invitablePeople.isEmpty) {
          explanation = strings.feature(
            'Alla aktiva personer i truppen har redan ett kopplat konto. '
            'Lägg till en ny person i truppen om du vill bjuda in någon '
            'ytterligare.',
          );
          fields = const SizedBox.shrink();
          break;
        }
        explanation = strings.feature(
          'En riktad inbjudan skickas till en specifik person via e-post och '
          'kopplas till en vald rosterpost. Mottagaren öppnar länken, '
          'verifierar sin e-post och kontot binds automatiskt till rätt '
          'person i laget. Länken fungerar en gång och är giltig i 7 dagar. '
          'TeamZone skickar inte länken automatiskt — du delar den själv.',
        );
        fields = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _targetedPersonId,
              decoration: InputDecoration(
                labelText: strings.feature('Vem gäller inbjudan?'),
              ),
              items: _invitablePeople
                  .map(
                    (person) => DropdownMenuItem(
                      value: person.id,
                      child: Text(person.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _targetedPersonId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onChanged: (value) => setState(() {
                _targetedEmail = value;
                _targetedEmailError = null;
              }),
              decoration: InputDecoration(
                labelText: strings.feature('Mottagarens e-post'),
                errorText: _targetedEmailError,
              ),
            ),
          ],
        );
      case _InviteKind.guardian:
        title = strings.feature('Koppla vårdnadshavare');
        if (_children.isEmpty) {
          explanation = strings.feature(
            'Inga barn i truppen är markerade som i behov av '
            'vårdnadshavarkoppling än. Öppna barnets personuppgifter och slå '
            'på "Behöver vårdnadshavarkoppling" innan du fortsätter här.',
          );
          fields = const SizedBox.shrink();
        } else {
          explanation = strings.feature(
            'En guardian-koppling länkar en vuxen som redan finns i laget '
            'till ett barn som är markerat som i behov av '
            'vårdnadshavarkoppling. Efter att koden använts kan '
            'vårdnadshavaren se information och svara på kallelser för '
            'barnets räkning.',
          );
          fields = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _guardianChildId,
                decoration: InputDecoration(labelText: strings.feature('Barn')),
                items: _children
                    .map(
                      (person) => DropdownMenuItem(
                        value: person.id,
                        child: Text(person.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _guardianChildId = value;
                  if (_guardianPersonId == value) _guardianPersonId = null;
                  final guardians = _guardianCandidates;
                  _guardianPersonId ??= guardians.isEmpty
                      ? null
                      : guardians.first.id;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _guardianPersonId,
                decoration: InputDecoration(
                  labelText: strings.feature('Vårdnadshavare'),
                ),
                items: _guardianCandidates
                    .map(
                      (person) => DropdownMenuItem(
                        value: person.id,
                        child: Text(person.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _guardianPersonId = value),
              ),
            ],
          );
        }
      case _InviteKind.teamCode:
        title = strings.feature('Skapa lagkod');
        explanation = strings.feature(
          'En lagkod är en delbar kod som flera personer kan använda för '
          'att ansöka om en vald roll i laget. En behörig ledare granskar '
          'ändå varje ansökan innan personen läggs till. Koden är giltig i '
          '30 dagar och kan användas upp till 100 gånger.',
        );
        fields = DropdownButtonFormField<String>(
          initialValue: _teamCodeRole,
          decoration: InputDecoration(
            labelText: strings.feature('Ansökningsroll'),
          ),
          items: const ['player', 'leader', 'guardian', 'club_functionary']
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(strings.domainValue(value)),
                ),
              )
              .toList(),
          onChanged: (value) =>
              setState(() => _teamCodeRole = value ?? _teamCodeRole),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(title),
        const SizedBox(height: 8),
        Text(explanation, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        fields,
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _backToMenu,
              child: Text(strings.feature('Avbryt')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _canAdvanceFromForm ? _advanceFromForm : null,
              child: Text(strings.feature('Nästa')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfirmStep(BuildContext context) {
    final strings = AppStrings.of(context);
    if (_createdToken != null) {
      final usageHint = switch (_kind!) {
        _InviteKind.teamCode => strings.feature(
          'Dela koden fritt — den kan användas flera gånger fram till '
          'utgångsdatumet.',
        ),
        _InviteKind.targeted || _InviteKind.guardian => strings.feature(
          'Dela koden med mottagaren. De klistrar in den under '
          'Inställningar → Använd kod.',
        ),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(strings.feature('Koden är skapad')),
          const SizedBox(height: 8),
          SelectableText(_createdToken!),
          const SizedBox(height: 8),
          Text(usageHint, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _copyCreatedToken,
                icon: const Icon(Icons.copy_outlined),
                label: Text(strings.feature('Kopiera')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _backToMenu,
                child: Text(strings.feature('Klar')),
              ),
            ],
          ),
        ],
      );
    }
    final summary = switch (_kind!) {
      _InviteKind.targeted =>
        '${strings.feature('Du bjuder in')} ${_targetedEmail.trim()} '
            '${strings.feature('att gå med som')} '
            '${widget.people.firstWhere((p) => p.id == _targetedPersonId).displayName}.',
      _InviteKind.guardian =>
        '${strings.feature('Du kopplar')} '
            '${widget.people.firstWhere((p) => p.id == _guardianPersonId).displayName} '
            '${strings.feature('som vårdnadshavare till')} '
            '${widget.people.firstWhere((p) => p.id == _guardianChildId).displayName}.',
      _InviteKind.teamCode =>
        '${strings.feature('Du skapar en lagkod för rollen')} '
            '${strings.domainValue(_teamCodeRole)}.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader(strings.feature('Bekräfta')),
        const SizedBox(height: 8),
        Text(summary, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _pending ? null : _backOneStep,
              child: Text(strings.feature('Tillbaka')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _pending ? null : _confirmCreate,
              child: Text(strings.feature('Bekräfta och skapa')),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .88,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: switch (_step) {
        _InviteStep.menu => _buildMenuStep(context),
        _InviteStep.list => _buildListStep(context),
        _InviteStep.form => _buildFormStep(context),
        _InviteStep.confirm => _buildConfirmStep(context),
      },
    ),
  );
}

class _BigChoiceCard extends StatelessWidget {
  const _BigChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

class _InvitationSectionHeader extends StatelessWidget {
  const _InvitationSectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        Text('$count'),
      ],
    ),
  );
}

Future<void> _openRosterPersonEditor(
  BuildContext context, {
  required TeamZoneContext contextValue,
  required RosterServices roster,
  String? personId,
  required Future<void> Function() onSaved,
  ProfileServices profileServices = const UnconfiguredProfileServices(),
  PersonContact? contact,
}) => Navigator.push<void>(
  context,
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: _RosterPersonEditor(
          contextValue: contextValue,
          roster: roster,
          personId: personId,
          onSaved: onSaved,
          profileServices: profileServices,
          contact: contact,
        ),
      ),
    ),
  ),
);

class _RosterPersonEditor extends StatelessWidget {
  const _RosterPersonEditor({
    required this.contextValue,
    required this.roster,
    required this.onSaved,
    this.personId,
    this.profileServices = const UnconfiguredProfileServices(),
    this.contact,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final String? personId;
  final Future<void> Function() onSaved;
  final ProfileServices profileServices;
  final PersonContact? contact;

  @override
  Widget build(BuildContext context) {
    final teamId = contextValue.teamId;
    if (teamId == null) return const SizedBox.shrink();
    if (personId == null) {
      return _RosterPersonFormSheet(
        contextValue: contextValue,
        roster: roster,
        onSaved: onSaved,
      );
    }
    return FutureBuilder<RosterPersonDetails>(
      future: roster
          .getPersonDetails(
            clubId: contextValue.clubId,
            teamId: teamId,
            personId: personId!,
          )
          .timeout(const Duration(seconds: 15)),
      builder: (context, snapshot) {
        final strings = AppStrings.of(context);
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(
            label: strings.feature('Laddar medlemsdetaljer'),
          );
        }
        if (!snapshot.hasData || snapshot.data!.personRevision == null) {
          return _StateCard(
            icon: Icons.lock_outline,
            title: strings.feature('Personen kunde inte redigeras'),
            message: strings.feature(
              'Ladda om truppen och kontrollera din behörighet.',
            ),
          );
        }
        return _RosterPersonFormSheet(
          contextValue: contextValue,
          roster: roster,
          initial: snapshot.data,
          onSaved: onSaved,
          profileServices: profileServices,
          contact: contact,
        );
      },
    );
  }
}

class _RosterPersonFormSheet extends StatefulWidget {
  const _RosterPersonFormSheet({
    required this.contextValue,
    required this.roster,
    required this.onSaved,
    this.initial,
    this.profileServices = const UnconfiguredProfileServices(),
    this.contact,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final RosterPersonDetails? initial;
  final Future<void> Function() onSaved;
  final ProfileServices profileServices;

  /// The person's contact details; the club fills them in for members
  /// without an account.
  final PersonContact? contact;

  @override
  State<_RosterPersonFormSheet> createState() => _RosterPersonFormSheetState();
}

class _RosterPersonFormSheetState extends State<_RosterPersonFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _submission = AppFormController();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.displayName,
  );
  late int? _birthYear =
      widget.initial?.birthYear ??
      int.tryParse((widget.initial?.ageClass ?? '').replaceFirst('F', ''));
  late DateTime? _birthDate = widget.initial?.birthDate;
  late bool _guardianRequired = widget.initial?.safeguardingRequired ?? false;
  late bool _representationAvailable =
      widget.initial?.representationAvailable ?? false;
  late final _email = TextEditingController(text: widget.contact?.contactEmail);
  late final _phone = TextEditingController(text: widget.contact?.phone);
  late final _street = TextEditingController(
    text: widget.contact?.streetAddress,
  );
  late final _postal = TextEditingController(text: widget.contact?.postalCode);
  late final _city = TextEditingController(text: widget.contact?.city);
  late final List<TextEditingController> _contactFields = [
    _email,
    _phone,
    _street,
    _postal,
    _city,
  ];
  bool _contactChanged = false;
  String? _error;

  bool get _editsContact =>
      _isEditing && (widget.contact?.canEditClubContact ?? false);

  void _markContactChanged() {
    _contactChanged = true;
    _submission.markDirty();
  }

  // A new person can get their role, titles and positions right away. The
  // team's roles decide what the viewer may set and which positions exist.
  late final Future<TeamRoles?> _teamRoles = widget.initial != null
      ? Future.value(null)
      : Future.sync(
          () => widget.roster
              .listTeamRoles(
                clubId: widget.contextValue.clubId,
                teamId: widget.contextValue.teamId!,
              )
              .timeout(const Duration(seconds: 15)),
        ).then<TeamRoles?>((value) => value, onError: (_) => null);
  // 'player', 'leader' or 'both'.
  String _newRole = 'player';
  final Set<String> _newTitles = {};
  final Set<String> _newPositions = {};

  bool get _isEditing => widget.initial != null;
  bool get _newIsLeader => _newRole != 'player';
  bool get _newIsPlayer => _newRole != 'leader';

  @override
  void initState() {
    super.initState();
    _name.addListener(_submission.markDirty);
    for (final field in _contactFields) {
      field.addListener(_markContactChanged);
    }
  }

  @override
  void dispose() {
    _name.removeListener(_submission.markDirty);
    _name.dispose();
    for (final field in _contactFields) {
      field.removeListener(_markContactChanged);
      field.dispose();
    }
    _submission.dispose();
    super.dispose();
  }

  String? _trimmed(TextEditingController field) =>
      field.text.trim().isEmpty ? null : field.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      final saved = await _submission.run(() async {
        final teamId = widget.contextValue.teamId!;
        if (_isEditing) {
          final initial = widget.initial!;
          var revision = initial.personRevision!;
          if (_name.text.trim() != initial.displayName ||
              _birthYear != initial.birthYear ||
              _birthDate != initial.birthDate) {
            revision = await widget.roster.updatePerson(
              clubId: widget.contextValue.clubId,
              teamId: teamId,
              personId: initial.id,
              displayName: _name.text.trim(),
              birthYear: _birthYear!,
              birthDate: _birthDate,
              expectedRevision: revision,
              idempotencyKey: _newUuid(),
            );
          }
          if (_editsContact && _contactChanged) {
            await widget.profileServices.setPersonContact(
              clubId: widget.contextValue.clubId,
              teamId: teamId,
              personId: initial.id,
              contactEmail: _trimmed(_email),
              phone: _trimmed(_phone),
            );
            await widget.profileServices.setPersonAddress(
              clubId: widget.contextValue.clubId,
              teamId: teamId,
              personId: initial.id,
              street: _trimmed(_street),
              postalCode: _trimmed(_postal),
              city: _trimmed(_city),
            );
          }
          if (_guardianRequired != widget.initial!.safeguardingRequired) {
            revision = await widget.roster.setGuardianRequirement(
              clubId: widget.contextValue.clubId,
              teamId: teamId,
              personId: widget.initial!.id,
              guardianRequired: _guardianRequired,
              expectedRevision: revision,
              idempotencyKey: _newUuid(),
            );
          }
          if (_representationAvailable !=
              (widget.initial!.representationAvailable ?? false)) {
            revision = await widget.roster.setRepresentationAvailable(
              clubId: widget.contextValue.clubId,
              teamId: teamId,
              personId: widget.initial!.id,
              available: _representationAvailable,
              expectedRevision: revision,
              idempotencyKey: _newUuid(),
            );
          }
        } else {
          final personId = await widget.roster.createPerson(
            clubId: widget.contextValue.clubId,
            teamId: teamId,
            displayName: _name.text.trim(),
            birthYear: _birthYear!,
            birthDate: _birthDate,
            startsAt: DateTime.now().toUtc(),
            idempotencyKey: _newUuid(),
          );
          await _applyNewRole(teamId, personId);
        }
        await widget.onSaved();
      });
      if (saved && mounted) Navigator.pop(context);
    } on ProfileException catch (error) {
      if (mounted) {
        setState(
          () => _error = _profileErrorMessage(AppStrings.of(context), error),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.of(context).feature(
            'Personen kunde inte sparas. Kontrollera uppgifterna och ladda om innan du försöker igen.',
          );
        });
      }
    }
  }

  /// Gives a just-created person (a player in the team) the chosen role,
  /// titles and positions. The person already exists, so a failure here is
  /// reported without undoing that; it can be fixed on the profile.
  Future<void> _applyNewRole(String teamId, String personId) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.of(context);
    final roles = await _teamRoles;
    if (roles == null) return;
    try {
      if (roles.canManage && _newIsLeader) {
        await widget.roster.setTeamRole(
          clubId: widget.contextValue.clubId,
          teamId: teamId,
          personId: personId,
          fromRole: _newIsPlayer ? null : 'player',
          toRole: 'leader',
          idempotencyKey: _newUuid(),
        );
      }
      final leader = roles.canManage && _newIsLeader;
      final titles = leader ? (_newTitles.toList()..sort()) : <String>[];
      final positions = _newIsPlayer
          ? (_newPositions.toList()..sort())
          : <String>[];
      if (roles.canEditDetails && (titles.isNotEmpty || positions.isNotEmpty)) {
        await widget.roster.setTeamPersonDetails(
          clubId: widget.contextValue.clubId,
          teamId: teamId,
          personId: personId,
          titles: titles,
          positions: positions,
          customTitles: const [],
          customPositions: const [],
          // A single position is the main one.
          mainPosition: positions.length == 1 ? positions.single : null,
          expectedRevision: 0,
          idempotencyKey: _newUuid(),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Personen lades till, men roll, titel eller position kunde inte sparas. Ändra det på personens profil.',
            ),
          ),
        ),
      );
    }
  }

  /// Role, title and position for a new person, shown as far as the viewer
  /// may set them.
  Widget _newRoleSection(AppStrings strings) => FutureBuilder<TeamRoles?>(
    future: _teamRoles,
    builder: (context, snapshot) {
      final roles = snapshot.data;
      if (roles == null) return const SizedBox.shrink();
      final leader = roles.canManage && _newIsLeader;
      Widget heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
      Widget chips(
        Iterable<String> keys,
        Set<String> selected,
        String Function(String key) label,
        String keyPrefix,
      ) => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final key in keys)
            FilterChip(
              key: ValueKey('$keyPrefix-$key'),
              label: Text(label(key)),
              selected: selected.contains(key),
              onSelected: (value) {
                setState(
                  () => value ? selected.add(key) : selected.remove(key),
                );
                _submission.markDirty();
              },
            ),
        ],
      );
      final catalog = [
        ...roles.positionCatalog.where((item) => item.level == 'general'),
        ...roles.positionCatalog.where((item) => item.level != 'general'),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (roles.canManage) ...[
            heading(strings.feature('Roll i laget')),
            SegmentedButton<String>(
              key: const ValueKey('new-person-role'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'player',
                  label: Text(strings.feature('Spelare')),
                ),
                ButtonSegment(
                  value: 'leader',
                  label: Text(strings.feature('Ledare')),
                ),
                ButtonSegment(
                  value: 'both',
                  label: Text(strings.feature('Båda')),
                ),
              ],
              selected: {_newRole},
              onSelectionChanged: (value) {
                setState(() => _newRole = value.single);
                _submission.markDirty();
              },
            ),
          ],
          if (roles.canEditDetails && leader) ...[
            heading(strings.feature('Titel')),
            chips(
              _teamTitleLabels.keys,
              _newTitles,
              (key) => _titleLabel(strings, key),
              'new-person-title',
            ),
          ],
          if (roles.canEditDetails && _newIsPlayer && catalog.isNotEmpty) ...[
            heading(
              '${strings.feature('Position')} · ${_sportLabel(strings, roles.sport)}',
            ),
            chips(
              catalog.map((item) => item.key),
              _newPositions,
              (key) => _positionLabel(strings, key),
              'new-person-position',
            ),
          ],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AppUnsavedChangesScope(
      controller: _submission,
      title: strings.feature('Kasta ändringar?'),
      message: strings.feature('Dina ändringar har inte sparats.'),
      discardLabel: strings.feature('Kasta'),
      cancelLabel: strings.feature('Avbryt'),
      child: ListenableBuilder(
        listenable: _submission,
        builder: (context, _) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings.feature(
                      _isEditing ? 'Redigera person' : 'Lägg till person',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.feature(
                      'Uppgifterna tillhör klubben och ändrar inte användarens globala identitet.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _name,
                    autofocus: !_isEditing,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: strings.feature('Visningsnamn'),
                    ),
                    validator: (value) {
                      final length = value?.trim().length ?? 0;
                      return length < 1 || length > 120
                          ? strings.feature('Ange ett namn med 1–120 tecken.')
                          : null;
                    },
                  ),
                  if (_isEditing)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.feature('Behöver vårdnadshavarkoppling'),
                      ),
                      subtitle: Text(
                        strings.feature(
                          'Gör personen valbar som barn i en guardianinbjudan.',
                        ),
                      ),
                      value: _guardianRequired,
                      onChanged: (value) {
                        setState(() => _guardianRequired = value);
                        _submission.markDirty();
                      },
                    ),
                  if (_isEditing && widget.initial!.homeMember)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.feature('Tillåt representation i andra lag'),
                      ),
                      subtitle: Text(
                        strings.feature(
                          'Gör personen valbar när ett annat lag i klubben '
                          'vill be om representation. Ingen börjar '
                          'representera automatiskt -- ditt lag godkänner '
                          'varje sådan begäran för sig.',
                        ),
                      ),
                      value: _representationAvailable,
                      onChanged: (value) {
                        setState(() => _representationAvailable = value);
                        _submission.markDirty();
                      },
                    ),
                  DropdownButtonFormField<int>(
                    key: const Key('roster-birth-year-field'),
                    initialValue: _birthYear,
                    decoration: InputDecoration(
                      labelText: strings.feature('Födelseår'),
                    ),
                    items: [
                      for (
                        var year = DateTime.now().year;
                        year >= DateTime.now().year - 120;
                        year--
                      )
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (year) {
                      setState(() {
                        _birthYear = year;
                        if (_birthDate?.year != year) _birthDate = null;
                      });
                      _submission.markDirty();
                    },
                    validator: (_) => _birthYear == null
                        ? strings.feature('Välj ett födelseår.')
                        : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _birthYear == null ? null : _pickBirthDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      _birthDate == null
                          ? strings.feature('Lägg till fullständigt datum')
                          : _formatBirthDate(_birthDate!),
                    ),
                  ),
                  if (_birthDate != null)
                    TextButton(
                      onPressed: () {
                        setState(() => _birthDate = null);
                        _submission.markDirty();
                      },
                      child: Text(strings.feature('Ta bort exakt datum')),
                    ),
                  if (!_isEditing) _newRoleSection(strings),
                  if (_isEditing) ..._contactSection(context, strings),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _submission.canSubmit ? _save : null,
                    child: _submission.isPending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(strings.feature('Spara person')),
                  ),
                  if (_isEditing && widget.initial!.assignmentState == 'active')
                    ..._personActionTiles(context, widget.initial!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _contactSection(BuildContext context, AppStrings strings) {
    final contact = widget.contact;
    if (contact == null || !contact.canSeeContact) return const [];
    final heading = Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Text(
        strings.feature('Kontaktuppgifter'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
    if (!_editsContact) {
      return [
        heading,
        Text(
          strings.feature(
            'Personen har ett konto och sköter sina kontaktuppgifter själv.',
          ),
          key: const ValueKey('person-contact-own'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    return [
      heading,
      Text(
        strings.feature(
          'Personen har inget konto, så klubben fyller i uppgifterna.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: const ValueKey('club-contact-email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(labelText: strings.feature('E-post')),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('club-contact-phone'),
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(labelText: strings.feature('Telefon')),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const ValueKey('club-contact-street'),
        controller: _street,
        decoration: InputDecoration(labelText: strings.feature('Gatuadress')),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          SizedBox(
            width: 120,
            child: TextFormField(
              key: const ValueKey('club-contact-postal'),
              controller: _postal,
              decoration: InputDecoration(
                labelText: strings.feature('Postnummer'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: const ValueKey('club-contact-city'),
              controller: _city,
              decoration: InputDecoration(labelText: strings.feature('Ort')),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _personActionTiles(
    BuildContext context,
    RosterPersonDetails person,
  ) {
    final strings = AppStrings.of(context);
    return [
      const SizedBox(height: 16),
      const Divider(),
      Text(
        strings.feature('Åtgärder'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      // Role, titles and permissions are managed on the profile itself.
      if (person.accountLinked != true)
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(strings.feature('Bjud in')),
          subtitle: Text(
            strings.feature(
              'Skicka en inbjudan så personen kan koppla ett konto.',
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _inviteFromProfile(
            context: context,
            contextValue: widget.contextValue,
            roster: widget.roster,
            person: person,
          ),
        ),
      // Leaders are in the team through their role, not a home-team
      // assignment, so moving, representation and archiving do not apply.
      if (person.homeMember) ..._playerActionTiles(context, person),
    ];
  }

  List<Widget> _playerActionTiles(
    BuildContext context,
    RosterPersonDetails person,
  ) {
    final strings = AppStrings.of(context);
    return [
      ListTile(
        leading: const Icon(Icons.compare_arrows),
        title: Text(strings.feature('Representation i annat lag')),
        subtitle: Text(
          strings.feature('Föreslå personen för ett annat lag i klubben.'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _representFromProfile(
          context: context,
          contextValue: widget.contextValue,
          roster: widget.roster,
          person: person,
        ),
      ),
      ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: Text(strings.feature('Flytta till ett annat lag')),
        subtitle: Text(
          strings.feature(
            'Nuvarande lagtillhörighet avslutas och historiken bevaras.',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _IntraClubMoveSheet(
            contextValue: widget.contextValue,
            roster: widget.roster,
            initialPersonId: person.id,
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.archive_outlined),
        title: Text(strings.feature('Avsluta i laget')),
        subtitle: Text(
          strings.feature(
            'Spelaren flyttas till Arkiverade. Namn, matcher, närvaro och annan historik bevaras.',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _archivePersonFromDetails(
          context: context,
          contextValue: widget.contextValue,
          roster: widget.roster,
          personId: person.id,
          onArchived: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
      ),
    ];
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final year = _birthYear!;
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(year, 1, 1),
      firstDate: DateTime(year, 1, 1),
      lastDate: year == now.year
          ? DateTime(now.year, now.month, now.day)
          : DateTime(year, 12, 31),
      helpText: AppStrings.of(context).feature('Välj födelsedatum'),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _birthDate = DateTime(selected.year, selected.month, selected.day);
    });
    _submission.markDirty();
  }
}

String _formatBirthDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class _NoOwnTeamProfile implements Exception {
  const _NoOwnTeamProfile();
}

class _RosterPersonDetailsView extends StatelessWidget {
  const _RosterPersonDetailsView({
    super.key,
    required this.future,
    required this.roles,
    required this.contextValue,
    required this.roster,
    required this.canManage,
    required this.onRolesChanged,
    this.contact,
    this.onOpenMemberCard,
  });
  final Future<RosterPersonDetails> future;

  /// Contact details and picture URL for the person.
  final Future<(PersonContact, String?)>? contact;
  final void Function(RosterPersonDetails person)? onOpenMemberCard;

  /// The team's roles, loaded once and shared by the role, title and
  /// permission tiles.
  final Future<TeamRoles> roles;
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final bool canManage;
  final void Function(RosterPersonDetails person, List<String> roles)
  onRolesChanged;

  @override
  Widget build(BuildContext context) => FutureBuilder<RosterPersonDetails>(
    future: future,
    builder: (context, snapshot) {
      final strings = AppStrings.of(context);
      if (snapshot.connectionState != ConnectionState.done) {
        return AppLoadingIndicator(
          label: strings.feature('Laddar medlemsdetaljer'),
        );
      }
      if (snapshot.error is _NoOwnTeamProfile) {
        return _StateCard(
          icon: Icons.person_off_outlined,
          title: strings.feature('Du har ingen profil i det här laget'),
          message: strings.feature(
            'Byt till ett lag där du är spelare eller ledare, eller se dina kontouppgifter under Inställningar.',
          ),
          action: OutlinedButton.icon(
            onPressed: () =>
                GoRouter.of(context).go(ProductRouteContract.settings),
            icon: const Icon(Icons.settings_outlined),
            label: Text(strings.feature('Inställningar')),
          ),
        );
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return _StateCard(
          icon: Icons.lock_outline,
          title: strings.feature('Medlemsdetaljen kunde inte laddas'),
          message: strings.feature(
            'Kontrollera din behörighet och försök igen.',
          ),
        );
      }
      final person = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: FutureBuilder<(PersonContact, String?)>(
              future: contact,
              builder: (context, snapshot) => _ProfileAvatar(
                key: const ValueKey('person-profile-avatar'),
                name: person.displayName,
                url: snapshot.data?.$2,
                radius: 34,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            person.isSelf
                ? '${person.displayName} (${strings.feature('du')})'
                : person.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          FutureBuilder<TeamRoles>(
            future: roles,
            builder: (context, rolesSnapshot) {
              final held = rolesSnapshot.data?.rolesOf(person.id) ?? const [];
              if (held.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  held.map((role) => _roleLabel(strings, role)).join(' · '),
                  key: const ValueKey('person-profile-roles'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            },
          ),
          if (onOpenMemberCard != null) ...[
            const SizedBox(height: 12),
            Center(
              child: FilledButton.tonalIcon(
                key: const ValueKey('open-member-card'),
                onPressed: () => onOpenMemberCard!(person),
                icon: const Icon(Icons.badge_outlined),
                label: Text(strings.feature('Visa medlemskort')),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(strings.feature('Lag')),
            subtitle: Text(person.teamName),
          ),
          if (person.ageClass != null)
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(strings.feature('Födelseår')),
              subtitle: Text(person.ageClass!),
            ),
          FutureBuilder<(PersonContact, String?)>(
            future: contact,
            builder: (context, snapshot) {
              final value = snapshot.data?.$1;
              if (value == null) return const SizedBox.shrink();
              return _PersonContactTiles(contact: value, isSelf: person.isSelf);
            },
          ),
          _PersonRoleTile(
            contextValue: contextValue,
            roster: roster,
            person: person,
            roles: roles,
            onChanged: (held) => onRolesChanged(person, held),
            interactive: !person.isSelf,
          ),
          _PersonTeamDetailsTile(
            roster: roster,
            clubId: contextValue.clubId,
            teamId: person.teamId,
            personId: person.id,
            roles: roles,
            interactive: !person.isSelf,
          ),
          _PersonPermissionsTile(
            contextValue: contextValue,
            roster: roster,
            personId: person.id,
            roles: roles,
          ),
          if (person.birthDate != null)
            ListTile(
              leading: const Icon(Icons.cake_outlined),
              title: Text(strings.feature('Födelsedatum')),
              subtitle: Text(_formatBirthDate(person.birthDate!)),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(strings.feature('Status')),
            subtitle: Text(strings.domainValue(person.assignmentState)),
          ),
        ],
      );
    },
  );
}

class _RosterPersonDetailsPage extends StatefulWidget {
  const _RosterPersonDetailsPage({
    required this.personId,
    required this.contextValue,
    required this.roster,
    required this.onBack,
    this.profileServices = const UnconfiguredProfileServices(),
    this.onOwnProfileChanged,
    this.personalSettings,
  });

  final String personId;
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final ProfileServices profileServices;

  /// Tells the app your own name or picture changed.
  final VoidCallback? onOwnProfileChanged;

  /// Your personal settings, shown as a tab on your own profile.
  final Widget Function()? personalSettings;
  final VoidCallback onBack;

  @override
  State<_RosterPersonDetailsPage> createState() =>
      _RosterPersonDetailsPageState();
}

class _RosterPersonDetailsPageState extends State<_RosterPersonDetailsPage> {
  late Future<TeamRoles> _roles = _loadRoles();
  late Future<RosterPersonDetails> _load = _reload();
  late Future<(PersonContact, String?)> _contact = _loadContact();
  // Bumped on every reload so the profile tiles pick up the new roles.
  int _generation = 0;

  /// Contact details and picture; optional, so failures just hide them.
  Future<(PersonContact, String?)> _loadContact() async {
    try {
      final person = await _load;
      final contact = await widget.profileServices
          .getPersonContact(
            clubId: widget.contextValue.clubId,
            teamId: person.teamId,
            personId: person.id,
          )
          .timeout(const Duration(seconds: 15));
      String? url;
      final avatar = contact.avatarProfileId;
      if (avatar != null) {
        try {
          url = await widget.profileServices.avatarUrl(avatar);
        } catch (_) {}
      }
      return (contact, url);
    } catch (_) {
      return (const PersonContact(), null);
    }
  }

  Future<TeamRoles> _loadRoles() {
    final teamId = widget.contextValue.teamId;
    final roles = teamId == null
        ? Future<TeamRoles>.error(StateError('No team'))
        : Future.sync(
            () => widget.roster
                .listTeamRoles(
                  clubId: widget.contextValue.clubId,
                  teamId: teamId,
                )
                .timeout(const Duration(seconds: 15)),
          );
    // Builders show the failure; it may settle before any of them listens.
    return roles..ignore();
  }

  /// ProductRouteContract.ownTeamProfile resolves to your own person in the
  /// active team through your role there.
  Future<String> _personId() async {
    if (widget.personId != ProductRouteContract.selfPersonId) {
      return widget.personId;
    }
    final TeamRoles roles;
    try {
      roles = await _roles;
    } catch (_) {
      throw const _NoOwnTeamProfile();
    }
    final own = roles.roles.where((role) => role.isSelf).firstOrNull;
    if (own == null) throw const _NoOwnTeamProfile();
    return own.personId;
  }

  Future<RosterPersonDetails> _reload() async {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) throw const _NoOwnTeamProfile();
    return widget.roster
        .getPersonDetails(
          clubId: widget.contextValue.clubId,
          teamId: teamId,
          personId: await _personId(),
        )
        .timeout(const Duration(seconds: 15));
  }

  void _refresh() => setState(() {
    _roles = _loadRoles();
    _load = _reload();
    _contact = _loadContact();
    _generation++;
  });

  void _rolesChanged(RosterPersonDetails person, List<String> held) {
    // A leader whose last role here ended is no longer in the team.
    if (held.isEmpty && !person.homeMember) {
      widget.onBack();
      return;
    }
    _refresh();
  }

  Future<void> _editOwnProfile(RosterPersonDetails person) async {
    await _openMyProfileEditor(
      context,
      widget.profileServices,
      onProfileChanged: widget.onOwnProfileChanged,
      teamDetails: ListView(
        key: const ValueKey('edit-team-role-tab'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${widget.contextValue.clubName} · ${person.teamName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _PersonRoleTile(
            contextValue: widget.contextValue,
            roster: widget.roster,
            person: person,
            roles: _roles,
          ),
          _PersonTeamDetailsTile(
            roster: widget.roster,
            clubId: widget.contextValue.clubId,
            teamId: person.teamId,
            personId: person.id,
            roles: _roles,
          ),
        ],
      ),
      settings: widget.personalSettings?.call(),
    );
    if (!mounted) return;
    widget.onOwnProfileChanged?.call();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final contextValue = widget.contextValue;
    final canManage =
        contextValue.can('club.memberships.manage') ||
        contextValue.can('team.roster.manage');
    final canView = contextValue.can('team.roster.view') || canManage;
    const supportedRoles = {'player', 'leader', 'guardian', 'club_functionary'};
    final allowed =
        canView &&
        supportedRoles.contains(contextValue.rolePackage) &&
        contextValue.rolePackage != 'guardian' &&
        contextValue.teamId != null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: strings.feature('Tillbaka till truppen'),
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(strings.feature('Medlemsuppgifter')),
        actions: [
          if (allowed)
            FutureBuilder<RosterPersonDetails>(
              future: _load,
              builder: (context, snapshot) {
                final person = snapshot.data;
                if (person == null || person.assignmentState != 'active') {
                  return const SizedBox.shrink();
                }
                if (person.isSelf) {
                  return IconButton(
                    key: const ValueKey('edit-own-profile-appbar'),
                    tooltip: strings.feature('Redigera profil'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editOwnProfile(person),
                  );
                }
                if (!canManage) return const SizedBox.shrink();
                return IconButton(
                  key: const ValueKey('edit-member'),
                  tooltip: strings.feature('Redigera medlem'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    PersonContact? contact;
                    try {
                      contact = (await _contact).$1;
                    } catch (_) {
                      // Edited without contact details.
                    }
                    if (!context.mounted) return;
                    await _openRosterPersonEditor(
                      context,
                      contextValue: contextValue,
                      roster: widget.roster,
                      personId: person.id,
                      onSaved: () async {},
                      profileServices: widget.profileServices,
                      contact: contact,
                    );
                    _refresh();
                  },
                );
              },
            ),
        ],
      ),
      body: allowed
          ? FutureBuilder<RosterPersonDetails>(
              future: _load,
              builder: (context, snapshot) {
                final view = _RosterPersonDetailsView(
                  key: ValueKey(_generation),
                  future: _load,
                  roles: _roles,
                  contact: _contact,
                  contextValue: contextValue,
                  roster: widget.roster,
                  canManage: canManage,
                  onRolesChanged: _rolesChanged,
                  onOpenMemberCard: (person) => _openMemberCard(
                    context,
                    profile: widget.profileServices,
                    clubId: contextValue.clubId,
                    teamId: person.teamId,
                    personId: person.id,
                  ),
                );
                final person = snapshot.data;
                if (person == null) return view;
                // Statistics for yourself and those who manage the team.
                // Own settings live in the app-bar edit flow.
                final showStats = person.isSelf || canManage;
                final tabs = <(String, Widget)>[
                  (strings.feature('Medlemsinfo'), view),
                  if (showStats)
                    (
                      strings.feature('Statistik'),
                      _PersonStatisticsView(
                        key: ValueKey('stats-$_generation'),
                        profile: widget.profileServices,
                        clubId: contextValue.clubId,
                        teamId: person.teamId,
                        personId: person.id,
                        homeMember: person.homeMember,
                      ),
                    ),
                ];
                if (tabs.length == 1) return view;
                return DefaultTabController(
                  key: ValueKey('profile-tabs-${tabs.length}'),
                  length: tabs.length,
                  child: Column(
                    children: [
                      TabBar(tabs: [for (final tab in tabs) Tab(text: tab.$1)]),
                      Expanded(
                        child: TabBarView(
                          children: [for (final tab in tabs) tab.$2],
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          : _StateCard(
              icon: Icons.lock_outline,
              title: strings.feature('Medlemsdetaljen är inte tillgänglig'),
              message: strings.feature(
                'Din roll saknar behörighet att visa de här uppgifterna.',
              ),
              action: OutlinedButton(
                onPressed: widget.onBack,
                child: Text(strings.feature('Tillbaka till truppen')),
              ),
            ),
    );
  }
}

Future<void> _archivePersonFromDetails({
  required BuildContext context,
  required TeamZoneContext contextValue,
  required RosterServices roster,
  required String personId,
  required VoidCallback onArchived,
}) async {
  final strings = AppStrings.of(context);
  final reasonController = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.feature('Avsluta i laget')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.feature(
              'Spelaren flyttas till Arkiverade. Namn, matcher, närvaro och annan historik bevaras.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: reasonController,
            autofocus: true,
            maxLength: 240,
            decoration: InputDecoration(
              labelText: strings.feature('Anledning'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            final value = reasonController.text.trim();
            if (value.isNotEmpty) Navigator.pop(dialogContext, value);
          },
          child: Text(strings.feature('Avsluta i laget')),
        ),
      ],
    ),
  );
  reasonController.dispose();
  if (reason == null || !context.mounted) return;

  try {
    final lifecycle = await roster.getRosterLifecycle(
      clubId: contextValue.clubId,
      teamId: contextValue.teamId!,
    );
    final assignment = lifecycle.people
        .where(
          (person) =>
              person.personId == personId && person.assignmentState == 'active',
        )
        .firstOrNull;
    if (assignment == null) {
      throw StateError('Active assignment is no longer available.');
    }
    await roster.archiveTeamAssignment(
      clubId: contextValue.clubId,
      teamId: contextValue.teamId!,
      personId: personId,
      assignmentId: assignment.assignmentId,
      expectedRevision: assignment.assignmentRevision,
      reason: reason,
      idempotencyKey: _newUuid(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.feature('Spelaren är arkiverad.'))),
    );
    onArchived();
  } catch (error, stackTrace) {
    debugPrint('TEAM-08 profile archive failed: $error\n$stackTrace');
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.feature('Avsluta i laget')),
        content: Text(
          strings.feature(
            'Åtgärden kunde inte sparas. Ladda om och försök igen.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.close),
          ),
        ],
      ),
    );
  }
}

Future<void> _showProfileActionMessage(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<void>(
  context: context,
  useRootNavigator: true,
  builder: (dialogContext) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(AppStrings.of(context).close),
      ),
    ],
  ),
);

Future<void> _inviteFromProfile({
  required BuildContext context,
  required TeamZoneContext contextValue,
  required RosterServices roster,
  required RosterPersonDetails person,
}) async {
  List<RosterPersonSummary> people;
  try {
    people = await roster
        .listPeople(clubId: contextValue.clubId, teamId: contextValue.teamId!)
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    people = const [];
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _InvitationAdminSheet(
      contextValue: contextValue,
      roster: roster,
      people: people,
      initialPersonId: person.id,
    ),
  );
}

Future<void> _representFromProfile({
  required BuildContext context,
  required TeamZoneContext contextValue,
  required RosterServices roster,
  required RosterPersonDetails person,
}) async {
  final strings = AppStrings.of(context);
  final title = strings.feature('Representation i annat lag');
  if (person.representationAvailable != true) {
    await _showProfileActionMessage(
      context,
      title: title,
      message: strings.feature(
        'Slå på "Tillåt representation i andra lag" under Redigera person '
        'innan du fortsätter här.',
      ),
    );
    return;
  }
  IntraClubMoveOptions options;
  try {
    options = await roster
        .getIntraClubMoveOptions(
          clubId: contextValue.clubId,
          sourceTeamId: contextValue.teamId!,
        )
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    if (context.mounted) {
      await _showProfileActionMessage(
        context,
        title: title,
        message: strings.feature('Lagen kunde inte laddas. Försök igen.'),
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (options.teams.isEmpty) {
    await _showProfileActionMessage(
      context,
      title: title,
      message: strings.feature('Det finns inga andra aktiva lag i klubben.'),
    );
    return;
  }
  var targetTeamId = options.teams.first.id;
  var kind = 'development';
  var validity = 'season';
  var boundary = DateTime(DateTime.now().year + 1, 6, 30);
  var sourceNote = 'Beslut av lagansvarig';
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: targetTeamId,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Lag'),
                ),
                items: options.teams
                    .map(
                      (team) => DropdownMenuItem(
                        value: team.id,
                        child: Text(team.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => targetTeamId = value ?? targetTeamId),
              ),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Typ'),
                ),
                items: const ['development', 'dispensation', 'loan', 'guest']
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(AppStrings.of(context).domainValue(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => kind = value ?? kind),
              ),
              DropdownButtonFormField<String>(
                initialValue: validity,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Giltighet'),
                ),
                items: const ['season', 'fixed', 'indefinite']
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(AppStrings.of(context).domainValue(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  validity = value ?? validity;
                  boundary = validity == 'indefinite'
                      ? DateTime.now().add(const Duration(days: 90))
                      : validity == 'fixed'
                      ? DateTime.now().add(const Duration(days: 30))
                      : DateTime(DateTime.now().year + 1, 6, 30);
                }),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  AppStrings.of(context).feature(
                    validity == 'indefinite'
                        ? 'Granskas senast'
                        : 'Gäller till',
                  ),
                ),
                subtitle: Text(
                  MaterialLocalizations.of(context).formatMediumDate(boundary),
                ),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    initialDate: boundary,
                  );
                  if (value != null) setDialogState(() => boundary = value);
                },
              ),
              TextFormField(
                initialValue: sourceNote,
                onChanged: (value) => sourceNote = value,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Beslutsunderlag'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.of(context).feature('Skicka')),
          ),
        ],
      ),
    ),
  );
  final note = sourceNote.trim();
  if (confirmed != true || note.length < 2 || !context.mounted) return;
  try {
    final endOfDay = DateTime(
      boundary.year,
      boundary.month,
      boundary.day,
      23,
      59,
      59,
    );
    await roster.createPlayEligibility(
      clubId: contextValue.clubId,
      teamId: targetTeamId,
      personId: person.id,
      kind: kind,
      validityKind: validity,
      startsAt: DateTime.now().toUtc(),
      endsAt: validity == 'indefinite' ? null : endOfDay,
      seasonEndsOn: validity == 'season' ? boundary : null,
      reviewDueAt: validity == 'indefinite' ? endOfDay : null,
      sourceNote: note,
      idempotencyKey: _newUuid(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Förfrågan skickad. Ditt lag behöver godkänna den innan '
              'det andra laget kan använda spelaren.',
            ),
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      await _showProfileActionMessage(
        context,
        title: title,
        message: strings.feature(
          'Förfrågan kunde inte sparas. Kontrollera lag, period och överlapp.',
        ),
      );
    }
  }
}

int _teamTabIndex(String? value) => switch (value) {
  'roster' => 1,
  'calendar' => 2,
  _ => 0,
};

class _TeamOverviewSurface extends StatefulWidget {
  const _TeamOverviewSurface({
    required this.contextValue,
    required this.roster,
    required this.calendar,
    required this.onNavigate,
    required this.onOpenApplications,
    required this.onOpenInvitations,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final CalendarServices calendar;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onOpenApplications;
  final Future<void> Function() onOpenInvitations;

  @override
  State<_TeamOverviewSurface> createState() => _TeamOverviewSurfaceState();
}

/// Team overview, top to bottom: team picture and identity, open
/// invitations and requests (only when there are any and you may handle
/// them), the next event, the latest match, then the team presentation
/// and its leaders.
class _TeamOverviewSurfaceState extends State<_TeamOverviewSurface> {
  late Future<TeamOverview> _load;
  // Titles are an optional enrichment: people without roster access simply
  // see the leader names.
  late Future<TeamRoles?> _roles;
  late Future<List<CalendarEventSummary>> _events;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final teamId = widget.contextValue.teamId;
    _load = teamId == null
        ? Future.error(StateError('Team context required.'))
        : widget.roster
              .getTeamOverview(teamId: teamId)
              .timeout(const Duration(seconds: 15));
    _roles = teamId == null
        ? Future.value(null)
        : widget.roster
              .listTeamRoles(clubId: widget.contextValue.clubId, teamId: teamId)
              .timeout(const Duration(seconds: 15))
              .then<TeamRoles?>((value) => value, onError: (_) => null);
    final now = DateTime.now();
    _events = teamId == null
        ? Future.value(const [])
        : Future.sync(
            () => widget.calendar
                .listCalendar(
                  contextIds: [
                    widget.contextValue.id,
                    ...widget.contextValue.aliasIds,
                  ],
                  from: DateTime(now.year - 1, now.month, now.day),
                  to: DateTime(now.year + 1, now.month, now.day),
                )
                .timeout(const Duration(seconds: 15)),
          );
    // The event cards show their own failure; it may settle first.
    _events.ignore();
  }

  @override
  void didUpdateWidget(covariant _TeamOverviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) setState(_reload);
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<TeamOverview>(
    future: _load,
    builder: (context, snapshot) {
      final strings = AppStrings.of(context);
      if (snapshot.connectionState != ConnectionState.done) {
        return AppLoadingIndicator(
          label: strings.feature('Laddar lagöversikt'),
        );
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return _StateCard(
          icon: Icons.sync_problem,
          title: strings.feature('Lagöversikten kunde inte laddas'),
          message: strings.feature(
            'Försök igen. Ingen administrativ information visas.',
          ),
          action: FilledButton(
            onPressed: () => setState(_reload),
            child: Text(strings.feature('Försök igen')),
          ),
        );
      }
      final value = snapshot.data!;
      final showAdmin =
          value.canManage &&
          (widget.contextValue.can('club.memberships.manage') ||
              widget.contextValue.can('team.roster.manage'));
      final hasRequests =
          value.activeInvitationCount > 0 || value.pendingApplicationCount > 0;
      return RefreshIndicator(
        onRefresh: () async {
          setState(_reload);
          await _load;
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _TeamImage(value: value),
            const SizedBox(height: 20),
            Text(
              value.teamName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              value.clubName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ([value.teamType, value.ageClass].whereType<String>().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  [
                    value.teamType,
                    value.ageClass,
                  ].whereType<String>().join(' · '),
                ),
              ),
            if (showAdmin && hasRequests) ...[
              const SizedBox(height: 20),
              _TeamRequestsCard(
                invitations: value.activeInvitationCount,
                applications: value.pendingApplicationCount,
                onOpenInvitations: () async {
                  await widget.onOpenInvitations();
                  if (mounted) setState(_reload);
                },
                onOpenApplications: () async {
                  await widget.onOpenApplications();
                  if (mounted) setState(_reload);
                },
              ),
            ],
            FutureBuilder<List<CalendarEventSummary>>(
              future: _events,
              builder: (context, eventsSnapshot) => _TeamOverviewEvents(
                snapshot: eventsSnapshot,
                teamId: widget.contextValue.teamId,
                sectionTitle: _sectionTitle,
                onOpenCalendar: () => widget.onNavigate('/team?tab=calendar'),
              ),
            ),
            _sectionTitle(context, strings.feature('Om laget')),
            Text(
              value.summary ??
                  strings.feature('Ingen laginformation har publicerats ännu.'),
            ),
            _sectionTitle(context, strings.feature('Ledare')),
            FutureBuilder<TeamRoles?>(
              future: _roles,
              builder: (context, rolesSnapshot) {
                if (value.leaders.isEmpty) {
                  return Text(strings.feature('Inga ledare visas ännu.'));
                }
                final roles = rolesSnapshot.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final leader in value.leaders)
                      Builder(
                        builder: (context) {
                          final row = roles?.roles
                              .where(
                                (role) =>
                                    role.personId == leader.personId &&
                                    _isLeaderRole(role.role),
                              )
                              .firstOrNull;
                          final titles = row == null
                              ? ''
                              : _titlesSummary(strings, row);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              titles.isEmpty
                                  ? leader.displayName
                                  : '${leader.displayName} · $titles',
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
            if (showAdmin) ...[
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _editTeamProfile,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(strings.feature('Redigera lagprofil')),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  Future<void> _editTeamProfile() async {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) return;
    final strings = AppStrings.of(context);
    try {
      final value = await widget.roster
          .getTeamProfileEdit(teamId: teamId)
          .timeout(const Duration(seconds: 15));
      final roles = await _roles;
      if (!mounted) return;
      final sportKey = _newUuid();
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _TeamProfileEditDialog(
          value: value,
          initialSport: roles?.sport,
          onSportSave: roles?.canSetSport == true
              ? (sport) => widget.roster.setTeamSport(
                  clubId: widget.contextValue.clubId,
                  teamId: teamId,
                  sport: sport,
                  idempotencyKey: sportKey,
                )
              : null,
          onSave:
              ({
                required teamType,
                required ageClass,
                required summary,
                required imageBytes,
                required imageMimeType,
                required removeImage,
              }) async {
                String? stagedImageId;
                if (imageBytes != null && imageMimeType != null) {
                  stagedImageId = await widget.roster.uploadTeamImage(
                    teamId: teamId,
                    mimeType: imageMimeType,
                    bytes: imageBytes,
                    idempotencyKey: _newUuid(),
                  );
                }
                return widget.roster.updateTeamProfile(
                  teamId: teamId,
                  teamType: teamType,
                  ageClass: ageClass,
                  summary: summary,
                  imageAction: stagedImageId != null
                      ? 'replace'
                      : removeImage
                      ? 'remove'
                      : 'keep',
                  stagedImageId: stagedImageId,
                  expectedRevision: value.revision,
                  idempotencyKey: _newUuid(),
                );
              },
        ),
      );
      if (saved == true && mounted) setState(_reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.feature('Lagprofilen kunde inte laddas.')),
          ),
        );
      }
    }
  }
}

/// Open invitations and membership requests. Rows with nothing waiting are
/// left out; the card itself is shown only when something is.
class _TeamRequestsCard extends StatelessWidget {
  const _TeamRequestsCard({
    required this.invitations,
    required this.applications,
    required this.onOpenInvitations,
    required this.onOpenApplications,
  });
  final int invitations, applications;
  final VoidCallback onOpenInvitations, onOpenApplications;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    Widget row(IconData icon, String label, int count, VoidCallback onTap) =>
        ListTile(
          leading: Icon(icon),
          title: Text(strings.feature(label)),
          trailing: Badge.count(count: count, largeSize: 22),
          onTap: onTap,
        );
    return Card(
      key: const ValueKey('team-overview-requests'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              strings.feature('Inbjudningar och förfrågningar'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (invitations > 0)
            row(
              Icons.mark_email_unread_outlined,
              'Aktiva inbjudningar',
              invitations,
              onOpenInvitations,
            ),
          if (applications > 0)
            row(
              Icons.how_to_reg_outlined,
              'Väntande ansökningar',
              applications,
              onOpenApplications,
            ),
        ],
      ),
    );
  }
}

/// "Nästa händelse" and "Senaste match" on the team overview, built from
/// the team's own calendar. Cancelled events are skipped.
class _TeamOverviewEvents extends StatelessWidget {
  const _TeamOverviewEvents({
    required this.snapshot,
    required this.teamId,
    required this.sectionTitle,
    required this.onOpenCalendar,
  });
  final AsyncSnapshot<List<CalendarEventSummary>> snapshot;
  final String? teamId;
  final Widget Function(BuildContext context, String text) sectionTitle;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    Widget placeholder(String text, {bool calendarLink = false}) => Card(
      child: ListTile(
        title: Text(strings.feature(text)),
        trailing: calendarLink ? const Icon(Icons.chevron_right) : null,
        onTap: calendarLink ? onOpenCalendar : null,
      ),
    );
    final nextTitle = sectionTitle(context, strings.feature('Nästa händelse'));
    final matchTitle = sectionTitle(context, strings.feature('Senaste match'));
    if (snapshot.connectionState != ConnectionState.done) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [nextTitle, const LinearProgressIndicator(minHeight: 2)],
      );
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          nextTitle,
          placeholder('Händelserna kunde inte laddas.', calendarLink: true),
        ],
      );
    }
    final now = DateTime.now();
    final events = snapshot.data!
        .where((event) => teamId == null || event.owningTeamId == teamId)
        .where((event) => event.state != 'cancelled')
        .toList();
    final next =
        (events.where((event) => event.endsAt.isAfter(now)).toList()
              ..sort((a, b) => a.startsAt.compareTo(b.startsAt)))
            .firstOrNull;
    final lastMatch =
        (events
                .where(
                  (event) =>
                      event.type == 'match' && event.startsAt.isBefore(now),
                )
                .toList()
              ..sort((a, b) => b.startsAt.compareTo(a.startsAt)))
            .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        nextTitle,
        if (next == null)
          placeholder('Inga kommande händelser.', calendarLink: true)
        else
          KeyedSubtree(
            key: const ValueKey('team-overview-next-event'),
            child: _TeamEventCard(event: next),
          ),
        matchTitle,
        if (lastMatch == null)
          placeholder('Inga spelade matcher ännu.')
        else
          KeyedSubtree(
            key: const ValueKey('team-overview-last-match'),
            child: _TeamEventCard(event: lastMatch),
          ),
      ],
    );
  }
}

class _TeamProfileEditDialog extends StatefulWidget {
  const _TeamProfileEditDialog({
    required this.value,
    required this.onSave,
    this.initialSport,
    this.onSportSave,
  });
  final TeamProfileEditData value;

  /// The team's sport selects its position catalog. Shown only when the
  /// user is a club administrator ([onSportSave] set); others see it read-only.
  final String? initialSport;
  final Future<void> Function(String sport)? onSportSave;
  final Future<int> Function({
    required String teamType,
    required String ageClass,
    required String summary,
    required Uint8List? imageBytes,
    required String? imageMimeType,
    required bool removeImage,
  })
  onSave;
  @override
  State<_TeamProfileEditDialog> createState() => _TeamProfileEditDialogState();
}

class _TeamProfileEditDialogState extends State<_TeamProfileEditDialog> {
  late final _teamType = TextEditingController(text: widget.value.teamType);
  late final _ageClass = TextEditingController(text: widget.value.ageClass);
  late final _summary = TextEditingController(text: widget.value.summary);
  late String? _sport = widget.initialSport;
  final _draft = AppFormController();
  Uint8List? _imageBytes;
  String? _imageMimeType;
  String? _imageName;
  bool _removeImage = false;
  bool _saving = false;
  String? _error;

  static const _sportIcons = {
    'football': Icons.sports_soccer,
    'handball': Icons.sports_handball,
    'other': Icons.sports_outlined,
  };

  @override
  void initState() {
    super.initState();
    for (final controller in [_teamType, _ageClass, _summary]) {
      controller.addListener(_draft.markDirty);
    }
  }

  @override
  void dispose() {
    for (final field in [_teamType, _ageClass, _summary]) {
      field.removeListener(_draft.markDirty);
      field.dispose();
    }
    _draft.dispose();
    super.dispose();
  }

  bool get _hasImage =>
      _imageBytes != null || (widget.value.imageUrl != null && !_removeImage);

  Widget _section(
    BuildContext context,
    IconData icon,
    String title,
    List<Widget> children,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _imagePreview(BuildContext context) {
    final image = _imageBytes != null
        ? Image.memory(
            _imageBytes!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _imageFallback(context),
          )
        : !_removeImage && widget.value.imageUrl != null
        ? Image.network(
            widget.value.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _imageFallback(context),
          )
        : _imageFallback(context);
    return AspectRatio(
      aspectRatio: 16 / 7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('team-image-preview'),
            onTap: _saving ? null : _pickImage,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final fullScreen = MediaQuery.sizeOf(context).width < 600;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: strings.feature('Stäng'),
            onPressed: _saving ? null : () => Navigator.maybePop(context),
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              strings.feature('Redigera lagprofil'),
              style: theme.textTheme.titleLarge,
            ),
          ),
          FilledButton(
            key: const ValueKey('save-team-profile'),
            onPressed: _saving ? null : _save,
            child: Text(strings.save),
          ),
        ],
      ),
    );

    final form = ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        _section(context, Icons.image_outlined, strings.feature('Lagbild'), [
          _imagePreview(context),
          if (_imageName != null) ...[
            const SizedBox(height: 6),
            Text(
              _imageName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.upload_outlined),
                label: Text(
                  strings.feature(
                    widget.value.imageUrl == null && _imageBytes == null
                        ? 'Välj lagbild'
                        : 'Byt lagbild',
                  ),
                ),
              ),
              if (_hasImage)
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _imageBytes = null;
                          _imageMimeType = null;
                          _imageName = null;
                          _removeImage = true;
                          _draft.markDirty();
                        }),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(strings.feature('Ta bort lagbild')),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            strings.feature(
              'JPG, PNG eller WebP. Max 5 MB. Originalet lagras privat.',
            ),
            style: theme.textTheme.bodySmall,
          ),
        ]),
        _section(context, Icons.groups_outlined, strings.feature('Om laget'), [
          LayoutBuilder(
            builder: (context, constraints) {
              final type = TextFormField(
                key: const ValueKey('team-type'),
                controller: _teamType,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: strings.feature('Lagtyp'),
                  hintText: strings.feature('T.ex. Flicklag'),
                ),
              );
              final age = TextFormField(
                key: const ValueKey('team-age-class'),
                controller: _ageClass,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: strings.feature('Åldersklass'),
                  hintText: strings.feature('T.ex. F2012'),
                ),
              );
              return constraints.maxWidth >= 440
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: type),
                        const SizedBox(width: 12),
                        Expanded(child: age),
                      ],
                    )
                  : Column(children: [type, age]);
            },
          ),
          if (widget.onSportSave == null && _sport != null)
            ListTile(
              key: const ValueKey('team-sport-readonly'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(_sportIcons[_sport] ?? Icons.sports_outlined),
              title: Text(_sportLabel(strings, _sport!)),
              subtitle: Text(
                strings.feature('Idrotten ändras av klubbens administratörer.'),
              ),
              trailing: const Icon(Icons.lock_outline, size: 18),
            ),
          if (widget.onSportSave != null && _sport != null) ...[
            const SizedBox(height: 4),
            Text(strings.feature('Idrott'), style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              key: const ValueKey('team-sport'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sport in _sportLabels.keys)
                  ChoiceChip(
                    key: ValueKey('team-sport-$sport'),
                    avatar: Icon(
                      _sportIcons[sport] ?? Icons.sports_outlined,
                      size: 18,
                    ),
                    label: Text(_sportLabel(strings, sport)),
                    selected: _sport == sport,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() {
                            _sport = sport;
                            _draft.markDirty();
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              strings.feature(
                'Styr vilka spelarpositioner som finns att välja.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ]),
        _section(
          context,
          Icons.notes_outlined,
          strings.feature('Presentation'),
          [
            TextFormField(
              key: const ValueKey('team-summary'),
              controller: _summary,
              maxLength: 1000,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: strings.feature('Kort lagpresentation'),
                hintText: strings.feature(
                  'Vilka ni är, var ni tränar och vad som gäller för laget.',
                ),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1),
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Material(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: form),
      ],
    );

    return AppUnsavedChangesScope(
      controller: _draft,
      title: strings.feature('Kasta ändringar?'),
      message: strings.feature('Dina osparade ändringar går förlorade.'),
      discardLabel: strings.feature('Kasta'),
      cancelLabel: strings.feature('Fortsätt redigera'),
      child: fullScreen
          ? Dialog.fullscreen(child: SafeArea(child: body))
          : Dialog(
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 600,
                  maxHeight: MediaQuery.sizeOf(context).height * .9,
                ),
                child: body,
              ),
            ),
    );
  }

  Widget _imageFallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups_outlined, size: 48),
          const SizedBox(height: 6),
          Text(
            AppStrings.of(context).feature('Tryck för att välja lagbild'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Future<void> _pickImage() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = pick?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    final strings = AppStrings.of(context);
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      setState(() => _error = strings.feature('Bilden måste vara högst 5 MB.'));
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    final mimeType = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    setState(() {
      _imageBytes = bytes;
      _imageMimeType = mimeType;
      _imageName = file.name;
      _removeImage = false;
      _error = null;
      _draft.markDirty();
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        teamType: _teamType.text.trim(),
        ageClass: _ageClass.text.trim(),
        summary: _summary.text.trim(),
        imageBytes: _imageBytes,
        imageMimeType: _imageMimeType,
        removeImage: _removeImage,
      );
      final sport = _sport;
      if (sport != null &&
          sport != widget.initialSport &&
          widget.onSportSave != null) {
        await widget.onSportSave!(sport);
      }
      _draft.markClean();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AppStrings.of(
            context,
          ).feature('Lagprofilen kunde inte sparas. Försök igen.');
        });
      }
    }
  }
}

class _TeamImage extends StatelessWidget {
  const _TeamImage({required this.value});
  final TeamOverview value;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Icon(
          Icons.groups_outlined,
          size: 72,
          semanticLabel: AppStrings.of(context).feature('Ingen lagbild'),
        ),
      ),
    );
    return AspectRatio(
      aspectRatio: 16 / 7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: value.imageUrl == null
            ? fallback
            : Image.network(
                value.imageUrl!,
                fit: BoxFit.cover,
                semanticLabel: AppStrings.of(context)
                    .feature('Lagbild för {team}')
                    .replaceFirst('{team}', value.teamName),
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

enum _TeamEventFilter { all, match, training, meeting }

enum _TeamEventPeriod { upcoming, previous }

class _TeamEventList extends StatefulWidget {
  const _TeamEventList({required this.contextValue, required this.calendar});
  final TeamZoneContext contextValue;
  final CalendarServices calendar;
  @override
  State<_TeamEventList> createState() => _TeamEventListState();
}

class _TeamEventListState extends State<_TeamEventList> {
  late Future<List<CalendarEventSummary>> _load;
  _TeamEventFilter _filter = _TeamEventFilter.all;
  _TeamEventPeriod _period = _TeamEventPeriod.upcoming;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final now = DateTime.now();
    _load = widget.calendar
        .listCalendar(
          contextIds: [widget.contextValue.id],
          from: DateTime(now.year - 1),
          to: DateTime(now.year + 2),
        )
        .timeout(const Duration(seconds: 15));
  }

  @override
  void didUpdateWidget(covariant _TeamEventList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) {
      setState(_reload);
    }
  }

  bool _matches(CalendarEventSummary event) => switch (_filter) {
    _TeamEventFilter.all => true,
    _TeamEventFilter.match => event.type == 'match',
    _TeamEventFilter.training => event.type == 'training',
    _TeamEventFilter.meeting => event.type == 'meeting',
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<List<CalendarEventSummary>>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(
            label: strings.feature('Laddar lagets kalender'),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _StateCard(
            icon: Icons.sync_problem,
            title: strings.feature('Lagets kalender kunde inte laddas'),
            message: strings.feature('Försök igen om en stund.'),
            action: FilledButton(
              onPressed: () => setState(_reload),
              child: Text(strings.feature('Försök igen')),
            ),
          );
        }
        final teamId = widget.contextValue.teamId;
        final events = snapshot.data!
            .where((event) => teamId == null || event.owningTeamId == teamId)
            .where(_matches)
            .toList();
        final now = DateTime.now();
        final upcoming =
            events.where((event) => !event.startsAt.isBefore(now)).toList()
              ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        final previous =
            events.where((event) => event.startsAt.isBefore(now)).toList()
              ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
        final visibleEvents = _period == _TeamEventPeriod.upcoming
            ? upcoming
            : previous;
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _load;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<_TeamEventPeriod>(
                      segments: [
                        ButtonSegment(
                          value: _TeamEventPeriod.upcoming,
                          label: Text(strings.feature('Kommande')),
                          icon: const Icon(Icons.upcoming_outlined),
                        ),
                        ButtonSegment(
                          value: _TeamEventPeriod.previous,
                          label: Text(strings.feature('Tidigare')),
                          icon: const Icon(Icons.history),
                        ),
                      ],
                      selected: {_period},
                      onSelectionChanged: (selection) =>
                          setState(() => _period = selection.single),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<_TeamEventFilter>(
                    tooltip: strings.feature('Filtrera händelser'),
                    initialValue: _filter,
                    onSelected: (value) => setState(() => _filter = value),
                    icon: Badge(
                      isLabelVisible: _filter != _TeamEventFilter.all,
                      child: const Icon(Icons.filter_list),
                    ),
                    itemBuilder: (context) => [
                      for (final item in _TeamEventFilter.values)
                        PopupMenuItem(
                          value: item,
                          child: Row(
                            children: [
                              Icon(
                                _filter == item
                                    ? Icons.check
                                    : Icons.circle_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(_teamEventFilterLabel(strings, item)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (_filter != _TeamEventFilter.all) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(_teamEventFilterLabel(strings, _filter)),
                    onDeleted: () =>
                        setState(() => _filter = _TeamEventFilter.all),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _TeamEventSection(
                title: strings.feature(
                  _period == _TeamEventPeriod.upcoming
                      ? 'Kommande händelser'
                      : 'Tidigare händelser',
                ),
                events: visibleEvents,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _teamEventFilterLabel(AppStrings strings, _TeamEventFilter filter) =>
    switch (filter) {
      _TeamEventFilter.all => strings.feature('Alla händelser'),
      _TeamEventFilter.match => strings.feature('Matcher'),
      _TeamEventFilter.training => strings.feature('Träningar'),
      _TeamEventFilter.meeting => strings.feature('Möten'),
    };

class _TeamEventSection extends StatelessWidget {
  const _TeamEventSection({required this.title, required this.events});
  final String title;
  final List<CalendarEventSummary> events;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (events.isEmpty)
        Text(AppStrings.of(context).feature('Inga händelser'))
      else
        for (final event in events) _TeamEventCard(event: event),
    ],
  );
}

class _TeamEventCard extends StatelessWidget {
  const _TeamEventCard({required this.event});

  final CalendarEventSummary event;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final localizations = MaterialLocalizations.of(context);
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    final date = localizations.formatFullDate(start);
    final time = event.allDay
        ? strings.feature('Heldag')
        : '${TimeOfDay.fromDateTime(start).format(context)}–'
              '${TimeOfDay.fromDateTime(end).format(context)}';
    final hasResult =
        event.type == 'match' &&
        event.matchState == 'completed' &&
        event.scoreUs != null &&
        event.scoreOpponent != null;
    final cancelled = event.state == 'cancelled';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => GoRouter.of(
          context,
        ).push(ProductRouteContract.calendarEvent(event.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                child: Icon(
                  event.type == 'match'
                      ? Icons.sports_soccer
                      : event.type == 'training'
                      ? Icons.fitness_center
                      : Icons.event_outlined,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          strings.domainValue(event.type),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        if (cancelled)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(strings.domainValue(event.state)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('$date · $time'),
                    if (event.locationName case final location?) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 18),
                          const SizedBox(width: 4),
                          Expanded(child: Text(location)),
                        ],
                      ),
                    ],
                    if (hasResult) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${strings.feature('Resultat')}  '
                        '${event.scoreUs}–${event.scoreOpponent}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClubVerificationSheet extends StatefulWidget {
  const _ClubVerificationSheet({
    required this.clubId,
    required this.membership,
  });

  final String clubId;
  final MembershipServices membership;

  @override
  State<_ClubVerificationSheet> createState() => _ClubVerificationSheetState();
}

class _ClubVerificationSheetState extends State<_ClubVerificationSheet> {
  final _evidence = TextEditingController();
  late Future<ClubVerificationStatus> _load;
  bool _pending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _load = widget.membership
        .getClubVerificationStatus(clubId: widget.clubId)
        .timeout(const Duration(seconds: 15));
  }

  Future<void> _request() async {
    final evidence = _evidence.text.trim();
    if (_pending || evidence.length < 20 || evidence.length > 1000) {
      setState(
        () => _error = AppStrings.of(
          context,
        ).feature('Beskriv kopplingen till klubben med 20–1000 tecken.'),
      );
      return;
    }
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.membership
          .requestClubVerification(
            clubId: widget.clubId,
            evidenceSummary: evidence,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _reload();
          _pending = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pending = false;
          _error = AppStrings.of(
            context,
          ).feature('Underlaget kunde inte skickas. Försök igen.');
        });
      }
    }
  }

  @override
  void dispose() {
    _evidence.dispose();
    super.dispose();
  }

  (IconData, String, String) _presentation(
    ClubVerificationStatus value,
    AppStrings strings,
  ) => switch (value.status) {
    'official' => (
      Icons.verified,
      strings.feature('Officiell klubb'),
      strings.feature('Klubben är granskad och godkänd av TeamZone.'),
    ),
    'pending' => (
      Icons.hourglass_top,
      strings.feature('Granskning pågår'),
      strings.feature('TeamZone har tagit emot klubbens underlag.'),
    ),
    'rejected' => (
      Icons.info_outline,
      strings.feature('Verifiering avslagen'),
      strings.feature('Klubben är fortsatt inofficiell.'),
    ),
    'revoked' => (
      Icons.gpp_bad_outlined,
      strings.feature('Officiell status återkallad'),
      strings.feature('Kontakta TeamZone om klubben ska granskas igen.'),
    ),
    _ => (
      Icons.shield_outlined,
      strings.feature('Inofficiell klubb'),
      strings.feature('Klubben är ännu inte verifierad av TeamZone.'),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: FutureBuilder<ClubVerificationStatus>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AppLoadingIndicator(
              label: strings.feature('Laddar klubbstatus'),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _StateCard(
              icon: Icons.sync_problem,
              title: strings.feature('Klubbstatus kunde inte laddas'),
              message: strings.feature('Försök igen om en stund.'),
              action: FilledButton(
                onPressed: () => setState(_reload),
                child: Text(strings.feature('Försök igen')),
              ),
            );
          }
          final value = snapshot.data!;
          final presentation = _presentation(value, strings);
          final canRequest = const {
            'unofficial',
            'rejected',
            'revoked',
          }.contains(value.status);
          return ListView(
            children: [
              Text(
                strings.feature('Klubbverifiering'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Semantics(
                label: '${presentation.$2}. ${presentation.$3}',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(presentation.$1),
                  title: Text(presentation.$2),
                  subtitle: Text(presentation.$3),
                ),
              ),
              if (canRequest) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _evidence,
                  enabled: !_pending,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: strings.feature('Underlag för granskning'),
                    helperText: strings.feature(
                      'Beskriv din roll och hur TeamZone kan verifiera kopplingen till klubben.',
                    ),
                  ),
                ),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _pending ? null : _request,
                  icon: _pending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(strings.feature('Skicka för granskning')),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MembershipReviewSheet extends StatefulWidget {
  const _MembershipReviewSheet({
    required this.contextValue,
    required this.membership,
    required this.onApproved,
  });

  final TeamZoneContext contextValue;
  final MembershipServices membership;
  final Future<void> Function() onApproved;

  @override
  State<_MembershipReviewSheet> createState() => _MembershipReviewSheetState();
}

class _MembershipReviewSheetState extends State<_MembershipReviewSheet> {
  late Future<List<MembershipReviewItem>> _load;
  String? _pendingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _load = widget.membership
        .listPendingReviews(
          clubId: widget.contextValue.clubId,
          teamId: widget.contextValue.teamId,
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<void> _decide(MembershipReviewItem item, bool approve) async {
    if (_pendingId != null) return;
    final strings = AppStrings.of(context);
    var approvedRole = item.role;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            strings.feature(
              approve ? 'Godkänn medlemsansökan?' : 'Avslå medlemsansökan?',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.feature(
                  approve
                      ? 'Personen får den valda rollen i laget.'
                      : 'Sökanden ser endast att ansökan har avslagits.',
                ),
              ),
              if (approve) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<MembershipRole>(
                  initialValue: approvedRole,
                  decoration: InputDecoration(
                    labelText: strings.feature('Godkänn som'),
                    helperText: strings
                        .feature('Ansökt som: {role}')
                        .replaceFirst('{role}', _roleLabel(strings, item.role)),
                  ),
                  items: MembershipRole.values
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(_roleLabel(strings, role)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (role) {
                    if (role != null) {
                      setDialogState(() => approvedRole = role);
                    }
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.feature(approve ? 'Godkänn' : 'Avslå')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _pendingId = item.id;
      _error = null;
    });
    try {
      await widget.membership
          .decide(
            applicationId: item.id,
            approve: approve,
            approvedRole: approve ? approvedRole : null,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
      if (approve) await widget.onApproved();
      if (mounted) setState(_reload);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = strings.feature(
            'Beslutet kunde inte sparas. Ladda om och försök igen.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingId = null);
    }
  }

  String _roleLabel(AppStrings strings, MembershipRole role) => switch (role) {
    MembershipRole.player => strings.feature('Spelare'),
    MembershipRole.leader => strings.feature('Ledare'),
    MembershipRole.guardian => strings.feature('Vårdnadshavare'),
    MembershipRole.clubFunctionary => strings.feature('Klubbfunktionär'),
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: FutureBuilder<List<MembershipReviewItem>>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AppLoadingIndicator(
              label: strings.feature('Hämtar medlemsansökningar'),
            );
          }
          if (snapshot.hasError) {
            return _StateCard(
              icon: Icons.sync_problem,
              title: strings.feature('Ansökningarna kunde inte hämtas'),
              message: strings.feature(
                'Försök igen. Inga råa backendfel visas.',
              ),
              action: FilledButton(
                onPressed: () => setState(_reload),
                child: Text(strings.feature('Försök igen')),
              ),
            );
          }
          final items = snapshot.requireData;
          return ListView(
            children: [
              Text(
                strings.feature('Medlemsansökningar'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(_error!)),
              ],
              if (items.isEmpty)
                ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: Text(
                    strings.feature('Inga väntande medlemsansökningar'),
                  ),
                )
              else
                ...items.map(
                  (item) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(item.applicantDisplayName),
                      subtitle: Text(
                        '${item.teamName} · ${_roleLabel(strings, item.role)}',
                      ),
                      isThreeLine: false,
                      trailing: _pendingId == item.id
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(),
                            )
                          : Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: strings.feature('Avslå'),
                                  onPressed: () => _decide(item, false),
                                  icon: const Icon(Icons.close),
                                ),
                                IconButton(
                                  tooltip: strings.feature('Godkänn'),
                                  onPressed: () => _decide(item, true),
                                  icon: const Icon(Icons.check),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A squad member's profile picture, or their initials without one.
class _RosterAvatar extends StatelessWidget {
  const _RosterAvatar({
    required this.avatars,
    required this.personId,
    required this.name,
  });
  final Future<Map<String, String>> avatars;
  final String personId, name;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>>(
    future: avatars,
    builder: (context, snapshot) {
      final url = snapshot.data?[personId];
      return CircleAvatar(
        key: ValueKey('roster-avatar-$personId'),
        foregroundImage: url == null ? null : NetworkImage(url),
        onForegroundImageError: url == null ? null : (_, _) {},
        child: Text(_initialsOf(name)),
      );
    },
  );
}
