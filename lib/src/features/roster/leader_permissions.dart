part of '../../app/teamzone_app.dart';

/// The per-leader permission panel (TEAM-10). Capabilities are granted on the
/// person's leader role in this team; the server only accepts changes the
/// viewer could make themselves, and never lets anyone remove their own right
/// to manage leaders.

const _permissionGroups = <(String, List<(String, String, String)>)>[
  (
    'Laget',
    [
      (
        'team.roster.manage',
        'Trupp och medlemmar',
        'Lägga till, ändra och bjuda in personer',
      ),
      (
        'team.leaders.manage',
        'Ledare och behörigheter',
        'Göra personer till ledare och ändra behörigheter',
      ),
    ],
  ),
  (
    'Event',
    [
      (
        'event.manage',
        'Skapa och flytta event',
        'Datum, tid, plats, ställa in och dela',
      ),
      ('event.squad.manage', 'Kallelser', 'Välja trupp, skicka och påminna'),
      ('event.attendance.manage', 'Närvaro', 'Registrera närvaro'),
      (
        'event.attendance.correct_late',
        'Sen närvarorättelse',
        'Rätta närvaro efter att eventet är över',
      ),
      (
        'event.logistics',
        'Material, uppgifter och filer',
        'Förberedelser som alla behöver, mötesagenda',
      ),
    ],
  ),
  (
    'Träning',
    [
      (
        'training.plan',
        'Träningsupplägg',
        'Träningsfokus och träningsanteckningar',
      ),
    ],
  ),
  (
    'Match',
    [
      ('match.plan', 'Matchplan och taktik', 'Matchförberedelse och taktik'),
      (
        'match.live',
        'Matchläge och resultat',
        'Klocka, mål, resultat och matchrapport',
      ),
    ],
  ),
  (
    'Övrigt',
    [
      ('development.manage', 'Spelarutveckling', 'Utvecklingsplaner'),
      ('publication.manage', 'Publicera', 'Nyheter och lagets publika sida'),
    ],
  ),
];

const _permissionTemplates = <String, Set<String>>{
  'head_coach': {
    'team.roster.manage',
    'team.leaders.manage',
    'event.manage',
    'event.squad.manage',
    'event.attendance.manage',
    'event.attendance.correct_late',
    'event.logistics',
    'training.plan',
    'match.plan',
    'match.live',
    'development.manage',
    'publication.manage',
  },
  'assistant_coach': {
    'event.attendance.manage',
    'event.logistics',
    'training.plan',
    'match.plan',
    'match.live',
    'development.manage',
  },
  'team_manager': {
    'team.roster.manage',
    'event.manage',
    'event.squad.manage',
    'event.attendance.manage',
    'event.attendance.correct_late',
    'event.logistics',
    'match.live',
    'publication.manage',
  },
  'specialist_coach': {'event.attendance.manage', 'training.plan'},
  'standard': {
    'team.roster.manage',
    'event.manage',
    'event.squad.manage',
    'event.attendance.manage',
    'event.attendance.correct_late',
    'event.logistics',
    'training.plan',
    'match.plan',
    'match.live',
  },
};

const _permissionTemplateLabels = <String, String>{
  'head_coach': 'Huvudtränare',
  'assistant_coach': 'Assisterande tränare',
  'team_manager': 'Lagledare',
  'specialist_coach': 'Målvakts- och fystränare',
  'standard': 'Ledare (standard)',
};

String _permissionTemplateLabel(AppStrings strings, String? template) =>
    template == null || template == 'custom'
    ? strings.feature(template == null ? 'Ledare (standard)' : 'Anpassad')
    : strings.feature(_permissionTemplateLabels[template] ?? 'Anpassad');

/// The template a title suggests; never applied without confirmation.
String? _suggestedPermissionTemplate(TeamRole role) {
  for (final (title, template) in const [
    ('head_coach', 'head_coach'),
    ('assistant_coach', 'assistant_coach'),
    ('team_manager', 'team_manager'),
    ('goalkeeper_coach', 'specialist_coach'),
    ('fitness_coach', 'specialist_coach'),
  ]) {
    if (role.titles.contains(title)) return template;
  }
  return null;
}

Future<bool> _openLeaderPermissions(
  BuildContext context, {
  required RosterServices roster,
  required TeamZoneContext contextValue,
  required TeamRoles data,
  required TeamRole role,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LeaderPermissionsSheet(
        roster: roster,
        contextValue: contextValue,
        data: data,
        role: role,
      ),
    ) ??
    false;

class _LeaderPermissionsSheet extends StatefulWidget {
  const _LeaderPermissionsSheet({
    required this.roster,
    required this.contextValue,
    required this.data,
    required this.role,
  });
  final RosterServices roster;
  final TeamZoneContext contextValue;
  final TeamRoles data;
  final TeamRole role;

  @override
  State<_LeaderPermissionsSheet> createState() =>
      _LeaderPermissionsSheetState();
}

class _LeaderPermissionsSheetState extends State<_LeaderPermissionsSheet> {
  late final Set<String> _original = {...?widget.role.permissions};
  late Set<String> _selected = {..._original};
  late String? _template = widget.role.permissionTemplate;
  String _key = _newUuid();
  bool _busy = false, _partialTemplate = false;
  String? _error;

  Set<String> get _grantable => widget.data.grantable.toSet();

  bool _locked(String capability) =>
      !_grantable.contains(capability) ||
      (widget.role.isSelf && capability == 'team.leaders.manage');

  /// The template matching the current selection, if any.
  String? get _matchingTemplate {
    for (final entry in _permissionTemplates.entries) {
      if (entry.value.length == _selected.length &&
          entry.value.containsAll(_selected)) {
        return entry.key;
      }
    }
    return null;
  }

  bool get _dirty =>
      _selected.length != _original.length || !_original.containsAll(_selected);

  void _toggle(String capability, bool value) => setState(() {
    value ? _selected.add(capability) : _selected.remove(capability);
    _key = _newUuid();
    _error = null;
  });

  /// Applies a template to what the viewer may change; the rest keeps its
  /// current state and the viewer is told.
  void _applyTemplate(String template) {
    final wanted = _permissionTemplates[template]!;
    var partial = false;
    final next = {..._selected};
    for (final capability in _permissionTemplates['head_coach']!) {
      final want = wanted.contains(capability);
      if (want == next.contains(capability)) continue;
      if (_locked(capability)) {
        partial = true;
        continue;
      }
      want ? next.add(capability) : next.remove(capability);
    }
    setState(() {
      _selected = next;
      _template = template;
      _partialTemplate = partial;
      _key = _newUuid();
      _error = null;
    });
  }

  Future<void> _save() async {
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.roster
          .setLeaderPermissions(
            clubId: widget.contextValue.clubId,
            teamId: widget.contextValue.teamId!,
            personId: widget.role.personId,
            capabilities: _selected.toList()..sort(),
            expected: _original.toList()..sort(),
            template: _matchingTemplate ?? 'custom',
            idempotencyKey: _key,
          )
          .timeout(const Duration(seconds: 20));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = strings.feature(switch (error) {
          TeamRoleException(code: 'stale_permissions') =>
            'Behörigheterna har ändrats av någon annan. Stäng och öppna igen.',
          TeamRoleException(code: 'not_grantable') =>
            'Du kan bara ge eller ta bort behörigheter som du själv har.',
          TeamRoleException(code: 'own_leaders_permission') =>
            'Du kan inte ta bort din egen behörighet att hantera ledare.',
          TeamRoleException(code: 'last_leaders_manager') =>
            'Laget måste ha minst en person som kan hantera ledare.',
          _ => 'Behörigheterna kunde inte sparas. Försök igen.',
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final suggested = _suggestedPermissionTemplate(widget.role);
    final matching = _matchingTemplate;
    final titles = _titlesSummary(strings, widget.role);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: CircleAvatar(child: Text(_initialsOf(widget.role.name))),
            title: Text(
              widget.role.isSelf
                  ? '${widget.role.name} (${strings.feature('du')})'
                  : widget.role.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                strings.feature('Ledare'),
                if (titles.isNotEmpty) titles,
              ].join(' · '),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  strings.feature('Utgå från mall'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    key: const ValueKey('permission-template'),
                    isExpanded: true,
                    value: _permissionTemplates.containsKey(_template)
                        ? _template
                        : null,
                    hint: Text(
                      _permissionTemplateLabel(strings, matching ?? 'custom'),
                    ),
                    items: [
                      for (final template in _permissionTemplates.keys)
                        DropdownMenuItem(
                          value: template,
                          child: Text(
                            _permissionTemplateLabel(strings, template),
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) _applyTemplate(value);
                          },
                  ),
                ),
              ],
            ),
          ),
          if (matching == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                strings.feature('Anpassad – skiljer sig från mallarna'),
                style: TextStyle(fontSize: 12, color: colors.tertiary),
              ),
            ),
          if (_partialTemplate)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                strings.feature(
                  'Vissa behörigheter ändrades inte eftersom du själv saknar dem.',
                ),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
          if (widget.role.permissionTemplate == null &&
              suggested != null &&
              matching != suggested)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${strings.feature('Titeln föreslår mallen')} ${_permissionTemplateLabel(strings, suggested)}.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('apply-suggested-template'),
                    onPressed: _busy ? null : () => _applyTemplate(suggested),
                    child: Text(strings.feature('Använd')),
                  ),
                ],
              ),
            ),
          const Divider(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (group, entries) in _permissionGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                    child: Text(
                      strings.feature(group).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .3,
                      ),
                    ),
                  ),
                  for (final (capability, label, description) in entries)
                    SwitchListTile(
                      key: ValueKey('permission-$capability'),
                      dense: true,
                      title: Text(strings.feature(label)),
                      subtitle: Text(strings.feature(description)),
                      value: _selected.contains(capability),
                      secondary: _locked(capability)
                          ? Tooltip(
                              message: strings.feature(
                                widget.role.isSelf &&
                                        capability == 'team.leaders.manage'
                                    ? 'Du kan inte ta bort din egen behörighet att hantera ledare.'
                                    : 'Du kan bara ge eller ta bort behörigheter som du själv har.',
                              ),
                              child: const Icon(Icons.lock_outline, size: 18),
                            )
                          : null,
                      onChanged: _busy || _locked(capability)
                          ? null
                          : (value) => _toggle(capability, value),
                    ),
                ],
              ],
            ),
          ),
          // Next to the buttons, so it is seen however far the list scrolled.
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: Text(strings.feature('Avbryt')),
                ),
                FilledButton(
                  key: const ValueKey('save-permissions'),
                  onPressed:
                      _busy ||
                          !_dirty &&
                              (matching ?? 'custom') ==
                                  widget.role.permissionTemplate
                      ? null
                      : _save,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.feature('Spara')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Behörighet" on a leader's member profile. Functionaries get their rights
/// from the club, so the panel is not offered for them.
class _PersonPermissionsTile extends StatefulWidget {
  const _PersonPermissionsTile({
    required this.contextValue,
    required this.roster,
    required this.personId,
    required this.roles,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final String personId;
  final Future<TeamRoles> roles;

  @override
  State<_PersonPermissionsTile> createState() => _PersonPermissionsTileState();
}

class _PersonPermissionsTileState extends State<_PersonPermissionsTile> {
  late Future<TeamRoles> _roles = widget.roles;

  Future<void> _edit(TeamRoles data, TeamRole role) async {
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
      _roles = widget.roster
          .listTeamRoles(
            clubId: widget.contextValue.clubId,
            teamId: widget.contextValue.teamId!,
          )
          .timeout(const Duration(seconds: 15));
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<TeamRoles>(
      future: _roles,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final rows = data.roles.where((row) => row.personId == widget.personId);
        final functionary = rows.any((row) => row.role == 'club_functionary');
        final leader = rows.where((row) => row.role == 'leader').firstOrNull;
        if (!functionary && leader?.permissions == null) {
          return const SizedBox.shrink();
        }
        final canEdit = !functionary && data.canManage;
        return ListTile(
          key: const ValueKey('person-permissions'),
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: Text(strings.feature('Behörighet')),
          subtitle: Text(
            functionary
                ? strings.feature('Klubbfunktionär – hela klubben')
                : _permissionTemplateLabel(strings, leader!.permissionTemplate),
          ),
          trailing: canEdit ? const Icon(Icons.chevron_right) : null,
          onTap: canEdit ? () => _edit(data, leader!) : null,
        );
      },
    );
  }
}
