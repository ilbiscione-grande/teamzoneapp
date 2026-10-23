part of '../../app/teamzone_app.dart';

/// Chooses a player for a slot or the bench: those who fit the slot's
/// position first, each with number, answer and where they already play.
class _PlayerPickerSheet extends StatelessWidget {
  const _PlayerPickerSheet({
    required this.title,
    required this.players,
    required this.answers,
    required this.placedIn,
    this.current,
    this.group,
  });
  final String title;
  final List<LineupPlayer> players;
  final Map<String, String?> answers;
  final Map<String, String> placedIn;
  final String? current, group;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final fits = group == null
        ? players
        : [
            ...players.where((p) => positionGroup(p.mainPosition) == group),
            ...players.where((p) => positionGroup(p.mainPosition) != group),
          ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: current == null
                  ? null
                  : TextButton(
                      key: const Key('lineup-pick-clear'),
                      onPressed: () => Navigator.pop(context, ''),
                      child: Text(strings.feature('Ta bort')),
                    ),
            ),
            const Divider(height: 1),
            if (fits.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(strings.feature('Inga fler spelare att välja.')),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final player in fits)
                      ListTile(
                        key: Key('lineup-pick-${player.personId}'),
                        selected: player.personId == current,
                        leading: CircleAvatar(
                          child: Text(player.number?.toString() ?? '–'),
                        ),
                        title: Text(player.name),
                        subtitle: Text(
                          [
                            if (player.mainPosition != null)
                              _anyPositionLabel(strings, player.mainPosition!),
                            if (placedIn[player.personId] case final where?)
                              '${strings.feature('Spelar')}: $where',
                          ].join(' · '),
                        ),
                        trailing: _AnswerIcon(answer: answers[player.personId]),
                        onTap: () => Navigator.pop(context, player.personId),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnswerIcon extends StatelessWidget {
  const _AnswerIcon({required this.answer});
  final String? answer;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final (label, icon, color) = switch (answer) {
      'accepted' => ('Kommer', Icons.check_circle, Colors.green),
      'declined' => ('Kommer inte', Icons.cancel, Colors.red),
      null => ('Inte kallad', Icons.remove_circle_outline, Colors.grey),
      _ => ('Inget svar', Icons.help_outline, Colors.orange),
    };
    return Tooltip(
      message: strings.feature(label),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// The bench: the substitutes, added from those not on the pitch.
class _BenchCard extends StatelessWidget {
  const _BenchCard({
    required this.players,
    required this.edit,
    required this.onAdd,
    required this.onRemove,
  });
  final List<LineupPlayer> players;
  final bool edit;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (!edit && players.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('lineup-bench'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${strings.feature('Avbytare')} (${players.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final player in players)
                  InputChip(
                    key: Key('lineup-bench-${player.personId}'),
                    avatar: CircleAvatar(
                      child: Text(player.number?.toString() ?? '–'),
                    ),
                    label: Text(player.name),
                    onDeleted: edit ? () => onRemove(player.personId) : null,
                  ),
                if (edit)
                  ActionChip(
                    key: const Key('lineup-bench-add'),
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(strings.feature('Lägg till')),
                    onPressed: onAdd,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The substitution plan, as the old app's checklist: who goes off for
/// whom, when, and why. Live will tick them off.
class _SubstitutionPlanCard extends StatelessWidget {
  const _SubstitutionPlanCard({
    required this.plan,
    required this.people,
    required this.onPitch,
    required this.bench,
    required this.onChanged,
  });
  final List<PlannedSubstitution> plan;
  final Map<String, LineupPlayer> people;
  final List<String> onPitch, bench;
  final ValueChanged<List<PlannedSubstitution>> onChanged;

  String _name(String id) => people[id]?.name ?? '?';

  Future<void> _add(BuildContext context) async {
    final added = await showDialog<PlannedSubstitution>(
      context: context,
      builder: (_) => _SubstitutionDialog(
        people: people,
        outOptions: [...onPitch, ...bench],
        inOptions: [...bench, ...onPitch],
      ),
    );
    if (added == null) return;
    final sorted = [...plan, added]
      ..sort((a, b) => (a.minute ?? 999).compareTo(b.minute ?? 999));
    onChanged(sorted);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final canAdd = onPitch.isNotEmpty && bench.isNotEmpty;
    return Card(
      key: const Key('lineup-substitutions'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.feature('Bytesplan'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  key: const Key('lineup-substitution-add'),
                  onPressed: canAdd ? () => _add(context) : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(strings.feature('Planerat byte')),
                ),
              ],
            ),
            if (plan.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  strings.feature(
                    canAdd
                        ? 'Inga planerade byten.'
                        : 'Välj startspelare och avbytare för att planera byten.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final sub in plan)
              ListTile(
                key: Key('lineup-substitution-${sub.id}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  child: Text(
                    sub.minute == null ? '–' : "${sub.minute}'",
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text.rich(
                  TextSpan(
                    children: [
                      const WidgetSpan(
                        child: Icon(
                          Icons.arrow_downward,
                          size: 16,
                          color: Colors.red,
                        ),
                      ),
                      TextSpan(text: ' ${_name(sub.outId)}   '),
                      const WidgetSpan(
                        child: Icon(
                          Icons.arrow_upward,
                          size: 16,
                          color: Colors.green,
                        ),
                      ),
                      TextSpan(text: ' ${_name(sub.inId)}'),
                    ],
                  ),
                ),
                subtitle: sub.note.isEmpty ? null : Text(sub.note),
                trailing: IconButton(
                  tooltip: strings.feature('Ta bort'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onChanged([
                    for (final item in plan)
                      if (item.id != sub.id) item,
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubstitutionDialog extends StatefulWidget {
  const _SubstitutionDialog({
    required this.people,
    required this.outOptions,
    required this.inOptions,
  });
  final Map<String, LineupPlayer> people;
  final List<String> outOptions, inOptions;

  @override
  State<_SubstitutionDialog> createState() => _SubstitutionDialogState();
}

class _SubstitutionDialogState extends State<_SubstitutionDialog> {
  late String _out = widget.outOptions.first;
  late String _in = widget.inOptions.firstWhere(
    (id) => id != _out,
    orElse: () => widget.inOptions.first,
  );
  final _minute = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _minute.dispose();
    _note.dispose();
    super.dispose();
  }

  DropdownMenuItem<String> _item(String id) =>
      DropdownMenuItem(value: id, child: Text(widget.people[id]?.name ?? '?'));

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final minute = int.tryParse(_minute.text.trim());
    final validMinute =
        _minute.text.trim().isEmpty || (minute != null && minute <= 300);
    return AlertDialog(
      title: Text(strings.feature('Planerat byte')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('substitution-out'),
              initialValue: _out,
              decoration: InputDecoration(labelText: strings.feature('Ut')),
              items: [for (final id in widget.outOptions) _item(id)],
              onChanged: (value) => setState(() => _out = value ?? _out),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('substitution-in'),
              initialValue: _in,
              decoration: InputDecoration(labelText: strings.feature('In')),
              items: [for (final id in widget.inOptions) _item(id)],
              onChanged: (value) => setState(() => _in = value ?? _in),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('substitution-minute'),
              controller: _minute,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: strings.feature('Minut (frivilligt)'),
                errorText: validMinute
                    ? null
                    : strings.feature('Ange en minut mellan 0 och 300.'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('substitution-note'),
              controller: _note,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: strings.feature('Anteckning (frivilligt)'),
                hintText: strings.feature(
                  'T.ex. vid trötthet eller om vi leder',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          key: const Key('substitution-save'),
          onPressed: _out == _in || !validMinute
              ? null
              : () => Navigator.pop(
                  context,
                  PlannedSubstitution(
                    id: _newUuid(),
                    outId: _out,
                    inId: _in,
                    minute: minute,
                    note: _note.text.trim(),
                  ),
                ),
          child: Text(strings.feature('Lägg till')),
        ),
      ],
    );
  }
}
