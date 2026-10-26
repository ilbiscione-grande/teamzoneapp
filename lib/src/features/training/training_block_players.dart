part of '../../app/teamzone_app.dart';

Color _trainingPlayerColor(TrainingPlayerTeam team) => switch (team) {
  TrainingPlayerTeam.blue => Colors.blue.shade800,
  TrainingPlayerTeam.red => Colors.red.shade800,
  TrainingPlayerTeam.green => Colors.green.shade800,
  TrainingPlayerTeam.yellow => Colors.amber.shade800,
  TrainingPlayerTeam.neutral => Colors.grey.shade700,
};

/// Assignments belong to this exercise, independently of event callups.
class _TrainingBlockPlayers extends StatelessWidget {
  const _TrainingBlockPlayers({
    super.key,
    required this.players,
    required this.roster,
    required this.onRetry,
    this.onChanged,
  });
  final List<TrainingBlockPlayer> players;
  final Future<List<EventRosterPerson>>? roster;
  final VoidCallback onRetry;
  final ValueChanged<List<TrainingBlockPlayer>>? onChanged;

  Future<void> _pickRoster(
    BuildContext context,
    List<EventRosterPerson> people,
  ) async {
    final picked = await showDialog<List<TrainingBlockPlayer>>(
      context: context,
      builder: (_) => _TrainingRosterPicker(
        people: people
            .where(
              (person) =>
                  !players.any((player) => player.personId == person.personId),
            )
            .toList(),
        limit: 80 - players.length,
      ),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    onChanged?.call([...players, ...picked]);
  }

  @override
  Widget build(BuildContext context) {
    if (onChanged == null && players.isEmpty) return const SizedBox.shrink();
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.feature('Spelare i övningen'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (onChanged != null) ...[
            Text(
              strings.feature(
                'Indelningen gäller bara den här övningen och ändrar inte kallelserna.',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('training-player-add-anonymous'),
                  onPressed: players.length < 80
                      ? () => onChanged!([
                          ...players,
                          const TrainingBlockPlayer(),
                        ])
                      : null,
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(strings.feature('Ospecificerad spelare')),
                ),
                FutureBuilder<List<EventRosterPerson>>(
                  future: roster,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return TextButton(
                        onPressed: onRetry,
                        child: Text(
                          strings.feature(
                            'Truppen kunde inte hämtas. Försök igen.',
                          ),
                        ),
                      );
                    }
                    return OutlinedButton.icon(
                      key: const Key('training-player-add-roster'),
                      onPressed: snapshot.hasData && players.length < 80
                          ? () => _pickRoster(context, snapshot.data!)
                          : null,
                      icon: const Icon(Icons.groups_outlined),
                      label: Text(strings.feature('Från truppen')),
                    );
                  },
                ),
              ],
            ),
          ],
          for (var i = 0; i < players.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: _trainingPlayerColor(players[i].team),
                    child: const Icon(
                      Icons.person,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      players[i].personId == null
                          ? strings.formatFeature('Spelare {number}', {
                              'number':
                                  '${players.take(i + 1).where((player) => player.personId == null).length}',
                            })
                          : players[i].name,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onChanged == null)
                    Text(strings.feature(players[i].team.label))
                  else ...[
                    DropdownButton<TrainingPlayerTeam>(
                      key: ValueKey('training-player-team-$i'),
                      value: players[i].team,
                      items: [
                        for (final team in TrainingPlayerTeam.values)
                          DropdownMenuItem(
                            value: team,
                            child: Text(strings.feature(team.label)),
                          ),
                      ],
                      onChanged: (team) {
                        if (team == null) return;
                        onChanged!(
                          [...players]..[i] = players[i].withTeam(team),
                        );
                      },
                    ),
                    IconButton(
                      key: ValueKey('training-player-remove-$i'),
                      tooltip: strings.feature('Ta bort spelare'),
                      onPressed: () => onChanged!([...players]..removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ],
              ),
            ),
          if (players.length >= 80)
            Text(strings.feature('Högst 80 spelare per övning.')),
        ],
      ),
    );
  }
}

class _TrainingRosterPicker extends StatefulWidget {
  const _TrainingRosterPicker({required this.people, required this.limit});
  final List<EventRosterPerson> people;
  final int limit;
  @override
  State<_TrainingRosterPicker> createState() => _TrainingRosterPickerState();
}

class _TrainingRosterPickerState extends State<_TrainingRosterPicker> {
  final Set<String> _selected = {};
  final Map<String, TrainingPlayerTeam> _teams = {};
  String _query = '';

  int _group(EventRosterPerson person) {
    if (person.callupId == null || person.callupState == 'cancelled') return 3;
    return switch (person.callupState) {
      'accepted' => 0,
      'declined' => 2,
      _ => 1,
    };
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final people = widget.people
        .where(
          (person) => person.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: Text(strings.feature('Från truppen')),
      content: SizedBox(
        width: 560,
        height: 360,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: strings.feature('Sök spelare'),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: people.isEmpty
                  ? Center(
                      child: Text(
                        strings.feature('Inga fler spelare att lägga till.'),
                      ),
                    )
                  : ListView(
                      children: [
                        for (var group = 0; group < 4; group++)
                          if (people.any(
                            (person) => _group(person) == group,
                          )) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                              child: Text(
                                strings.feature(switch (group) {
                                  0 => 'Kallade – accepterat',
                                  1 => 'Kallade – obesvarat',
                                  2 => 'Kallade – nekat',
                                  _ => 'Okallade spelare',
                                }),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            for (final person in people.where(
                              (person) => _group(person) == group,
                            ))
                              Row(
                                children: [
                                  Expanded(
                                    child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      title: Text(person.name),
                                      value: _selected.contains(
                                        person.personId,
                                      ),
                                      onChanged:
                                          !_selected.contains(
                                                person.personId,
                                              ) &&
                                              _selected.length >= widget.limit
                                          ? null
                                          : (value) => setState(() {
                                              if (value == true) {
                                                _selected.add(person.personId);
                                              } else {
                                                _selected.remove(
                                                  person.personId,
                                                );
                                              }
                                            }),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  DropdownButton<TrainingPlayerTeam>(
                                    key: ValueKey(
                                      'training-roster-team-${person.personId}',
                                    ),
                                    value:
                                        _teams[person.personId] ??
                                        TrainingPlayerTeam.blue,
                                    items: [
                                      for (final team
                                          in TrainingPlayerTeam.values)
                                        DropdownMenuItem(
                                          value: team,
                                          child: Text(
                                            strings.feature(team.label),
                                          ),
                                        ),
                                    ],
                                    onChanged:
                                        !_selected.contains(person.personId)
                                        ? null
                                        : (team) {
                                            if (team != null) {
                                              setState(
                                                () => _teams[person.personId] =
                                                    team,
                                              );
                                            }
                                          },
                                  ),
                                ],
                              ),
                          ],
                      ],
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
          key: const Key('training-player-roster-confirm'),
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.people
                      .where((person) => _selected.contains(person.personId))
                      .map(
                        (person) => TrainingBlockPlayer(
                          personId: person.personId,
                          name: person.name,
                          team:
                              _teams[person.personId] ??
                              TrainingPlayerTeam.blue,
                        ),
                      )
                      .toList(),
                ),
          child: Text(strings.feature('Lägg till')),
        ),
      ],
    );
  }
}
