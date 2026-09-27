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
  });

  final TeamZoneContext contextValue;
  final RosterServices roster;
  final MembershipServices membership;
  final CalendarServices calendar;
  final Future<void> Function(String teamId) onTeamCreated;
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
        final people = _list.visibleItems;
        final rosterList = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
              child: people.isEmpty
                  ? _StateCard(
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
                    )
                  : RefreshIndicator(
                      onRefresh: _data.refresh,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount:
                            people.length +
                            (state.isStale ? 1 : 0) +
                            (_list.hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          if (state.isStale && index == 0) {
                            return ListTile(
                              leading: const Icon(Icons.cloud_off),
                              title: Text(strings.offlineData),
                              subtitle: state.lastUpdated == null
                                  ? null
                                  : Text(
                                      strings.lastUpdated(state.lastUpdated!),
                                    ),
                            );
                          }
                          final dataIndex = index - (state.isStale ? 1 : 0);
                          if (dataIndex == people.length) {
                            return TextButton.icon(
                              onPressed: _list.loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: Text(strings.feature('Visa fler')),
                            );
                          }
                          final person = people[dataIndex];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(person.displayName),
                            subtitle: Text(
                              [
                                person.ageClass,
                                person.teamName,
                              ].whereType<String>().join(' · '),
                            ),
                            trailing: canManage
                                ? IconButton(
                                    tooltip: strings.feature('Redigera person'),
                                    onPressed: () =>
                                        _openRosterPersonForm(person: person),
                                    icon: const Icon(Icons.edit_outlined),
                                  )
                                : canOpenPersonDetails
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: canOpenPersonDetails
                                ? () => _openPersonDetails(person)
                                : null,
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
        return Scaffold(
          floatingActionButtonLocation: _assistantUsesFab(context)
              ? _aboveAssistantFabLocation
              : null,
          body: state.phase == AsyncDataPhase.empty
              ? _StateCard(
                  icon: Icons.groups_outlined,
                  title: AppStrings.of(context).feature('Ingen i truppen ännu'),
                  message: AppStrings.of(
                    context,
                  ).feature('Rosterposter visas här när de har skapats.'),
                  // A brand-new team's empty roster used to have no action
                  // here at all, unlike every other empty/blocked state on
                  // this screen. Found via a physical walkthrough of a
                  // freshly created team. Points at Inställningar, not
                  // straight at the code dialog: "Använd kod" was removed
                  // from the Trupp tab entirely and consolidated into the
                  // profile settings page (see profile_settings_surface.dart).
                  action: OutlinedButton.icon(
                    onPressed: () =>
                        GoRouter.of(context).go(ProductRouteContract.settings),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(
                      AppStrings.of(context).feature('Inställningar'),
                    ),
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

  void _openRosterPersonForm({RosterPersonSummary? person}) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            child: _RosterPersonEditor(
              contextValue: widget.contextValue,
              roster: widget.roster,
              person: person,
              onSaved: () async {
                await _data.refresh();
              },
            ),
          ),
        ),
      ),
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

  void _openPersonDetails(RosterPersonSummary person) {
    GoRouter.of(context).push(ProductRouteContract.teamMember(person.id));
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

class _RosterPersonEditor extends StatelessWidget {
  const _RosterPersonEditor({
    required this.contextValue,
    required this.roster,
    required this.onSaved,
    this.person,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final RosterPersonSummary? person;
  final Future<void> Function() onSaved;

  @override
  Widget build(BuildContext context) {
    final teamId = contextValue.teamId;
    if (teamId == null) return const SizedBox.shrink();
    if (person == null) {
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
            personId: person!.id,
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
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final RosterPersonDetails? initial;
  final Future<void> Function() onSaved;

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
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(_submission.markDirty);
  }

  @override
  void dispose() {
    _name.removeListener(_submission.markDirty);
    _name.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      final saved = await _submission.run(() async {
        final teamId = widget.contextValue.teamId!;
        if (_isEditing) {
          var revision = await widget.roster.updatePerson(
            clubId: widget.contextValue.clubId,
            teamId: teamId,
            personId: widget.initial!.id,
            displayName: _name.text.trim(),
            birthYear: _birthYear!,
            birthDate: _birthDate,
            expectedRevision: widget.initial!.personRevision!,
            idempotencyKey: _newUuid(),
          );
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
          await widget.roster.createPerson(
            clubId: widget.contextValue.clubId,
            teamId: teamId,
            displayName: _name.text.trim(),
            birthYear: _birthYear!,
            birthDate: _birthDate,
            startsAt: DateTime.now().toUtc(),
            idempotencyKey: _newUuid(),
          );
        }
        await widget.onSaved();
      });
      if (saved && mounted) Navigator.pop(context);
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
                  if (_isEditing)
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

class _RosterPersonDetailsView extends StatelessWidget {
  const _RosterPersonDetailsView({
    required this.future,
    this.onMovePlayer,
    this.onArchivePlayer,
    this.onInvitePlayer,
    this.onSetRepresentation,
  });
  final Future<RosterPersonDetails> future;
  final VoidCallback? onMovePlayer;
  final Future<void> Function()? onArchivePlayer;
  final void Function(RosterPersonDetails person)? onInvitePlayer;
  final void Function(RosterPersonDetails person)? onSetRepresentation;

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
          CircleAvatar(
            radius: 34,
            child: Text(person.displayName.characters.first.toUpperCase()),
          ),
          const SizedBox(height: 12),
          Text(
            person.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
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
          if ((onMovePlayer != null ||
                  onArchivePlayer != null ||
                  onInvitePlayer != null ||
                  onSetRepresentation != null) &&
              person.assignmentState == 'active') ...[
            const Divider(),
            Text(
              strings.feature('Åtgärder'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (onInvitePlayer != null && person.accountLinked != true)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(strings.feature('Bjud in')),
                subtitle: Text(
                  strings.feature(
                    'Skicka en inbjudan så personen kan koppla ett konto.',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onInvitePlayer!(person),
              ),
            if (onSetRepresentation != null)
              ListTile(
                leading: const Icon(Icons.compare_arrows),
                title: Text(strings.feature('Representation i annat lag')),
                subtitle: Text(
                  strings.feature(
                    'Föreslå personen för ett annat lag i klubben.',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onSetRepresentation!(person),
              ),
            if (onMovePlayer != null)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(strings.feature('Flytta till ett annat lag')),
                subtitle: Text(
                  strings.feature(
                    'Nuvarande lagtillhörighet avslutas och historiken bevaras.',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onMovePlayer,
              ),
            if (onArchivePlayer != null)
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(strings.feature('Avsluta i laget')),
                subtitle: Text(
                  strings.feature(
                    'Spelaren flyttas till Arkiverade. Namn, matcher, närvaro och annan historik bevaras.',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onArchivePlayer!(),
              ),
          ],
          if (person.hasManagementDetails) ...[
            const Divider(),
            Text(
              strings.feature('Administrativa uppgifter'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ListTile(
              title: Text(strings.feature('Ursprung')),
              subtitle: Text(person.provenance!),
            ),
            if (person.assignmentStartsAt != null)
              ListTile(
                title: Text(strings.feature('Startdatum')),
                subtitle: Text(
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(person.assignmentStartsAt!.toLocal()),
                ),
              ),
            if (person.assignmentEndsAt != null)
              ListTile(
                title: Text(strings.feature('Slutdatum')),
                subtitle: Text(
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(person.assignmentEndsAt!.toLocal()),
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _RosterPersonDetailsPage extends StatelessWidget {
  const _RosterPersonDetailsPage({
    required this.personId,
    required this.contextValue,
    required this.roster,
    required this.onBack,
  });

  final String personId;
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
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
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(strings.feature('Medlemsuppgifter')),
      ),
      body: allowed
          ? _RosterPersonDetailsView(
              future: roster
                  .getPersonDetails(
                    clubId: contextValue.clubId,
                    teamId: contextValue.teamId!,
                    personId: personId,
                  )
                  .timeout(const Duration(seconds: 15)),
              onMovePlayer: canManage
                  ? () => showModalBottomSheet<void>(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => _IntraClubMoveSheet(
                        contextValue: contextValue,
                        roster: roster,
                        initialPersonId: personId,
                      ),
                    )
                  : null,
              onArchivePlayer: canManage
                  ? () => _archivePersonFromDetails(
                      context: context,
                      contextValue: contextValue,
                      roster: roster,
                      personId: personId,
                      onArchived: onBack,
                    )
                  : null,
              onInvitePlayer: canManage
                  ? (person) => _inviteFromProfile(
                      context: context,
                      contextValue: contextValue,
                      roster: roster,
                      person: person,
                    )
                  : null,
              onSetRepresentation: canManage
                  ? (person) => _representFromProfile(
                      context: context,
                      contextValue: contextValue,
                      roster: roster,
                      person: person,
                    )
                  : null,
            )
          : _StateCard(
              icon: Icons.lock_outline,
              title: strings.feature('Medlemsdetaljen är inte tillgänglig'),
              message: strings.feature(
                'Din roll saknar behörighet att visa de här uppgifterna.',
              ),
              action: OutlinedButton(
                onPressed: onBack,
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
    required this.onNavigate,
    required this.onOpenApplications,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onOpenApplications;

  @override
  State<_TeamOverviewSurface> createState() => _TeamOverviewSurfaceState();
}

class _TeamOverviewSurfaceState extends State<_TeamOverviewSurface> {
  late Future<TeamOverview> _load;

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
  }

  @override
  void didUpdateWidget(covariant _TeamOverviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) setState(_reload);
  }

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
            const SizedBox(height: 16),
            Text(
              value.summary ??
                  strings.feature('Ingen laginformation har publicerats ännu.'),
            ),
            const SizedBox(height: 20),
            Text(
              strings.feature('Ledare'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              value.leaders.isEmpty
                  ? strings.feature('Inga ledare visas ännu.')
                  : value.leaders
                        .map((leader) => leader.displayName)
                        .join(', '),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.groups_outlined),
                  label: Text(strings.feature('Öppna trupp')),
                  onPressed: () => widget.onNavigate('/team?tab=roster'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.event_outlined),
                  label: Text(strings.feature('Öppna lagkalender')),
                  onPressed: () => widget.onNavigate('/team?tab=calendar'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.inbox_outlined),
                  label: Text(strings.feature('Öppna Inbox')),
                  onPressed: () => widget.onNavigate('/inbox'),
                ),
              ],
            ),
            if (showAdmin) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _editTeamProfile,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(strings.feature('Redigera lagprofil')),
                ),
              ),
            ],
            if (showAdmin) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        strings.feature('Kräver åtgärd'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.mark_email_unread_outlined),
                        title: Text(strings.feature('Aktiva inbjudningar')),
                        trailing: Text('${value.activeInvitationCount}'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.how_to_reg_outlined),
                        title: Text(strings.feature('Väntande ansökningar')),
                        trailing: Text('${value.pendingApplicationCount}'),
                        onTap: value.pendingApplicationCount == 0
                            ? null
                            : () async {
                                await widget.onOpenApplications();
                                if (mounted) setState(_reload);
                              },
                      ),
                      Semantics(
                        label: strings
                            .feature('Totalt {count} ärenden kräver åtgärd.')
                            .replaceFirst('{count}', '${value.actionCount}'),
                        child: Text(
                          strings
                              .feature('{count} ärenden totalt')
                              .replaceFirst('{count}', '${value.actionCount}'),
                        ),
                      ),
                    ],
                  ),
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
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _TeamProfileEditDialog(
          value: value,
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

class _TeamProfileEditDialog extends StatefulWidget {
  const _TeamProfileEditDialog({required this.value, required this.onSave});
  final TeamProfileEditData value;
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
  final _formKey = GlobalKey<FormState>();
  Uint8List? _imageBytes;
  String? _imageMimeType;
  String? _imageName;
  bool _removeImage = false;
  bool _saving = false;

  @override
  void dispose() {
    _teamType.dispose();
    _ageClass.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.feature('Redigera lagprofil')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _teamType,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: strings.feature('Lagtyp'),
                ),
              ),
              TextFormField(
                controller: _ageClass,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: strings.feature('Åldersklass'),
                ),
              ),
              TextFormField(
                controller: _summary,
                maxLength: 1000,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: strings.feature('Kort lagpresentation'),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  strings.feature('Lagbild'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 16 / 7,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _imageBytes != null
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
                      : _imageFallback(context),
                ),
              ),
              if (_imageName != null) ...[
                const SizedBox(height: 8),
                Text(_imageName!, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  if ((_imageBytes != null || widget.value.imageUrl != null) &&
                      !_removeImage)
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _imageBytes = null;
                              _imageMimeType = null;
                              _imageName = null;
                              _removeImage = true;
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
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(strings.save),
        ),
      ],
    );
  }

  Widget _imageFallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.groups_outlined, size: 56)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.feature('Bilden måste vara högst 5 MB.')),
        ),
      );
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
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        teamType: _teamType.text.trim(),
        ageClass: _ageClass.text.trim(),
        summary: _summary.text.trim(),
        imageBytes: _imageBytes,
        imageMimeType: _imageMimeType,
        removeImage: _removeImage,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Lagprofilen kunde inte sparas.'),
            ),
          ),
        );
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
