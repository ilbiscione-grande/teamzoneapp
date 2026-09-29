part of '../../app/teamzone_app.dart';

/// Titles (for leaders) and playing positions (for players) per team.
/// Descriptive only: none of this changes what a person may do. Positions
/// come from the team sport's two-level catalog; teams can add own labels.

const _teamTitleLabels = <String, String>{
  'head_coach': 'Huvudtränare',
  'assistant_coach': 'Assisterande tränare',
  'team_manager': 'Lagledare',
  'contact_person': 'Kontaktperson',
  'goalkeeper_coach': 'Målvaktstränare',
  'fitness_coach': 'Fystränare',
  'equipment_manager': 'Materialansvarig',
  'medical_staff': 'Medicinskt ansvarig',
  'treasurer': 'Kassör',
  'administrator': 'Administratör',
};

const _playingPositionLabels = <String, String>{
  'goalkeeper': 'Målvakt',
  'defender': 'Försvarare',
  'midfielder': 'Mittfältare',
  'forward': 'Anfallare',
  'centre_back': 'Mittback',
  'left_back': 'Vänsterback',
  'right_back': 'Högerback',
  'wing_back': 'Wingback',
  'defensive_midfielder': 'Defensiv mittfältare',
  'central_midfielder': 'Central mittfältare',
  'attacking_midfielder': 'Offensiv mittfältare',
  'left_winger': 'Vänsterytter',
  'right_winger': 'Högerytter',
  'striker': 'Centralanfallare',
  'hb_backcourt': 'Nia',
  'hb_wing': 'Kant',
  'hb_pivot': 'Linjespelare',
  'hb_left_back': 'Vänsternia',
  'hb_centre_back': 'Mittnia',
  'hb_right_back': 'Högernia',
  'hb_left_wing': 'Vänstersexa',
  'hb_right_wing': 'Högersexa',
};

const _sportLabels = <String, String>{
  'football': 'Fotboll',
  'handball': 'Handboll',
  'other': 'Annan idrott',
};

String _titleLabel(AppStrings strings, String key) {
  final label = _teamTitleLabels[key];
  return label == null ? key : strings.feature(label);
}

String _positionLabel(AppStrings strings, String key) {
  final label = _playingPositionLabels[key];
  return label == null ? key : strings.feature(label);
}

String _sportLabel(AppStrings strings, String sport) =>
    strings.feature(_sportLabels[sport] ?? 'Annan idrott');

bool _isLeaderRole(String role) =>
    role == 'leader' || role == 'club_functionary';

/// "Huvudtränare · Ungdomsansvarig"
String _titlesSummary(AppStrings strings, TeamRole role) => [
  ...role.titles.map((key) => _titleLabel(strings, key)),
  ...role.customTitles,
].join(' · ');

/// "Mittback · Libero" — a general position is left out when one of its
/// detailed positions is also chosen, since it is implied.
String _positionsSummary(
  AppStrings strings,
  TeamRole role,
  List<SportPosition> catalog,
) {
  final order = {for (var i = 0; i < catalog.length; i++) catalog[i].key: i};
  final implied = {
    for (final entry in catalog)
      if (!entry.isGeneral && role.positions.contains(entry.key)) entry.parent,
  };
  final keys = role.positions.where((key) => !implied.contains(key)).toList()
    ..sort((a, b) => (order[a] ?? 99).compareTo(order[b] ?? 99));
  return [
    ...keys.map((key) => _positionLabel(strings, key)),
    ...role.customPositions,
  ].join(' · ');
}

/// Summary for a person given all their role rows in the team: titles when
/// they lead, positions when they play.
String _personDetailsSummary(
  AppStrings strings,
  TeamRoles data,
  String personId,
) {
  final rows = data.roles.where((role) => role.personId == personId).toList();
  if (rows.isEmpty) return '';
  final roles = rows.map((row) => row.role).toSet();
  return [
    if (roles.any(_isLeaderRole)) _titlesSummary(strings, rows.first),
    if (roles.contains('player'))
      _positionsSummary(strings, rows.first, data.positionCatalog),
  ].where((part) => part.isNotEmpty).join(' · ');
}

Future<bool> _editTeamPersonDetails(
  BuildContext context, {
  required RosterServices roster,
  required String clubId,
  required String teamId,
  required TeamRoles data,
  required String personId,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TeamPersonDetailsEditor(
        roster: roster,
        clubId: clubId,
        teamId: teamId,
        data: data,
        personId: personId,
      ),
    ) ??
    false;

class _TeamPersonDetailsEditor extends StatefulWidget {
  const _TeamPersonDetailsEditor({
    required this.roster,
    required this.clubId,
    required this.teamId,
    required this.data,
    required this.personId,
  });
  final RosterServices roster;
  final String clubId, teamId, personId;
  final TeamRoles data;
  @override
  State<_TeamPersonDetailsEditor> createState() =>
      _TeamPersonDetailsEditorState();
}

class _TeamPersonDetailsEditorState extends State<_TeamPersonDetailsEditor> {
  late TeamRoles _data = widget.data;
  late TeamRole _person = _rowFor(_data)!;
  late Set<String> _titles = _person.titles.toSet();
  late Set<String> _positions = _person.positions.toSet();
  late List<String> _customTitles = [..._person.customTitles];
  late List<String> _customPositions = [..._person.customPositions];
  late int _revision = _person.detailsRevision;
  final _customTitle = TextEditingController();
  final _customPosition = TextEditingController();
  // A new key per distinct selection; a retry of the same selection reuses it.
  String _key = _newUuid();
  String? _error;
  bool _busy = false;
  bool _stale = false;

  TeamRole? _rowFor(TeamRoles data) =>
      data.roles.where((role) => role.personId == widget.personId).firstOrNull;
  Set<String> get _roles => _data.rolesOf(widget.personId).toSet();
  bool get _isLeader => _roles.any(_isLeaderRole);
  bool get _isPlayer => _roles.contains('player');

  @override
  void dispose() {
    _customTitle.dispose();
    _customPosition.dispose();
    super.dispose();
  }

  void _changed(VoidCallback change) {
    if (_busy || _stale) return;
    setState(() {
      change();
      _key = _newUuid();
      _error = null;
    });
  }

  void _addCustom(TextEditingController controller, List<String> target) {
    final value = controller.text.trim();
    if (value.isEmpty || value.length > 40 || target.length >= 5) return;
    if (target.any((item) => item.toLowerCase() == value.toLowerCase())) {
      controller.clear();
      return;
    }
    _changed(() => target.add(value));
    controller.clear();
  }

  Future<void> _reload() async {
    final strings = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      final data = await widget.roster.listTeamRoles(
        clubId: widget.clubId,
        teamId: widget.teamId,
      );
      final person = _rowFor(data);
      if (!data.canEditDetails || person == null) throw StateError('not_found');
      if (mounted) {
        setState(() {
          _data = data;
          _person = person;
          _titles = person.titles.toSet();
          _positions = person.positions.toSet();
          _customTitles = [...person.customTitles];
          _customPositions = [...person.customPositions];
          _revision = person.detailsRevision;
          _key = _newUuid();
          _error = null;
          _stale = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = strings.feature(
            'Uppgifterna kunde inte hämtas. Kontrollera din behörighet och försök igen.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _stale) return;
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.roster
          .setTeamPersonDetails(
            clubId: widget.clubId,
            teamId: widget.teamId,
            personId: widget.personId,
            titles: _isLeader ? (_titles.toList()..sort()) : const [],
            positions: _isPlayer ? (_positions.toList()..sort()) : const [],
            customTitles: _isLeader ? _customTitles : const [],
            customPositions: _isPlayer ? _customPositions : const [],
            expectedRevision: _revision,
            idempotencyKey: _key,
          )
          .timeout(const Duration(seconds: 20));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _stale = error is PostgrestException && error.code == '40001';
          _error = strings.feature(
            _stale
                ? 'Uppgifterna har ändrats av någon annan. Hämta senaste uppgifter innan du sparar.'
                : 'Kunde inte spara. Kontrollera anslutningen och din behörighet och försök igen.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _title {
    final strings = AppStrings.of(context);
    if (_isLeader && _isPlayer) return strings.feature('Titel och position');
    return strings.feature(_isLeader ? 'Titel' : 'Position');
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _chips(
    Iterable<String> keys,
    Set<String> selected,
    String Function(String) label,
  ) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final key in keys)
        FilterChip(
          label: Text(label(key)),
          selected: selected.contains(key),
          onSelected: _busy || _stale
              ? null
              : (value) => _changed(
                  () => value ? selected.add(key) : selected.remove(key),
                ),
        ),
    ],
  );

  Widget _customEditor(
    List<String> values,
    TextEditingController controller,
    String hint,
  ) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (values.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final value in values)
                  InputChip(
                    label: Text(value),
                    onDeleted: _busy || _stale
                        ? null
                        : () => _changed(() => values.remove(value)),
                    deleteButtonTooltipMessage:
                        '${strings.feature('Ta bort')} $value',
                  ),
              ],
            ),
          ),
        if (values.length < 5)
          TextField(
            controller: controller,
            enabled: !_busy && !_stale,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _addCustom(controller, values),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              counterText: '',
              suffixIcon: IconButton(
                tooltip: strings.feature('Lägg till'),
                onPressed: () => _addCustom(controller, values),
                icon: const Icon(Icons.add),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final catalog = _data.positionCatalog;
    final general = catalog.where((entry) => entry.isGeneral).toList();
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _person.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  strings.feature(
                    'Gäller i detta lag och ändrar inte personens behörigheter.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_isLeader) ...[
                  _heading(strings.feature('Titel')),
                  _chips(
                    _teamTitleLabels.keys,
                    _titles,
                    (key) => _titleLabel(strings, key),
                  ),
                  _customEditor(
                    _customTitles,
                    _customTitle,
                    strings.feature('Egen titel'),
                  ),
                ],
                if (_isPlayer) ...[
                  _heading(
                    '${strings.feature('Position')} · ${_sportLabel(strings, _data.sport)}',
                  ),
                  if (general.isNotEmpty) ...[
                    _chips(
                      general.map((entry) => entry.key),
                      _positions,
                      (key) => _positionLabel(strings, key),
                    ),
                    for (final parent in general)
                      if (catalog.any((entry) => entry.parent == parent.key))
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_positionLabel(strings, parent.key)} – ${strings.feature('detaljerat')}',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              _chips(
                                catalog
                                    .where(
                                      (entry) => entry.parent == parent.key,
                                    )
                                    .map((entry) => entry.key),
                                _positions,
                                (key) => _positionLabel(strings, key),
                              ),
                            ],
                          ),
                        ),
                  ],
                  const SizedBox(height: 6),
                  _customEditor(
                    _customPositions,
                    _customPosition,
                    strings.feature('Egen position'),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_stale)
                  TextButton(
                    onPressed: _busy ? null : _reload,
                    child: Text(strings.feature('Hämta senaste uppgifter')),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            key: const ValueKey('save-team-person-details'),
            onPressed: _busy || _stale ? null : _save,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.feature('Spara')),
          ),
        ],
      ),
    );
  }
}

/// Titles/positions in a person's profile.
class _PersonTeamDetailsTile extends StatefulWidget {
  const _PersonTeamDetailsTile({
    required this.roster,
    required this.clubId,
    required this.teamId,
    required this.personId,
    this.roles,
  });
  final RosterServices roster;
  final String clubId, teamId, personId;

  /// Already loaded team roles, shared with the other profile tiles.
  final Future<TeamRoles>? roles;
  @override
  State<_PersonTeamDetailsTile> createState() => _PersonTeamDetailsTileState();
}

class _PersonTeamDetailsTileState extends State<_PersonTeamDetailsTile> {
  late Future<TeamRoles> _future = widget.roles ?? _load();
  Future<TeamRoles> _load() => widget.roster
      .listTeamRoles(clubId: widget.clubId, teamId: widget.teamId)
      .timeout(const Duration(seconds: 15));

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<TeamRoles>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListTile(
            title: Text(strings.feature('Titel och position')),
            subtitle: Text(strings.feature('Kunde inte hämta uppgifterna')),
            trailing: IconButton(
              tooltip: strings.feature('Försök igen'),
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                _future = _load();
              }),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return ListTile(
            title: Text(strings.feature('Titel och position')),
            subtitle: Text(strings.feature('Hämtar uppgifter…')),
          );
        }
        final roles = data.rolesOf(widget.personId).toSet();
        if (roles.isEmpty) return const SizedBox.shrink();
        final leader = roles.any(_isLeaderRole);
        final player = roles.contains('player');
        final summary = _personDetailsSummary(strings, data, widget.personId);
        return ListTile(
          key: const ValueKey('person-team-details'),
          leading: const Icon(Icons.assignment_ind_outlined),
          title: Text(
            strings.feature(
              leader && player
                  ? 'Titel och position'
                  : leader
                  ? 'Titel'
                  : 'Position',
            ),
          ),
          subtitle: Text(
            summary.isEmpty ? strings.feature('Inga valda') : summary,
          ),
          trailing: data.canEditDetails
              ? const Icon(Icons.chevron_right)
              : null,
          onTap: !data.canEditDetails
              ? null
              : () async {
                  final saved = await _editTeamPersonDetails(
                    context,
                    roster: widget.roster,
                    clubId: widget.clubId,
                    teamId: widget.teamId,
                    data: data,
                    personId: widget.personId,
                  );
                  if (saved && mounted) {
                    setState(() {
                      _future = _load();
                    });
                  }
                },
        );
      },
    );
  }
}
