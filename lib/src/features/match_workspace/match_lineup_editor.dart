part of '../../app/teamzone_app.dart';

/// Uppställning in the Match module: the formation for the team's match
/// format, the players on the pitch, the bench and the substitution plan.
/// It is the event's own line-up, the one under Förberedelser too.
class _MatchLineupEditor extends StatefulWidget {
  const _MatchLineupEditor({required this.eventId, required this.calendar});
  final String eventId;
  final CalendarServices calendar;

  @override
  State<_MatchLineupEditor> createState() => _MatchLineupEditorState();
}

class _MatchLineupEditorState extends State<_MatchLineupEditor> {
  MatchLineup? _lineup;
  Object? _error;
  bool _loaded = false, _busy = false, _dirty = false, _published = false;
  String _formation = '';
  final _slots = <String, String>{};
  final _places = <String, Offset>{};
  final _bench = <String>[];
  final _plan = <PlannedSubstitution>[];

  /// Everyone who can be chosen, by person, and their answer for the match.
  final _people = <String, LineupPlayer>{};
  final _answers = <String, String?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lineup = await widget.calendar.matchPlans.getLineup(widget.eventId);
      SquadDetails? squad;
      if (lineup?.canEdit == true) {
        squad = await widget.calendar
            .getEventSquad(widget.eventId)
            .then<SquadDetails?>((value) => value, onError: (_) => null);
      }
      if (!mounted) return;
      setState(() => _apply(lineup, squad));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _apply(MatchLineup? lineup, SquadDetails? squad) {
    _lineup = lineup;
    _loaded = true;
    _error = null;
    _dirty = false;
    _slots.clear();
    _places.clear();
    _bench.clear();
    _plan.clear();
    _people.clear();
    _answers.clear();
    if (lineup == null) return;
    for (final player in lineup.players) {
      _people[player.personId] = player;
    }
    for (final person in squad?.roster ?? const <EventRosterPerson>[]) {
      if (person.rolePackage != 'player') continue;
      _people.putIfAbsent(
        person.personId,
        () => LineupPlayer(personId: person.personId, name: person.name),
      );
      _answers[person.personId] = person.isCalled
          ? (person.callupState ?? 'pending')
          : null;
    }
    for (final starter in lineup.starters) {
      _people.putIfAbsent(
        starter.personId,
        () => LineupPlayer(
          personId: starter.personId,
          name: starter.name,
          number: starter.number,
        ),
      );
    }
    for (final sub in lineup.substitutes) {
      _people.putIfAbsent(sub.personId, () => sub);
    }
    final formations = formationsFor(lineup.matchFormat);
    _formation = formations.contains(lineup.formation)
        ? lineup.formation!
        : formations.first;
    final slots = formationSlots(_formation, lineup.matchFormat);
    final codes = {for (final slot in slots) slot.code};
    final unplaced = <String>[];
    for (final starter in lineup.starters) {
      final slot = starter.slot;
      if (slot != null && codes.contains(slot) && !_slots.containsKey(slot)) {
        _slots[slot] = starter.personId;
        if (starter.x != null && starter.y != null) {
          _places[slot] = Offset(starter.x!, starter.y!);
        }
      } else {
        unplaced.add(starter.personId);
      }
    }
    // Starters chosen under Förberedelser get places by their positions.
    _slots.addAll(autoFill(slots, _slots, _candidates(unplaced)));
    _bench.addAll(lineup.substitutes.map((sub) => sub.personId));
    _plan.addAll(lineup.plan);
    _published = lineup.published;
  }

  List<({String personId, String? main, List<String> positions})> _candidates(
    Iterable<String> ids,
  ) => [
    for (final id in ids)
      (
        personId: id,
        main: _people[id]?.mainPosition,
        positions: _people[id]?.positions ?? const [],
      ),
  ];

  /// Who to choose from: accepted first, then the called, then the rest,
  /// those who declined last.
  List<LineupPlayer> get _choosable {
    int rank(String id) => switch (_answers[id]) {
      'accepted' => 0,
      'declined' => 3,
      null => 2,
      _ => 1,
    };
    return _people.values.toList()..sort((a, b) {
      final byRank = rank(a.personId).compareTo(rank(b.personId));
      if (byRank != 0) return byRank;
      final byNumber = (a.number ?? 999).compareTo(b.number ?? 999);
      return byNumber != 0 ? byNumber : a.name.compareTo(b.name);
    });
  }

  String? get _format => _lineup?.matchFormat;
  List<FormationSlot> get _formationSlots =>
      formationSlots(_formation, _format);

  void _edit(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  void _changeFormation(String formation) => _edit(() {
    final slots = formationSlots(formation, _format);
    final placed = [
      for (final slot in _formationSlots)
        if (_slots[slot.code] != null) _slots[slot.code]!,
    ];
    _formation = formation;
    _slots.clear();
    _places.clear();
    _slots.addAll(autoFill(slots, const {}, _candidates(placed)));
  });

  void _autoFill() => _edit(() {
    final taken = {..._slots.values, ..._bench};
    final free = _choosable
        .where((p) => !taken.contains(p.personId))
        .where((p) => _answers[p.personId] != 'declined')
        .map((p) => p.personId);
    _slots.addAll(autoFill(_formationSlots, _slots, _candidates(free)));
  });

  void _place(String slot, String? personId) => _edit(() {
    if (personId == null) {
      _slots.remove(slot);
      _places.remove(slot);
      return;
    }
    _slots.removeWhere((_, id) => id == personId);
    _bench.remove(personId);
    _slots[slot] = personId;
  });

  Future<void> _chooseFor(FormationSlot slot) async {
    final strings = AppStrings.of(context);
    final current = _slots[slot.code];
    final chosen = await _pickPlayer(
      title: '${strings.feature('Välj spelare')} · ${slot.label}',
      exclude: const {},
      current: current,
      group: slot.group,
    );
    if (chosen == null) return;
    _place(slot.code, chosen.isEmpty ? null : chosen);
  }

  Future<void> _addToBench() async {
    final chosen = await _pickPlayer(
      title: AppStrings.of(context).feature('Lägg till avbytare'),
      exclude: {..._slots.values, ..._bench},
    );
    if (chosen == null || chosen.isEmpty) return;
    _edit(() => _bench.add(chosen));
  }

  /// The chosen person, '' to empty the slot, null when cancelled.
  Future<String?> _pickPlayer({
    required String title,
    required Set<String> exclude,
    String? current,
    String? group,
  }) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _PlayerPickerSheet(
      title: title,
      players: _choosable.where((p) => !exclude.contains(p.personId)).toList(),
      answers: _answers,
      placedIn: {
        for (final entry in _slots.entries)
          entry.value: _formationSlots
              .firstWhere((slot) => slot.code == entry.key)
              .label,
        for (final id in _bench) id: AppStrings.of(context).feature('Bänk'),
      },
      current: current,
      group: group,
    ),
  );

  Future<void> _save() async {
    final lineup = _lineup;
    if (lineup == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      await widget.calendar.matchPlans.saveLineup(
        eventId: widget.eventId,
        expectedRevision: lineup.revision,
        formation: _formation,
        starters: [
          for (final slot in _formationSlots)
            if (_slots[slot.code] case final id?)
              LineupStarter(
                personId: id,
                name: '',
                slot: slot.code,
                position: slot.label,
                x: (_places[slot.code]?.dx ?? slot.x),
                y: (_places[slot.code]?.dy ?? slot.y),
              ),
        ],
        substitutes: _bench,
        plan: _plan,
        published: _published,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Uppställningen är sparad.'))),
      );
      await _load();
    } on MatchPlanConflict {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Någon annan har ändrat uppställningen. Den senaste versionen visas nu.',
            ),
          ),
        ),
      );
      await _load();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.feature('Uppställningen kunde inte sparas.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (_error != null) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: Text(
            strings.feature('Uppställningen kunde inte hämtas. Försök igen.'),
          ),
        ),
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final lineup = _lineup;
    if (lineup == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            strings.feature('Uppställningen är inte publicerad än.'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final edit = lineup.canEdit;
    final slots = _formationSlots;
    final onPitch = _slots.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: edit
                  ? DropdownButtonFormField<String>(
                      key: const Key('lineup-formation'),
                      initialValue: _formation,
                      decoration: InputDecoration(
                        labelText:
                            '${strings.feature('Formation')} · ${_format ?? '11v11'}',
                        isDense: true,
                      ),
                      items: [
                        for (final formation in formationsFor(_format))
                          DropdownMenuItem(
                            value: formation,
                            child: Text(formation),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null && value != _formation) {
                          _changeFormation(value);
                        }
                      },
                    )
                  : Text(
                      '${strings.feature('Formation')} $_formation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
            ),
            if (edit) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('lineup-autofill'),
                onPressed: onPitch >= slots.length ? null : _autoFill,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(strings.feature('Fyll i')),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (edit)
          Text(
            '$onPitch/${slots.length} ${strings.feature('på planen')} · '
            '${strings.feature('tryck för att välja spelare, dra för att flytta')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        _LineupPitch(
          edit: edit,
          spots: [
            for (final slot in slots)
              (
                slot: slot,
                place: _places[slot.code] ?? Offset(slot.x, slot.y),
                player: _people[_slots[slot.code]],
              ),
          ],
          onTap: _chooseFor,
          onMoved: (slot, place) => _edit(() => _places[slot.code] = place),
        ),
        const SizedBox(height: 16),
        _BenchCard(
          players: [for (final id in _bench) ?_people[id]],
          edit: edit,
          onAdd: _addToBench,
          onRemove: (id) => _edit(() {
            _bench.remove(id);
            _plan.removeWhere((sub) => sub.outId == id || sub.inId == id);
          }),
        ),
        if (edit) ...[
          const SizedBox(height: 12),
          _SubstitutionPlanCard(
            plan: _plan,
            people: _people,
            onPitch: [for (final slot in slots) ?_slots[slot.code]],
            bench: _bench,
            onChanged: (plan) => _edit(() {
              _plan
                ..clear()
                ..addAll(plan);
            }),
          ),
          SwitchListTile(
            key: const Key('lineup-published'),
            contentPadding: EdgeInsets.zero,
            value: _published,
            onChanged: (value) => _edit(() => _published = value),
            title: Text(strings.feature('Visa uppställningen för spelarna')),
            subtitle: Text(strings.feature('Bytesplanen ser bara ledarna.')),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('lineup-save'),
            onPressed: _busy || !_dirty ? null : _save,
            child: Text(
              strings.feature(_busy ? 'Sparar…' : 'Spara uppställningen'),
            ),
          ),
        ],
      ],
    );
  }
}
