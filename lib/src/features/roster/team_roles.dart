part of '../../app/teamzone_app.dart';

/// TEAM-09: who leads the team, and adding/changing player and leader roles.
/// Every change is a server command (history kept, capabilities follow the
/// role); the UI only offers what the active context may manage.

String _roleLabel(AppStrings strings, String role) => switch (role) {
  'leader' => strings.feature('Ledare'),
  'club_functionary' => strings.feature('Klubbfunktionär'),
  _ => strings.feature('Spelare'),
};

String _roleErrorMessage(AppStrings strings, Object error) => switch (error) {
  TeamRoleException(code: 'own_leader_role') => strings.feature(
    'Du kan inte ändra eller ta bort din egen ledarroll.',
  ),
  TeamRoleException(code: 'home_in_other_team') => strings.feature(
    'Personen spelar i ett annat lag. Använd Flytta eller Representation.',
  ),
  TeamRoleException(code: 'stale_role') => strings.feature(
    'Rollen har redan ändrats av någon annan.',
  ),
  _ => strings.feature('Rollen kunde inte ändras. Försök igen.'),
};

/// Runs one role command with a fixed idempotency key and reports the
/// outcome. Returns whether it succeeded.
Future<bool> _runRoleCommand(
  BuildContext context, {
  required RosterServices roster,
  required TeamZoneContext contextValue,
  required String personId,
  String? fromRole,
  String? toRole,
  required String success,
}) async {
  final strings = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await roster
        .setTeamRole(
          clubId: contextValue.clubId,
          teamId: contextValue.teamId!,
          personId: personId,
          fromRole: fromRole,
          toRole: toRole,
          idempotencyKey: _newUuid(),
        )
        .timeout(const Duration(seconds: 15));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(success)));
    return true;
  } catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(_roleErrorMessage(strings, error))),
      );
    return false;
  }
}

Future<void> _openTeamRolesSheet(
  BuildContext context, {
  required TeamZoneContext contextValue,
  required RosterServices roster,
  required List<RosterPersonSummary> people,
  required VoidCallback onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _TeamRolesSheet(
    contextValue: contextValue,
    roster: roster,
    people: people,
    onChanged: onChanged,
  ),
);

class _TeamRolesSheet extends StatefulWidget {
  const _TeamRolesSheet({
    required this.contextValue,
    required this.roster,
    required this.people,
    required this.onChanged,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final List<RosterPersonSummary> people;
  final VoidCallback onChanged;

  @override
  State<_TeamRolesSheet> createState() => _TeamRolesSheetState();
}

class _TeamRolesSheetState extends State<_TeamRolesSheet> {
  late Future<TeamRoles> _roles = _load();
  bool _busy = false;

  Future<TeamRoles> _load() => widget.roster
      .listTeamRoles(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));

  Future<void> _command({
    required String personId,
    String? fromRole,
    String? toRole,
    required String success,
  }) async {
    setState(() => _busy = true);
    final ok = await _runRoleCommand(
      context,
      roster: widget.roster,
      contextValue: widget.contextValue,
      personId: personId,
      fromRole: fromRole,
      toRole: toRole,
      success: success,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _roles = _load();
    });
    if (ok) widget.onChanged();
  }

  Future<void> _addLeader(TeamRoles current) async {
    final picked = await showModalBottomSheet<(String, String)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AddLeaderSheet(
        contextValue: widget.contextValue,
        roster: widget.roster,
        people: widget.people,
        current: current,
      ),
    );
    if (picked == null || !mounted) return;
    final strings = AppStrings.of(context);
    await _command(
      personId: picked.$1,
      toRole: 'leader',
      success: '${picked.$2} ${strings.feature('är nu ledare i laget.')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<TeamRoles>(
      future: _roles,
      builder: (context, snapshot) {
        final value = snapshot.data;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  strings.feature('Ledare och roller'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  strings.feature(
                    'Ledare kan hantera truppen, kallelser och event i laget.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (value != null && !value.canManage)
                Padding(
                  key: const ValueKey('leaders-manage-hint'),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.feature(
                            'Nya ledare och behörigheter hanteras av huvudtränaren eller en klubbfunktionär.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              if (value == null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: snapshot.hasError
                      ? Text(strings.feature('Rollerna kunde inte laddas.'))
                      : const Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_busy) const LinearProgressIndicator(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final rows in _groupedLeaders(value))
                        _personTile(rows, value),
                      if (value.roles.every((role) => role.role == 'player'))
                        ListTile(
                          title: Text(strings.feature('Inga ledare ännu')),
                        ),
                    ],
                  ),
                ),
                if (value.canManage)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: FilledButton.icon(
                      key: const ValueKey('add-team-leader'),
                      onPressed: _busy ? null : () => _addLeader(value),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(strings.feature('Lägg till ledare')),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// One row per person, whatever roles they hold here. The permission line
  /// is its own tap target so it is found without opening a menu.
  Widget _personTile(List<TeamRole> rows, TeamRoles data) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final person = rows.first;
    final leader = rows.where((row) => row.role == 'leader').firstOrNull;
    final functionary = rows.any((row) => row.role == 'club_functionary');
    final titles = _titlesSummary(strings, person);
    final roleLabels = [
      if (functionary) _roleLabel(strings, 'club_functionary'),
      if (leader != null) _roleLabel(strings, 'leader'),
    ].join(' · ');
    // A functionary's rights come from the club, so the leader-role panel
    // would not change what they can do.
    final permissionText = functionary
        ? strings.feature('Klubbfunktionär – hela klubben')
        : leader?.permissions != null
        ? _permissionTemplateLabel(strings, leader!.permissionTemplate)
        : null;
    final canEditPermissions =
        !functionary && leader?.permissions != null && data.canManage && !_busy;
    final canChangeRole = data.canManage && leader != null && !person.isSelf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: ValueKey('leader-${person.personId}'),
          leading: CircleAvatar(child: Text(_initialsOf(person.name))),
          title: Text(
            person.isSelf
                ? '${person.name} (${strings.feature('du')})'
                : person.name,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(roleLabels),
              Text(
                titles.isEmpty
                    ? strings.feature(
                        data.canEditDetails ? 'Välj titel' : 'Ingen titel vald',
                      )
                    : titles,
              ),
            ],
          ),
          onTap: !data.canEditDetails || _busy
              ? null
              : () async {
                  final saved = await _editTeamPersonDetails(
                    context,
                    roster: widget.roster,
                    clubId: widget.contextValue.clubId,
                    teamId: widget.contextValue.teamId!,
                    data: data,
                    personId: person.personId,
                  );
                  if (saved && mounted) {
                    setState(() {
                      _roles = _load();
                    });
                    widget.onChanged();
                  }
                },
          trailing: !canChangeRole
              ? null
              : PopupMenuButton<String>(
                  tooltip: strings.feature('Ändra roll'),
                  enabled: !_busy,
                  onSelected: (action) => action == 'player'
                      ? _command(
                          personId: person.personId,
                          fromRole: 'leader',
                          toRole: 'player',
                          success:
                              '${person.name} ${strings.feature('är nu spelare i laget.')}',
                        )
                      : _command(
                          personId: person.personId,
                          fromRole: 'leader',
                          success:
                              '${person.name} ${strings.feature('är inte längre ledare i laget.')}',
                        ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'player',
                      child: Text(strings.feature('Ändra till spelare')),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(strings.feature('Ta bort som ledare')),
                    ),
                  ],
                ),
        ),
        if (permissionText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Material(
              color: colors.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                key: ValueKey('leader-permissions-${person.personId}'),
                borderRadius: BorderRadius.circular(8),
                onTap: canEditPermissions
                    ? () => _editPermissions(leader!, data)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${strings.feature('Behörighet')}: $permissionText',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (canEditPermissions)
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: colors.primary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Leaders and functionaries, one entry per person, in list order.
  List<List<TeamRole>> _groupedLeaders(TeamRoles data) {
    final byPerson = <String, List<TeamRole>>{};
    for (final role in data.roles.where((role) => role.role != 'player')) {
      byPerson.putIfAbsent(role.personId, () => []).add(role);
    }
    return byPerson.values.toList();
  }

  Future<void> _editPermissions(TeamRole role, TeamRoles data) async {
    final saved = await _openLeaderPermissions(
      context,
      roster: widget.roster,
      contextValue: widget.contextValue,
      data: data,
      role: role,
    );
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${AppStrings.of(context).feature('Behörigheterna sparades för')} ${role.name}.',
          ),
        ),
      );
    setState(() {
      _roles = _load();
    });
    widget.onChanged();
  }
}

/// Picks who becomes leader: an existing club leader, someone already in
/// the squad, or (the actor) themselves. Returns (personId, name).
class _AddLeaderSheet extends StatefulWidget {
  const _AddLeaderSheet({
    required this.contextValue,
    required this.roster,
    required this.people,
    required this.current,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final List<RosterPersonSummary> people;
  final TeamRoles current;

  @override
  State<_AddLeaderSheet> createState() => _AddLeaderSheetState();
}

class _AddLeaderSheetState extends State<_AddLeaderSheet> {
  late final Future<List<LeaderCandidate>> _candidates = widget.roster
      .listLeaderCandidates(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));
  String _query = '';

  bool _matches(String name) =>
      _query.isEmpty || name.toLowerCase().contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final leaders = widget.current.roles
        .where((role) => role.role == 'leader')
        .map((role) => role.personId)
        .toSet();
    final squad = widget.people
        .where(
          (person) =>
              person.assignmentState == 'active' &&
              !leaders.contains(person.id) &&
              _matches(person.displayName),
        )
        .toList();
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              strings.feature('Lägg till ledare'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.feature('Sök person'),
                isDense: true,
              ),
            ),
          ),
          Flexible(
            child: FutureBuilder<List<LeaderCandidate>>(
              future: _candidates,
              builder: (context, snapshot) {
                final candidates =
                    (snapshot.data ?? const [])
                        .where((candidate) => _matches(candidate.name))
                        .toList()
                      // Offer yourself first: the common case right after
                      // creating a team.
                      ..sort((a, b) {
                        if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
                        return a.name.compareTo(b.name);
                      });
                return ListView(
                  shrinkWrap: true,
                  children: [
                    header(strings.feature('Klubbens ledare')),
                    if (snapshot.connectionState != ConnectionState.done)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError)
                      ListTile(
                        title: Text(
                          strings.feature('Klubbens ledare kunde inte laddas.'),
                        ),
                      )
                    else if (candidates.isEmpty)
                      ListTile(
                        dense: true,
                        title: Text(
                          strings.feature(
                            'Alla klubbens ledare är redan ledare här.',
                          ),
                        ),
                      ),
                    for (final candidate in candidates)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(_initialsOf(candidate.name)),
                        ),
                        title: Text(
                          candidate.isSelf
                              ? '${candidate.name} (${strings.feature('du')})'
                              : candidate.name,
                        ),
                        subtitle: Text(candidate.context),
                        trailing: const Icon(Icons.add),
                        onTap: () => Navigator.pop(context, (
                          candidate.personId,
                          candidate.name,
                        )),
                      ),
                    header(strings.feature('Från truppen')),
                    if (squad.isEmpty)
                      ListTile(
                        dense: true,
                        title: Text(
                          strings.feature('Ingen i truppen att välja.'),
                        ),
                      ),
                    for (final person in squad)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(_initialsOf(person.displayName)),
                        ),
                        title: Text(person.displayName),
                        subtitle: Text(
                          strings.feature('Behåller sin spelarroll'),
                        ),
                        trailing: const Icon(Icons.add),
                        onTap: () => Navigator.pop(context, (
                          person.id,
                          person.displayName,
                        )),
                      ),
                    header(strings.feature('Ny person')),
                    ListTile(
                      leading: const Icon(Icons.qr_code_2),
                      title: Text(strings.feature('Bjud in med en lagkod')),
                      subtitle: Text(
                        strings.feature(
                          'Skapa en lagkod med rollen Ledare under Inbjudningar och lagkoder.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Roll i laget" on the member profile: shows the person's roles here and
/// offers the valid player/leader changes.
class _PersonRoleTile extends StatefulWidget {
  const _PersonRoleTile({
    required this.contextValue,
    required this.roster,
    required this.person,
    this.roles,
    this.onChanged,
    this.interactive = true,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final RosterPersonDetails person;
  final Future<TeamRoles>? roles;

  /// Called after a successful change with the roles the person now holds.
  final ValueChanged<List<String>>? onChanged;
  final bool interactive;

  @override
  State<_PersonRoleTile> createState() => _PersonRoleTileState();
}

class _PersonRoleTileState extends State<_PersonRoleTile> {
  late Future<TeamRoles> _roles = widget.roles ?? _load();

  Future<TeamRoles> _load() => widget.roster
      .listTeamRoles(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
      )
      .timeout(const Duration(seconds: 15));

  Future<void> _choose(TeamRoles value) async {
    final strings = AppStrings.of(context);
    final roles = value.rolesOf(widget.person.id);
    final isPlayer = roles.contains('player');
    final isLeader = roles.contains('leader');
    final self = widget.person.isSelf;
    final canChangeOwnLeader =
        self && widget.contextValue.can('club.memberships.manage');
    final name = widget.person.displayName;
    final options = <(String, IconData, String?, String?, String)>[
      if (!isLeader)
        (
          strings.feature('Lägg till ledarroll'),
          Icons.add_moderator_outlined,
          null,
          'leader',
          '$name ${strings.feature('är nu ledare i laget.')}',
        ),
      if (isPlayer && !isLeader)
        (
          strings.feature('Byt från spelare till ledare'),
          Icons.swap_horiz,
          'player',
          'leader',
          '$name ${strings.feature('är nu ledare i laget.')}',
        ),
      if (isLeader && !isPlayer && (!self || canChangeOwnLeader))
        (
          strings.feature('Byt från ledare till spelare'),
          Icons.swap_horiz,
          'leader',
          'player',
          '$name ${strings.feature('är nu spelare i laget.')}',
        ),
      if (isLeader && (!self || canChangeOwnLeader))
        (
          strings.feature('Ta bort ledarrollen'),
          Icons.remove_moderator_outlined,
          'leader',
          null,
          '$name ${strings.feature('är inte längre ledare i laget.')}',
        ),
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                strings.feature('Roll i laget'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              subtitle: Text(
                roles.isEmpty
                    ? strings.feature('Ingen roll')
                    : roles.map((role) => _roleLabel(strings, role)).join(', '),
              ),
            ),
            for (var i = 0; i < options.length; i++)
              ListTile(
                leading: Icon(options[i].$2),
                title: Text(options[i].$1),
                onTap: () => Navigator.pop(sheetContext, i),
              ),
            if (self && isLeader && !canChangeOwnLeader)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                subtitle: Text(
                  strings.feature(
                    'Du kan inte ändra eller ta bort din egen ledarroll.',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final option = options[picked];
    final ok = await _runRoleCommand(
      context,
      roster: widget.roster,
      contextValue: widget.contextValue,
      personId: widget.person.id,
      fromRole: option.$3,
      toRole: option.$4,
      success: option.$5,
    );
    if (!mounted || !ok) return;
    final now = [
      ...roles.where((role) => role != option.$3),
      if (option.$4 != null && !roles.contains(option.$4)) option.$4!,
    ];
    final onChanged = widget.onChanged;
    if (onChanged != null) {
      onChanged(now);
    } else {
      setState(() {
        _roles = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<TeamRoles>(
      future: _roles,
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value == null) return const SizedBox.shrink();
        final roles = value.rolesOf(widget.person.id);
        if (roles.isEmpty && !value.canManage) return const SizedBox.shrink();
        return ListTile(
          key: const ValueKey('person-team-role'),
          leading: const Icon(Icons.badge_outlined),
          title: Text(strings.feature('Roll i laget')),
          subtitle: Text(
            roles.isEmpty
                ? strings.feature('Ingen roll')
                : roles.map((role) => _roleLabel(strings, role)).join(', '),
          ),
          trailing: value.canManage && widget.interactive
              ? const Icon(Icons.chevron_right)
              : null,
          onTap: value.canManage && widget.interactive
              ? () => _choose(value)
              : null,
        );
      },
    );
  }
}
