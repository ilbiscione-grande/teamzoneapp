part of '../../app/teamzone_app.dart';

class _RosterSurface extends StatefulWidget {
  const _RosterSurface({
    required this.contextValue,
    required this.roster,
    required this.membership,
    required this.calendar,
    this.onContextsChanged,
    this.initialTab,
  });

  final TeamZoneContext contextValue;
  final RosterServices roster;
  final MembershipServices membership;
  final CalendarServices calendar;
  final Future<void> Function()? onContextsChanged;
  final String? initialTab;

  @override
  State<_RosterSurface> createState() => _RosterSurfaceState();
}

class _RosterSurfaceState extends State<_RosterSurface> {
  late final AsyncDataController<List<RosterPersonSummary>> _data;
  late final AppListController<RosterPersonSummary> _list;
  List<RosterPersonSummary>? _syncedPeople;
  late int _selectedTab = _teamTabIndex(widget.initialTab);
  String? _selectedPersonId;
  Future<RosterPersonDetails>? _selectedPersonDetails;

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
  }

  void _syncList() {
    final people = _data.state.data;
    if (identical(people, _syncedPeople)) return;
    _syncedPeople = people;
    _list.replaceItems(people ?? const []);
  }

  Future<List<RosterPersonSummary>> _reload() {
    if (widget.contextValue.teamId == null) return Future.value(const []);
    return widget.roster.listPeople(
      clubId: widget.contextValue.clubId,
      teamId: widget.contextValue.teamId,
    );
  }

  Future<void> _acceptGuardianInvite() async {
    final controller = TextEditingController();
    var useTeamCode = false;
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            AppStrings.of(context).feature('Använd inbjudan eller lagkod'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<bool>(
                initialValue: useTeamCode,
                items: [
                  DropdownMenuItem(
                    value: false,
                    child: Text(
                      AppStrings.of(context).feature('Guardianinbjudan'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text(AppStrings.of(context).feature('Lagkod')),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => useTeamCode = value ?? false),
              ),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: AppStrings.of(
                    context,
                  ).feature('Säker inbjudningskod'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(AppStrings.of(context).feature('Acceptera')),
            ),
          ],
        ),
      ),
    );
    if (token == null || token.isEmpty || !mounted) return;
    try {
      if (useTeamCode) {
        await widget.roster.claimTeamCode(
          token: token,
          idempotencyKey: _newUuid(),
        );
      } else {
        await widget.roster.acceptGuardianInvite(
          token: token,
          idempotencyKey: _newUuid(),
        );
      }
      if (mounted) {
        await widget.onContextsChanged?.call();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                useTeamCode
                    ? 'Medlemsansökan har skapats.'
                    : 'Guardianrelationen är aktiverad.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Inbjudan eller lagkoden är ogiltig eller har gått ut.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _createTeam() async {
    final strings = AppStrings.of(context);
    final controller = TextEditingController();
    final teamName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.feature('Skapa ytterligare lag')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: strings.feature('Lagnamn')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty && value.length <= 120) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: Text(strings.feature('Skapa lag')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (teamName == null || !mounted) return;
    try {
      await widget.membership
          .createTeam(
            clubId: widget.contextValue.clubId,
            teamName: teamName,
            idempotencyKey: _newUuid(),
          )
          .timeout(const Duration(seconds: 15));
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
      _selectedPersonId = null;
      _selectedPersonDetails = null;
      _data.replaceScope(scopeKey: widget.contextValue.id, loader: _reload);
    }
    if (oldWidget.initialTab != widget.initialTab) {
      _selectedTab = _teamTabIndex(widget.initialTab);
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
      return _NoTeamMembershipSurface(onUseCode: _acceptGuardianInvite);
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
    GoRouter.of(context).go('/team?tab=${names[index]}');
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
          onPressed: _acceptGuardianInvite,
          icon: const Icon(Icons.vpn_key_outlined),
          label: Text(AppStrings.of(context).feature('Använd kod')),
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
              child: Row(
                children: [
                  Expanded(
                    child: SearchBar(
                      leading: const Icon(Icons.search),
                      hintText: strings.feature('Sök i truppen'),
                      onChanged: _list.setQuery,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _acceptGuardianInvite,
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: Text(strings.feature('Använd kod')),
                  ),
                ],
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
                        child: Text(strings.feature('Rensa sökning')),
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
                            selected: person.id == _selectedPersonId,
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
          body: state.phase == AsyncDataPhase.empty
              ? _StateCard(
                  icon: Icons.groups_outlined,
                  title: AppStrings.of(context).feature('Ingen i truppen ännu'),
                  message: AppStrings.of(
                    context,
                  ).feature('Rosterposter visas här när de har skapats.'),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 840) return rosterList;
                    return Row(
                      children: [
                        Expanded(flex: 3, child: rosterList),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 2,
                          child: _selectedPersonDetails == null
                              ? _StateCard(
                                  icon: Icons.person_search_outlined,
                                  title: strings.feature('Välj en person'),
                                  message: strings.feature(
                                    'Medlemsdetaljer visas här utan att lämna truppen.',
                                  ),
                                )
                              : _RosterPersonDetailsView(
                                  future: _selectedPersonDetails!,
                                ),
                        ),
                      ],
                    );
                  },
                ),
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  // A single FAB here, not a stack: this screen used to show
                  // "Medlemsansökningar" and "Hantera" as two separate
                  // stacked FloatingActionButtons, which overlapped and
                  // clipped the persistent Min assistent FAB (fixed
                  // `bottom: 88` in product_shell.dart) and, on shorter
                  // rosters, the roster list's own row actions underneath.
                  // "Medlemsansökningar" is now a menu entry below instead
                  // of a second floating button.
                  heroTag: 'manage-roster',
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
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
                                  'Avsluta lagtillhörighet eller starta en skyddad raderingsbegäran.',
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                showModalBottomSheet<void>(
                                  context: context,
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
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(AppStrings.of(context).feature('Hantera')),
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
                if (mounted) {
                  setState(() {
                    _selectedPersonId = null;
                    _selectedPersonDetails = null;
                  });
                }
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

  Future<RosterPersonDetails> _loadPersonDetails(String personId) {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) return Future.error(StateError('Team required.'));
    return widget.roster
        .getPersonDetails(
          clubId: widget.contextValue.clubId,
          teamId: teamId,
          personId: personId,
        )
        .timeout(const Duration(seconds: 15));
  }

  void _openPersonDetails(RosterPersonSummary person) {
    final future = _loadPersonDetails(person.id);
    if (MediaQuery.sizeOf(context).width >= 840) {
      setState(() {
        _selectedPersonId = person.id;
        _selectedPersonDetails = future;
      });
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: _RosterPersonDetailsView(future: future),
      ),
    );
  }
}

class _NoTeamMembershipSurface extends StatelessWidget {
  const _NoTeamMembershipSurface({required this.onUseCode});

  final VoidCallback onUseCode;

  @override
  Widget build(BuildContext context) => _StateCard(
    icon: Icons.groups_outlined,
    title: AppStrings.of(context).feature('Du är inte kopplad till något lag'),
    message: AppStrings.of(context).feature(
      'När du blir tillagd i ett lag visas lagets översikt, trupp och kalender här.',
    ),
    action: FilledButton.icon(
      onPressed: onUseCode,
      icon: const Icon(Icons.vpn_key_outlined),
      label: Text(AppStrings.of(context).feature('Använd kod')),
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
  Future<RosterLifecycleOptions> _reload() => widget.roster
      .getRosterLifecycle(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));
  void _refresh() => setState(() => _load = _reload());

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

  Future<void> _archive(RosterLifecyclePerson person) async {
    final reason = await _reason(
      'Arkivera från laget',
      'Personen flyttas till Tidigare. Historiska fakta bevaras.',
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Åtgärden kunde inte sparas. Ladda om och försök igen.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _requestErasure(RosterLifecyclePerson person) async {
    final reason = await _reason(
      'Begär radering av klubbuppgifter',
      'En annan klubbansvarig måste godkänna. Namn och lokala personuppgifter anonymiseras, men verksamhetshistorik bevaras.',
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Raderingsbegäran kunde inte skapas.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _approve(ClubErasureRequest request) async {
    final reason = await _reason(
      'Godkänn anonymisering',
      'Du måste vara en annan klubbansvarig än den som startade begäran. Åtgärden kan inte ångras i appen.',
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Godkännandet nekades. Kontrollera behörighet och att initiatorn är en annan användare.',
              ),
            ),
          ),
        );
      }
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
                'Arkivering döljer inte historik. Personuppgiftsradering kräver två separata ansvariga. Global radering granskas alltid av TeamZone.',
              ),
            ),
            const Divider(),
            Text(
              AppStrings.of(context).feature('Personer'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final person in data.people)
              ListTile(
                title: Text(person.personName),
                subtitle: Text(
                  AppStrings.of(context).domainValue(person.assignmentState),
                ),
                trailing: person.canArchive
                    ? PopupMenuButton<String>(
                        enabled: !_pending,
                        onSelected: (value) {
                          if (value == 'archive') _archive(person);
                          if (value == 'erase') _requestErasure(person);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'archive',
                            child: Text(
                              AppStrings.of(
                                context,
                              ).feature('Arkivera från laget'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'erase',
                            child: Text(
                              AppStrings.of(
                                context,
                              ).feature('Begär radering av klubbuppgifter'),
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            const Divider(),
            Text(
              AppStrings.of(context).feature('Raderingsbegäranden'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (data.requests.isEmpty)
              Text(
                AppStrings.of(
                  context,
                ).feature('Inga pågående raderingsbegäranden.'),
              ),
            for (final request in data.requests)
              ListTile(
                title: Text(request.personName),
                subtitle: Text(
                  AppStrings.of(context).domainValue(request.state),
                ),
                trailing:
                    request.canApprove &&
                        widget.contextValue.rolePackage == 'club_functionary'
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
  const _IntraClubMoveSheet({required this.contextValue, required this.roster});
  final TeamZoneContext contextValue;
  final RosterServices roster;
  @override
  State<_IntraClubMoveSheet> createState() => _IntraClubMoveSheetState();
}

class _IntraClubMoveSheetState extends State<_IntraClubMoveSheet> {
  late Future<IntraClubMoveOptions> _load = _reload();
  bool _pending = false;

  Future<IntraClubMoveOptions> _reload() => widget.roster
      .getIntraClubMoveOptions(
        clubId: widget.contextValue.clubId,
        sourceTeamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));

  Future<void> _move(IntraClubMoveOptions options) async {
    if (_pending || !options.canMove) return;
    var person = options.people.first;
    var target = options.teams.first;
    var effectiveDate = DateTime.now();
    final reason = TextEditingController(text: 'Flytt beslutad av lagansvarig');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).feature('Flytta spelare')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: person.personId,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Spelare'),
                  ),
                  items: options.people
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.personId,
                          child: Text(item.personName),
                        ),
                      )
                      .toList(),
                  onChanged: (id) => setDialogState(() {
                    person = options.people.firstWhere(
                      (item) => item.personId == id,
                      orElse: () => person,
                    );
                  }),
                ),
                DropdownButtonFormField<String>(
                  initialValue: target.id,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Nytt lag'),
                  ),
                  items: options.teams
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (id) => setDialogState(() {
                    target = options.teams.firstWhere(
                      (item) => item.id == id,
                      orElse: () => target,
                    );
                  }),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppStrings.of(context).feature('Flyttdatum')),
                  subtitle: Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(effectiveDate),
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                      initialDate: effectiveDate,
                    );
                    if (selected != null) {
                      setDialogState(() => effectiveDate = selected);
                    }
                  },
                ),
                TextField(
                  controller: reason,
                  maxLength: 240,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).feature('Anledning'),
                  ),
                ),
                Text(
                  AppStrings.of(
                    context,
                  ).feature('Det tidigare laget och all historik bevaras.'),
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
              child: Text(AppStrings.of(context).feature('Flytta')),
            ),
          ],
        ),
      ),
    );
    final moveReason = reason.text.trim();
    reason.dispose();
    if (confirmed != true || moveReason.length < 2) return;
    final now = DateTime.now();
    final effectiveAt = DateUtils.isSameDay(effectiveDate, now)
        ? now
        : DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day);
    setState(() => _pending = true);
    try {
      await widget.roster.movePlayerWithinClub(
        clubId: widget.contextValue.clubId,
        sourceTeamId: person.sourceTeamId,
        targetTeamId: target.id,
        personId: person.personId,
        assignmentId: person.assignmentId,
        effectiveAt: effectiveAt,
        expectedRevision: person.assignmentRevision,
        reason: moveReason,
        idempotencyKey: _newUuid(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Spelaren är flyttad.'),
            ),
          ),
        );
        setState(() => _load = _reload());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Flytten kunde inte sparas. Ladda om och kontrollera datum och lag.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .72,
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
        return Column(
          children: [
            ListTile(
              title: Text(AppStrings.of(context).feature('Flytta spelare')),
              subtitle: Text(
                AppStrings.of(context).feature(
                  'Flytten avslutar nuvarande lagtillhörighet och skapar en ny från valt datum.',
                ),
              ),
              trailing: FilledButton.icon(
                onPressed: _pending || !options.canMove
                    ? null
                    : () => _move(options),
                icon: const Icon(Icons.swap_horiz),
                label: Text(AppStrings.of(context).feature('Flytta')),
              ),
            ),
            Expanded(
              child: options.canMove
                  ? ListView(
                      children: options.people
                          .map(
                            (person) => ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: Text(person.personName),
                              subtitle: Text(person.sourceTeamName),
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
    final people = await widget.roster.listPeople(
      clubId: widget.contextValue.clubId,
    );
    if (!mounted || people.isEmpty) return;
    var personId = people.first.id;
    var kind = 'development';
    var validity = 'season';
    var boundary = DateTime(DateTime.now().year + 1, 6, 30);
    final source = TextEditingController(text: 'Beslut av lagansvarig');
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
                TextField(
                  controller: source,
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
    final note = source.text.trim();
    source.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                'Representationen kunde inte sparas. Kontrollera lag, period och överlapp.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

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
                        '${AppStrings.of(context).domainValue(item.kind)} · ${AppStrings.of(context).domainValue(item.validityKind)} · ${AppStrings.of(context).domainValue(item.state)}',
                      ),
                      trailing: item.canEnd
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
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final List<RosterPersonSummary> people;
  @override
  State<_InvitationAdminSheet> createState() => _InvitationAdminSheetState();
}

class _InvitationAdminSheetState extends State<_InvitationAdminSheet> {
  late Future<List<InvitationAdminItem>> _load = _reload();
  bool _pending = false;

  Future<List<InvitationAdminItem>> _reload() => widget.roster
      .listInvitationAdmin(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));

  void _refresh() => setState(() {
    _load = _reload();
  });

  Future<void> _issueTeamCode() async {
    var role = 'player';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).feature('Skapa lagkod')),
          content: DropdownButtonFormField<String>(
            initialValue: role,
            decoration: InputDecoration(
              labelText: AppStrings.of(context).feature('Ansökningsroll'),
            ),
            items: const ['player', 'leader', 'guardian', 'club_functionary']
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(AppStrings.of(context).domainValue(value)),
                  ),
                )
                .toList(),
            onChanged: (value) => setDialogState(() => role = value ?? role),
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
    if (confirmed != true) return;
    final token = '${_newUuid()}${_newUuid()}';
    await _runIssue(
      () => widget.roster.issueTeamCode(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
        requestedRole: role,
        token: token,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
        maxUses: 100,
        idempotencyKey: _newUuid(),
      ),
      token,
    );
  }

  Future<void> _issueTargeted() async {
    if (widget.people.isEmpty) return;
    var personId = widget.people.first.id;
    var address = '';
    String? emailError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).feature('Riktad inbjudan')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: personId,
                  items: widget.people
                      .map(
                        (person) => DropdownMenuItem(
                          value: person.id,
                          child: Text(person.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => personId = value ?? personId),
                ),
                TextField(
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  onChanged: (value) {
                    address = value;
                    if (emailError != null) {
                      setDialogState(() => emailError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: AppStrings.of(
                      context,
                    ).feature('Mottagarens e-post'),
                    errorText: emailError,
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
              onPressed: () {
                final normalizedAddress = address.trim();
                final valid = RegExp(
                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                ).hasMatch(normalizedAddress);
                if (!valid) {
                  setDialogState(
                    () => emailError = AppStrings.of(
                      context,
                    ).feature('Ange en giltig e-postadress.'),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(AppStrings.of(context).feature('Skapa')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    address = address.trim();
    final token = '${_newUuid()}${_newUuid()}';
    await _runIssue(
      () => widget.roster.issueTargetedInvitation(
        personId: personId,
        intendedEmail: address,
        token: token,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        idempotencyKey: _newUuid(),
      ),
      token,
    );
  }

  Future<void> _issueGuardian() async {
    final children = widget.people
        .where((person) => person.safeguardingRequired)
        .toList(growable: false);
    if (children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).feature(
              'Markera först ett barn som behöver vårdnadshavarkoppling.',
            ),
          ),
        ),
      );
      return;
    }
    var childId = children.first.id;
    final guardians = widget.people
        .where((person) => person.id != childId)
        .toList(growable: false);
    if (guardians.isEmpty) return;
    var guardianId = guardians.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).feature('Guardianinbjudan')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: guardianId,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Guardian'),
                ),
                items: guardians
                    .map(
                      (person) => DropdownMenuItem(
                        value: person.id,
                        child: Text(person.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => guardianId = value ?? guardianId),
              ),
              DropdownButtonFormField<String>(
                initialValue: childId,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Barn'),
                ),
                items: children
                    .map(
                      (person) => DropdownMenuItem(
                        value: person.id,
                        child: Text(person.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => childId = value ?? childId),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: guardianId == childId
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(AppStrings.of(context).feature('Skapa')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || guardianId == childId) return;
    final token = '${_newUuid()}${_newUuid()}';
    await _runIssue(
      () => widget.roster.issueGuardianInvitation(
        guardianPersonId: guardianId,
        childPersonId: childId,
        token: token,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
        idempotencyKey: _newUuid(),
      ),
      token,
    );
  }

  Future<void> _runIssue(Future<String> Function() action, String token) async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      await action();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppStrings.of(dialogContext).feature('Koden är skapad')),
          content: SelectableText(token),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppStrings.of(
                        dialogContext,
                      ).feature('Inbjudningskoden har kopierats.'),
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

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .88,
    child: Column(
      children: [
        ListTile(
          title: Text(
            AppStrings.of(context).feature('Inbjudningar och lagkoder'),
          ),
          subtitle: Text(
            AppStrings.of(context).feature(
              'Lagkoder kan visas och kopieras igen. Personliga koder visas bara en gång.',
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _pending ? _noop : _issueTargeted,
              child: Text(AppStrings.of(context).feature('Riktad')),
            ),
            FilledButton.tonal(
              onPressed: _pending ? _noop : _issueGuardian,
              child: Text(AppStrings.of(context).feature('Guardian')),
            ),
            FilledButton.tonal(
              onPressed: _pending ? _noop : _issueTeamCode,
              child: Text(AppStrings.of(context).feature('Lagkod')),
            ),
          ],
        ),
        const Divider(),
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
              return ListView(
                children: [
                  for (final item in snapshot.data!)
                    ListTile(
                      title: Text(item.subjectName),
                      subtitle: Text(
                        item.expiresAt == null
                            ? AppStrings.of(context).domainValue(item.state)
                            : '${AppStrings.of(context).domainValue(item.state)} · ${MaterialLocalizations.of(context).formatMediumDate(item.expiresAt!.toLocal())}',
                      ),
                      trailing: item.kind == 'team_code' && item.canRevoke
                          ? Wrap(
                              spacing: 0,
                              children: [
                                IconButton(
                                  tooltip: AppStrings.of(
                                    context,
                                  ).feature('Visa kod'),
                                  onPressed: _pending
                                      ? null
                                      : () => _showTeamCode(item),
                                  icon: const Icon(Icons.visibility_outlined),
                                ),
                                IconButton(
                                  tooltip: AppStrings.of(
                                    context,
                                  ).feature('Återkalla'),
                                  onPressed: _pending
                                      ? null
                                      : () => _revoke(item),
                                  icon: const Icon(Icons.block_outlined),
                                ),
                              ],
                            )
                          : item.canEndRelation
                          ? TextButton(
                              onPressed: _pending
                                  ? null
                                  : () => _endRelation(item),
                              child: Text(
                                AppStrings.of(context).feature('Avsluta'),
                              ),
                            )
                          : item.canRevoke
                          ? TextButton(
                              onPressed: _pending ? null : () => _revoke(item),
                              child: Text(
                                AppStrings.of(context).feature('Återkalla'),
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

void _noop() {}

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
  late final TextEditingController _ageClass = TextEditingController(
    text: widget.initial?.ageClass,
  );
  late bool _guardianRequired = widget.initial?.safeguardingRequired ?? false;
  String? _error;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(_submission.markDirty);
    _ageClass.addListener(_submission.markDirty);
  }

  @override
  void dispose() {
    _name.removeListener(_submission.markDirty);
    _ageClass.removeListener(_submission.markDirty);
    _name.dispose();
    _ageClass.dispose();
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
          final revision = await widget.roster.updatePerson(
            clubId: widget.contextValue.clubId,
            teamId: teamId,
            personId: widget.initial!.id,
            displayName: _name.text.trim(),
            ageClass: _ageClass.text.trim(),
            expectedRevision: widget.initial!.personRevision!,
            idempotencyKey: _newUuid(),
          );
          if (_guardianRequired != widget.initial!.safeguardingRequired) {
            await widget.roster.setGuardianRequirement(
              clubId: widget.contextValue.clubId,
              teamId: teamId,
              personId: widget.initial!.id,
              guardianRequired: _guardianRequired,
              expectedRevision: revision,
              idempotencyKey: _newUuid(),
            );
          }
        } else {
          await widget.roster.createPerson(
            clubId: widget.contextValue.clubId,
            teamId: teamId,
            displayName: _name.text.trim(),
            ageClass: _ageClass.text.trim(),
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
            'Personen kunde inte sparas. Kontrollera dubbletter och ladda om innan du försöker igen.',
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
                  TextFormField(
                    controller: _ageClass,
                    maxLength: 40,
                    decoration: InputDecoration(
                      labelText: strings.feature('Åldersklass (valfri)'),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) > 40
                        ? strings.feature('Ange högst 40 tecken.')
                        : null,
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
}

class _RosterPersonDetailsView extends StatelessWidget {
  const _RosterPersonDetailsView({required this.future});
  final Future<RosterPersonDetails> future;

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
              title: Text(strings.feature('Åldersklass')),
              subtitle: Text(person.ageClass!),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(strings.feature('Status')),
            subtitle: Text(strings.domainValue(person.assignmentState)),
          ),
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
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final ValueChanged<String> onNavigate;

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
                            : () => widget.onNavigate('/team?tab=roster'),
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
                required imageUrl,
              }) => widget.roster.updateTeamProfile(
                teamId: teamId,
                teamType: teamType,
                ageClass: ageClass,
                summary: summary,
                imageUrl: imageUrl,
                expectedRevision: value.revision,
                idempotencyKey: _newUuid(),
              ),
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
    required String imageUrl,
  })
  onSave;
  @override
  State<_TeamProfileEditDialog> createState() => _TeamProfileEditDialogState();
}

class _TeamProfileEditDialogState extends State<_TeamProfileEditDialog> {
  late final _teamType = TextEditingController(text: widget.value.teamType);
  late final _ageClass = TextEditingController(text: widget.value.ageClass);
  late final _summary = TextEditingController(text: widget.value.summary);
  late final _imageUrl = TextEditingController(text: widget.value.imageUrl);
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _teamType.dispose();
    _ageClass.dispose();
    _summary.dispose();
    _imageUrl.dispose();
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
              TextFormField(
                controller: _imageUrl,
                maxLength: 2048,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: strings.feature('Lagbildens HTTPS-adress'),
                  helperText: strings.feature(
                    'Säker bilduppladdning läggs till separat.',
                  ),
                ),
                validator: (value) {
                  final url = value?.trim() ?? '';
                  return url.isEmpty || Uri.tryParse(url)?.scheme == 'https'
                      ? null
                      : strings.feature('Ange en giltig HTTPS-adress.');
                },
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        teamType: _teamType.text.trim(),
        ageClass: _ageClass.text.trim(),
        summary: _summary.text.trim(),
        imageUrl: _imageUrl.text.trim(),
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
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _load;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final item in _TeamEventFilter.values)
                    FilterChip(
                      label: Text(switch (item) {
                        _TeamEventFilter.all => strings.feature('Alla'),
                        _TeamEventFilter.match => strings.feature('Matcher'),
                        _TeamEventFilter.training => strings.feature(
                          'Träningar',
                        ),
                        _TeamEventFilter.meeting => strings.feature('Möten'),
                      }),
                      selected: _filter == item,
                      onSelected: (_) => setState(() => _filter = item),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _TeamEventSection(
                title: strings.feature('Kommande'),
                events: upcoming,
              ),
              const SizedBox(height: 20),
              _TeamEventSection(
                title: strings.feature('Tidigare'),
                events: previous,
              ),
            ],
          ),
        );
      },
    );
  }
}

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
        for (final event in events)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              event.type == 'match' ? Icons.sports_soccer : Icons.event,
            ),
            title: Text(event.title),
            subtitle: Text(
              '${event.startsAt.toLocal()}${event.locationName == null ? '' : ' · ${event.locationName}'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => GoRouter.of(context).go('/calendar?event=${event.id}'),
          ),
    ],
  );
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.feature(
            approve ? 'Godkänn medlemsansökan?' : 'Avslå medlemsansökan?',
          ),
        ),
        content: Text(
          strings.feature(
            approve
                ? 'Personen får den valda rollen i laget.'
                : 'Sökanden ser endast att ansökan har avslagits.',
          ),
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
