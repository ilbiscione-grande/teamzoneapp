part of '../../app/teamzone_app.dart';

/// Direct assignments from the session squad for the selected desktop block.
class _TrainingPlayerPanel extends StatefulWidget {
  const _TrainingPlayerPanel({
    super.key,
    required this.roster,
    required this.players,
    required this.onChanged,
    required this.onManageRoster,
    required this.onAddUnnamed,
    this.grouped = false,
  });
  final List<TrainingBlockPlayer> roster, players;
  final ValueChanged<List<TrainingBlockPlayer>> onChanged;
  final VoidCallback onManageRoster;

  /// Adds an unnamed player to the session squad and this exercise.
  final VoidCallback? onAddUnnamed;

  /// On a phone: the selected players first, the others folded below.
  final bool grouped;

  @override
  State<_TrainingPlayerPanel> createState() => _TrainingPlayerPanelState();
}

class _TrainingPlayerPanelState extends State<_TrainingPlayerPanel> {
  String _query = '';

  /// 0 all, 1 selected, 2 not selected.
  int _filter = 0;

  /// Whether the unselected players show; at first only when none is chosen.
  late bool _others = widget.players.isEmpty;

  List<Widget> _groups(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final chosen = [
      for (var i = 0; i < widget.roster.length; i++)
        if (widget.players.any((p) => p.id == widget.roster[i].id)) i,
    ];
    final rest = [
      for (var i = 0; i < widget.roster.length; i++)
        if (!chosen.contains(i)) i,
    ];
    final heading = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              strings.formatFeature('Valda spelare ({count})', {
                'count': chosen.length,
              }),
              style: heading,
            ),
          ),
          TextButton(
            onPressed: chosen.isEmpty ? null : () => widget.onChanged(const []),
            child: Text(strings.feature('Rensa')),
          ),
        ],
      ),
      for (final i in chosen) ?_player(context, i),
      const Divider(height: 24),
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => setState(() => _others = !_others),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.formatFeature('Övriga ({count})', {
                    'count': rest.length,
                  }),
                  style: heading?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Icon(_others ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
      if (_others)
        for (final i in rest) ?_player(context, i),
    ];
  }

  static String _colorName(TrainingPlayerTeam team) => switch (team) {
    TrainingPlayerTeam.blue => 'Blå',
    TrainingPlayerTeam.red => 'Röd',
    TrainingPlayerTeam.green => 'Grön',
    TrainingPlayerTeam.yellow => 'Gul',
    TrainingPlayerTeam.neutral => 'Neutral',
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.grouped) ...[
          Text(
            strings.formatFeature('Deltagare i passet ({selected}/{total})', {
              'selected': widget.players.length,
              'total': widget.roster.length,
            }),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('training-panel-search'),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: strings.feature('Sök spelare'),
                  border: border,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 104,
              child: DropdownButtonFormField<int>(
                initialValue: _filter,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  border: border,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                items: [
                  for (final (i, label) in const [
                    'Alla',
                    'Valda',
                    'Ej valda',
                  ].indexed)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        strings.feature(label),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _filter = value ?? 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.roster.isEmpty)
          Text(
            strings.feature(
              'Lägg till spelare i sessionstruppen på översikten.',
            ),
          ),
        Expanded(
          child: ListView(
            children: widget.grouped
                ? _groups(context)
                : [
                    for (var i = 0; i < widget.roster.length; i++)
                      ?_player(context, i),
                  ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('training-panel-add-unnamed'),
                onPressed: widget.onAddUnnamed,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  strings.feature('Lägg till ospecificerad spelare'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<int>(
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) => switch (value) {
                0 => widget.onManageRoster(),
                1 => widget.onChanged([
                  ...widget.players,
                  for (final person in widget.roster)
                    if (!widget.players.any((p) => p.id == person.id))
                      person.withTeam(TrainingPlayerTeam.blue),
                ]),
                _ => widget.onChanged(const []),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 0,
                  child: Text(strings.feature('Ändra sessionstruppen')),
                ),
                PopupMenuItem(
                  value: 1,
                  child: Text(strings.feature('Markera alla')),
                ),
                PopupMenuItem(
                  value: 2,
                  child: Text(strings.feature('Avmarkera alla')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// One squad player's row, or null when the search or filter hides it.
  Widget? _player(BuildContext context, int index) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final person = widget.roster[index];
    final name = person.personId == null
        ? strings.formatFeature('Spelare {number}', {
            'number':
                '${widget.roster.take(index + 1).where((p) => p.personId == null).length}',
          })
        : person.name;
    if (!name.toLowerCase().contains(_query)) return null;
    final selected = widget.players.where((p) => p.id == person.id).firstOrNull;
    if (_filter == 1 && selected == null || _filter == 2 && selected != null) {
      return null;
    }
    final initials = name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    void toggle(bool? checked) => widget.onChanged(
      checked == true
          ? [...widget.players, person.withTeam(TrainingPlayerTeam.blue)]
          : widget.players.where((p) => p.id != person.id).toList(),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => toggle(selected == null),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('training-panel-player-${person.id}'),
              value: selected != null,
              onChanged: toggle,
              visualDensity: VisualDensity.compact,
            ),
            CircleAvatar(
              radius: 14,
              backgroundColor: colors.surfaceContainerHigh,
              child: Text(
                initials,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${index + 1}. $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 92,
              height: 34,
              padding: const EdgeInsets.only(left: 8, right: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<TrainingPlayerTeam>(
                  key: ValueKey('training-panel-team-${person.id}'),
                  value: selected?.team,
                  isExpanded: true,
                  isDense: true,
                  menuWidth: 200,
                  disabledHint: Text(
                    strings.feature('Ingen'),
                    style: theme.textTheme.bodySmall,
                  ),
                  selectedItemBuilder: (context) => [
                    for (final team in TrainingPlayerTeam.values)
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 12,
                            color: _trainingPlayerColor(team),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              strings.feature(_colorName(team)),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                  ],
                  items: [
                    for (final team in TrainingPlayerTeam.values)
                      DropdownMenuItem(
                        value: team,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 12,
                              color: _trainingPlayerColor(team),
                            ),
                            const SizedBox(width: 6),
                            Text(strings.feature(team.label)),
                          ],
                        ),
                      ),
                  ],
                  onChanged: selected == null
                      ? null
                      : (team) {
                          if (team == null) return;
                          widget.onChanged([
                            for (final p in widget.players)
                              p.id == person.id ? p.withTeam(team) : p,
                          ]);
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
