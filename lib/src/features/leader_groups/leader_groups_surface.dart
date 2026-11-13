part of '../../app/teamzone_app.dart';

/// Ledargrupper: the club's own groups of leaders across teams, e.g. a
/// herrsektion with the men's teams, the oldest junior team and a few board
/// members. Made by whoever holds members and teams or leads the board; each
/// group gets a chat in the members' Inkorg and can book meetings that show
/// in the members' calendars.
class _LeaderGroupsSurface extends StatefulWidget {
  const _LeaderGroupsSurface({
    required this.clubId,
    required this.services,
    required this.onNavigate,
  });
  final String clubId;
  final LeaderGroupServices services;
  final ValueChanged<String> onNavigate;

  @override
  State<_LeaderGroupsSurface> createState() => _LeaderGroupsSurfaceState();
}

class _LeaderGroupsSurfaceState extends State<_LeaderGroupsSurface> {
  late Future<LeaderGroupsOverview> _overview = _load();

  Future<LeaderGroupsOverview> _load() => widget.services.list(widget.clubId);

  void _reload() => setState(() {
    _overview = _load();
  });

  Future<void> _edit(
    LeaderGroupsOverview overview, [
    LeaderGroup? group,
  ]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LeaderGroupEditor(
          clubId: widget.clubId,
          services: widget.services,
          overview: overview,
          group: group,
        ),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _archive(LeaderGroup group) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Ta bort ${group.name}?'),
        content: const Text(
          'Gruppen försvinner och chatten stängs. Det som skrivits finns kvar '
          'att läsa i Inkorgen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            key: const ValueKey('leader-group-archive-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.services.archive(
        groupId: group.id,
        expectedRevision: group.revision,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('${group.name} är borttagen.')),
      );
    } catch (error) {
      if (error is! LeaderGroupException) {
        AppErrors.caught('leader_groups_surface._archive', error);
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Gruppen kunde inte tas bort. Försök igen.'),
        ),
      );
    }
    if (mounted) _reload();
  }

  Future<void> _bookMeeting(LeaderGroup group) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = await showDialog<String>(
      context: context,
      builder: (_) =>
          _LeaderGroupMeetingDialog(group: group, services: widget.services),
    );
    if (id == null || !mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Mötet är bokat och syns i kalendern för ${group.name}.'),
        action: SnackBarAction(
          label: 'Öppna',
          onPressed: () =>
              widget.onNavigate(ProductRouteContract.calendarEvent(id)),
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LeaderGroupsOverview>(
    future: _overview,
    builder: (context, snapshot) {
      final overview = snapshot.data;
      return Scaffold(
        key: const ValueKey('leader-groups'),
        appBar: AppBar(title: const Text('Ledargrupper')),
        floatingActionButton: overview == null
            ? null
            : FloatingActionButton.extended(
                key: const ValueKey('leader-group-new'),
                onPressed: () => _edit(overview),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Ny ledargrupp'),
              ),
        body: snapshot.hasError
            ? Center(
                child: TextButton(
                  onPressed: _reload,
                  child: const Text(
                    'Ledargrupperna kunde inte hämtas. Försök igen.',
                  ),
                ),
              )
            : overview == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _overview;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    const Text(
                      'Samla ledare från flera lag, till exempel en herrsektion '
                      'med herrlagens ledare, äldsta juniorlaget och några '
                      'ur styrelsen. Lagens ledare följer med automatiskt när '
                      'de byts ut. Varje grupp får en egen chatt i Inkorgen '
                      'och kan boka möten som syns i medlemmarnas kalender.',
                    ),
                    const SizedBox(height: 16),
                    if (overview.groups.isEmpty)
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.groups_outlined),
                          title: Text('Klubben har inga ledargrupper än.'),
                        ),
                      ),
                    for (final group in overview.groups)
                      _LeaderGroupCard(
                        group: group,
                        onEdit: () => _edit(overview, group),
                        onArchive: () => _archive(group),
                        onBookMeeting: () => _bookMeeting(group),
                        onOpenMeeting: (meeting) => widget.onNavigate(
                          ProductRouteContract.calendarEvent(meeting.id),
                        ),
                        onOpenChat: group.threadId == null
                            ? null
                            : () => widget.onNavigate(
                                '${ProductRouteContract.inbox}?thread=${group.threadId}',
                              ),
                      ),
                  ],
                ),
              ),
      );
    },
  );
}

class _LeaderGroupCard extends StatelessWidget {
  const _LeaderGroupCard({
    required this.group,
    required this.onEdit,
    required this.onArchive,
    required this.onOpenChat,
    required this.onBookMeeting,
    required this.onOpenMeeting,
  });
  final LeaderGroup group;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback? onOpenChat;
  final VoidCallback onBookMeeting;
  final ValueChanged<LeaderGroupMeeting> onOpenMeeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = group.memberCount;
    return Card(
      key: ValueKey('leader-group-${group.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(group.name, style: theme.textTheme.titleMedium),
                ),
                Text(
                  count == 1 ? '1 medlem' : '$count medlemmar',
                  style: theme.textTheme.bodySmall,
                ),
                PopupMenuButton<String>(
                  key: ValueKey('leader-group-menu-${group.id}'),
                  tooltip: 'Fler val',
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onArchive(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Ändra')),
                    PopupMenuItem(value: 'archive', child: Text('Ta bort')),
                  ],
                ),
              ],
            ),
            if (group.teams.isNotEmpty)
              _LeaderGroupLine(
                icon: Icons.groups_outlined,
                text:
                    'Ledarna i ${group.teams.map((team) => team.name).join(', ')}',
              ),
            if (group.people.isNotEmpty)
              _LeaderGroupLine(
                icon: Icons.person_outline,
                text: group.people.map((person) => person.name).join(', '),
              ),
            _LeaderGroupMeetings(group: group, onOpen: onOpenMeeting),
            Wrap(
              children: [
                TextButton.icon(
                  key: ValueKey('leader-group-chat-${group.id}'),
                  onPressed: onOpenChat,
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Öppna chatten'),
                ),
                TextButton.icon(
                  key: ValueKey('leader-group-book-${group.id}'),
                  onPressed: group.canBookMeetings ? onBookMeeting : null,
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Nytt möte'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderGroupLine extends StatelessWidget {
  const _LeaderGroupLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, right: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// Name, teams and people of a new or existing group.
class _LeaderGroupEditor extends StatefulWidget {
  const _LeaderGroupEditor({
    required this.clubId,
    required this.services,
    required this.overview,
    this.group,
  });
  final String clubId;
  final LeaderGroupServices services;
  final LeaderGroupsOverview overview;
  final LeaderGroup? group;

  @override
  State<_LeaderGroupEditor> createState() => _LeaderGroupEditorState();
}

class _LeaderGroupEditorState extends State<_LeaderGroupEditor> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late final Set<String> _teams = {
    ...?widget.group?.teams.map((team) => team.id),
  };
  late final Set<String> _people = {
    ...?widget.group?.people.map((person) => person.id),
  };
  String _filter = '';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && (_teams.isNotEmpty || _people.isNotEmpty);

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await widget.services.save(
        clubId: widget.clubId,
        groupId: widget.group?.id,
        name: _name.text.trim(),
        teamIds: _teams.toList(),
        personIds: _people.toList(),
        expectedRevision: widget.group?.revision,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      final code = error is LeaderGroupException ? error.code : null;
      if (code == null) AppErrors.caught('leader_groups_surface._save', error);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (code) {
            'name_taken' => 'Klubben har redan en ledargrupp med det namnet.',
            'stale_revision' =>
              'Gruppen har ändrats av någon annan. Stäng och öppna den igen.',
            'empty_group' => 'Välj minst ett lag eller en person.',
            _ => 'Gruppen kunde inte sparas. Försök igen.',
          }),
        ),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  String _describe(LeaderGroupCandidate person) {
    final board = BoardStrings.of(context);
    return [
      for (final office in person.offices) board.office(office),
      if (person.teams.isNotEmpty) 'Ledare i ${person.teams.join(', ')}',
      if (person.offices.isEmpty && person.teams.isEmpty && person.functionary)
        'Klubbfunktionär',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _filter.trim().toLowerCase();
    final people = [
      for (final person in widget.overview.people)
        if (query.isEmpty ||
            person.name.toLowerCase().contains(query) ||
            _people.contains(person.id))
          person,
    ];
    return Scaffold(
      key: const ValueKey('leader-group-editor'),
      appBar: AppBar(
        title: Text(
          widget.group == null ? 'Ny ledargrupp' : 'Ändra ledargrupp',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const ValueKey('leader-group-save'),
              onPressed: _saving || !_valid ? null : _save,
              child: const Text('Spara'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                key: const ValueKey('leader-group-name'),
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Namn',
                  hintText: 'Till exempel Herrsektionen',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text('Lag', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('Lagens ledare är med så länge de leder laget.'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final team in widget.overview.teams)
                    FilterChip(
                      key: ValueKey('leader-group-team-${team.id}'),
                      label: Text(team.name),
                      selected: _teams.contains(team.id),
                      onSelected: (on) => setState(
                        () => on ? _teams.add(team.id) : _teams.remove(team.id),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Personer', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Lägg till fler, till exempel ledamöter ur styrelsen eller en '
                'ledare från ett lag som inte är med.',
              ),
              const SizedBox(height: 8),
              if (widget.overview.people.length > 8)
                TextField(
                  key: const ValueKey('leader-group-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Sök person',
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              for (final person in people)
                CheckboxListTile(
                  key: ValueKey('leader-group-person-${person.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: _people.contains(person.id),
                  title: Text(person.name),
                  subtitle: Text(_describe(person)),
                  onChanged: (on) => setState(
                    () => on == true
                        ? _people.add(person.id)
                        : _people.remove(person.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
