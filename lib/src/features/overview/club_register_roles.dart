part of '../../app/teamzone_app.dart';

// Roller i personkortet (2026-11-11): the club admin gives and takes back a
// person's roles from the member register - Styrelse eller funktionär and
// Medlem i klubben for the whole club, leader and player in a team. Club
// areas are still given under Klubbens behörigheter.

const _clubWideRoles = ['club_functionary', 'member'];
const _teamRoles = ['leader', 'player'];

String _clubRoleLabel(AppStrings strings, String role) =>
    strings.feature(switch (role) {
      'club_functionary' => 'Styrelse eller funktionär',
      'member' => 'Medlem i klubben',
      'leader' => 'Ledare',
      'player' => 'Spelare',
      'guardian' => 'Vårdnadshavare',
      _ => role,
    });

class _ClubRegisterRoles extends StatefulWidget {
  const _ClubRegisterRoles({
    required this.clubId,
    required this.person,
    required this.services,
    required this.onChanged,
  });
  final String clubId;
  final ClubRegisterPerson person;
  final ClubRegisterServices services;

  /// A role was saved: the register reloads.
  final VoidCallback onChanged;

  @override
  State<_ClubRegisterRoles> createState() => _ClubRegisterRolesState();
}

class _ClubRegisterRolesState extends State<_ClubRegisterRoles> {
  late final Future<List<({String id, String name})>> _teams = widget.services
      .listClubTeams(widget.clubId)
      .timeout(const Duration(seconds: 15));
  String? _role;
  String? _teamId;
  bool _busy = false;
  String? _error;

  ClubRegisterPerson get _person => widget.person;

  List<String> get _addable => [
    for (final role in _clubWideRoles)
      if (!_person.clubRoles.contains(role)) role,
    ..._teamRoles,
  ];

  Future<void> _run(Future<void> Function() change) async {
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await change();
      if (mounted) widget.onChanged();
    } catch (error) {
      AppErrors.caught('club_register_roles', error);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = strings.feature(switch (error) {
          ClubRoleException(code: 'own_club_role') =>
            'Du kan inte ta bort din egen roll som funktionär.',
          ClubRoleException(code: 'own_leader_role') =>
            'Du kan inte ta bort din egen ledarroll.',
          ClubRoleException(code: 'last_memberships_manager') =>
            'Klubben måste ha minst en person med Medlemmar och lag.',
          ClubRoleException(code: 'home_in_other_team') =>
            'Personen är redan spelare i ett annat lag.',
          ClubRoleException(code: 'stale_role') =>
            'Rollen har ändrats av någon annan. Stäng och öppna igen.',
          _ => 'Rollen kunde inte sparas. Försök igen.',
        });
      });
    }
  }

  void _removeClubRole(String role) => _run(
    () => widget.services.setClubRole(
      clubId: widget.clubId,
      personId: _person.personId,
      role: role,
      active: false,
      idempotencyKey: _newUuid(),
    ),
  );

  void _removeTeamRole(ClubRegisterTeamRole team) => _run(
    () => widget.services.setTeamRole(
      clubId: widget.clubId,
      teamId: team.teamId,
      personId: _person.personId,
      fromRole: team.role,
      idempotencyKey: _newUuid(),
    ),
  );

  void _add() {
    final role = _role;
    if (role == null) return;
    if (_clubWideRoles.contains(role)) {
      _run(
        () => widget.services.setClubRole(
          clubId: widget.clubId,
          personId: _person.personId,
          role: role,
          active: true,
          idempotencyKey: _newUuid(),
        ),
      );
    } else if (_teamId != null) {
      _run(
        () => widget.services.setTeamRole(
          clubId: widget.clubId,
          teamId: _teamId!,
          personId: _person.personId,
          toRole: role,
          idempotencyKey: _newUuid(),
        ),
      );
    }
  }

  Widget _roleRow({
    required String keyName,
    required String title,
    required String subtitle,
    VoidCallback? onRemove,
  }) {
    final strings = AppStrings.of(context);
    return ListTile(
      key: ValueKey('club-register-role-$keyName'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onRemove == null
          ? null
          : IconButton(
              key: ValueKey('club-register-role-remove-$keyName'),
              tooltip: strings.feature('Ta bort rollen'),
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: _busy ? null : onRemove,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final rows = [
      for (final role in _person.clubRoles)
        _roleRow(
          keyName: role,
          title: _clubRoleLabel(strings, role),
          subtitle: strings.feature('Hela klubben'),
          onRemove: role == 'club_functionary' && _person.isSelf
              ? null
              : () => _removeClubRole(role),
        ),
      for (final team in _person.teams)
        _roleRow(
          keyName: '${team.teamId}-${team.role}',
          title: _clubRoleLabel(strings, team.role),
          subtitle: team.teamName,
          // A guardian follows the child; your own leader role stays.
          onRemove:
              !_teamRoles.contains(team.role) ||
                  (team.role == 'leader' && _person.isSelf)
              ? null
              : () => _removeTeamRole(team),
        ),
    ];
    final needsTeam = _role != null && _teamRoles.contains(_role);
    return Column(
      key: const ValueKey('club-register-roles'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.feature('Roller'), style: theme.textTheme.titleSmall),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(strings.feature('Personen har ingen roll i klubben.')),
          )
        else
          ...rows,
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const ValueKey('club-register-role-new'),
          initialValue: _role,
          decoration: InputDecoration(
            labelText: strings.feature('Lägg till roll'),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final role in _addable)
              DropdownMenuItem(
                value: role,
                child: Text(_clubRoleLabel(strings, role)),
              ),
          ],
          onChanged: _busy ? null : (value) => setState(() => _role = value),
        ),
        if (needsTeam) ...[
          const SizedBox(height: 8),
          FutureBuilder<List<({String id, String name})>>(
            future: _teams,
            builder: (context, snapshot) {
              final teams = snapshot.data ?? const [];
              if (snapshot.hasError) {
                return Text(strings.feature('Lagen kunde inte hämtas.'));
              }
              return DropdownButtonFormField<String>(
                key: const ValueKey('club-register-role-team'),
                initialValue: _teamId,
                decoration: InputDecoration(
                  labelText: strings.feature('Lag'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final team in teams)
                    DropdownMenuItem(value: team.id, child: Text(team.name)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _teamId = value),
              );
            },
          ),
        ],
        if (_role == 'club_functionary')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              strings.feature(
                'Områden som Medlemmar och lag ger du under Klubbens behörigheter.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const ValueKey('club-register-role-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('club-register-role-add'),
            onPressed: _busy || _role == null || (needsTeam && _teamId == null)
                ? null
                : _add,
            icon: const Icon(Icons.add),
            label: Text(strings.feature('Lägg till')),
          ),
        ),
      ],
    );
  }
}
