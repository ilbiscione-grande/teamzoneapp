part of '../../app/teamzone_app.dart';

/// One training's session: its theme and goal, the blocks of the warm-up,
/// main part and finish in order, how the minutes fit the training, and
/// whether the players see it. Edited locally and saved whole; who may not
/// edit reads the published session.
class _TrainingSessionPage extends StatefulWidget {
  const _TrainingSessionPage({required this.eventId, required this.calendar});
  final String eventId;
  final CalendarServices calendar;

  TrainingServices get services => calendar.trainingSessions;

  @override
  State<_TrainingSessionPage> createState() => _TrainingSessionPageState();
}

class _TrainingSessionPageState extends State<_TrainingSessionPage> {
  final _theme = TextEditingController();
  // The old free-text goal, saved back as loaded: goals are now the list
  // in the preparation ("Mål för träningen").
  final _goal = TextEditingController();
  TrainingSession? _session;
  List<TrainingBlock> _blocks = const [];
  bool _published = false, _dirty = false, _busy = false, _missing = false;
  Object? _error;
  int? _selectedBlock;
  int _view = 0;
  List<TrainingBlockPlayer> _sessionPlayers = const [];

  Future<void> _guide() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final draft = await showDialog<(String, List<TrainingBlock>)>(
      context: context,
      builder: (_) => _TrainingGuide(
        focus: _theme.text,
        minutes: session.eventMinutes,
        hasBlocks: _blocks.isNotEmpty,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    _edit(() {
      _theme.text = draft.$1;
      _blocks = draft.$2;
      _editorRevision++;
      _selectedBlock = null;
    });
  }

  late final Future<TeamPlanSuggestion?> _suggestion =
      widget.services is TeamPlanSuggestionServices
      ? (widget.services as TeamPlanSuggestionServices)
            .teamPlanSuggestion(widget.eventId)
            .catchError((Object error) {
              AppErrors.caught('training_session._suggestion', error);
              return null;
            })
      : Future.value(null);

  late Future<(EventDetails, SquadDetails)> _event = _loadEvent();
  late Future<List<EventRosterPerson>> _playerRoster = _loadPlayerRoster();

  Future<List<EventRosterPerson>> _loadPlayerRoster() async {
    final squad = await widget.calendar.getEventSquad(widget.eventId);
    final people = <String, EventRosterPerson>{
      for (final person in squad.roster)
        if (person.rolePackage == 'player') person.personId: person,
    }.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return people;
  }

  Widget _playersFor(int index, bool canEdit) => _TrainingBlockPlayers(
    key: ValueKey('training-players-$index'),
    players: _blocks[index].players,
    roster: canEdit ? _sessionCandidates() : null,
    onManageRoster: () => setState(() => _view = 0),
    onRetry: () => setState(() => _playerRoster = _loadPlayerRoster()),
    onChanged: canEdit
        ? (players) =>
              _updateExercise(index, _blocks[index].copyWith(players: players))
        : null,
  );

  late Future<EventPreparation> _overviewPreparation = widget
      .calendar
      .preparation
      .getPreparation(widget.eventId);
  late Future<EventFollowup> _overviewGoals = widget.calendar.preparation
      .getFollowup(widget.eventId);

  Future<List<EventRosterPerson>> _sessionCandidates() async {
    final people = await _playerRoster;
    if (!mounted) return const [];
    return [
      for (var i = 0; i < _sessionPlayers.length; i++)
        if (_sessionPlayers[i].personId == null)
          EventRosterPerson(
            personId: _sessionPlayers[i].id,
            name: AppStrings.of(context).formatFeature('Spelare {number}', {
              'number':
                  '${_sessionPlayers.take(i + 1).where((player) => player.personId == null).length}',
            }),
            teamId: '',
            teamName: '',
            rolePackage: 'anonymous',
            inDraft: false,
          )
        else if (people.any(
          (person) => person.personId == _sessionPlayers[i].personId,
        ))
          people.firstWhere(
            (person) => person.personId == _sessionPlayers[i].personId,
          ),
    ];
  }

  Future<void> _changeSessionRoster(List<TrainingBlockPlayer> players) async {
    final ids = players.map((player) => player.id).toSet();
    final removesAssigned = _blocks.any(
      (block) => block.players.any((player) => !ids.contains(player.id)),
    );
    if (removesAssigned) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            AppStrings.of(context).feature('Ta bort från sessionstruppen?'),
          ),
          content: Text(
            AppStrings.of(
              context,
            ).feature('Spelaren tas också bort från övningar där den används.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStrings.of(context).feature('Ta bort')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    _edit(() {
      _sessionPlayers = players;
      _blocks = [
        for (final block in _blocks)
          block.copyWith(
            players: block.players
                .where((player) => ids.contains(player.id))
                .toList(),
          ),
      ];
    });
  }

  Widget _dashboard(TrainingSession session) => _TrainingSessionOverview(
    session: session,
    blocks: _blocks,
    theme: _theme,
    published: _published,
    event: _event,
    preparation: _overviewPreparation,
    goals: _overviewGoals,
    onRetry: () => setState(() {
      _event = _loadEvent();
      _overviewPreparation = widget.calendar.preparation.getPreparation(
        widget.eventId,
      );
      _overviewGoals = widget.calendar.preparation.getFollowup(widget.eventId);
    }),
    evaluation: !session.startsAt.isAfter(DateTime.now())
        ? _TrainingEvaluationSection(
            eventId: session.eventId,
            services: widget.services,
            blockTitles: [for (final block in session.blocks) block.title],
          )
        : null,
    onPlanning: () => setState(() => _view = 1),
    onPreparation: () => setState(() => _view = 2),
    onPublished: (value) => _edit(() => _published = value),
    rosterEditor: _TrainingBlockPlayers(
      key: const Key('training-session-roster'),
      isSessionRoster: true,
      players: _sessionPlayers,
      roster: _playerRoster,
      onRetry: () => setState(() => _playerRoster = _loadPlayerRoster()),
      onChanged: _changeSessionRoster,
    ),
  );

  Future<(EventDetails, SquadDetails)> _loadEvent() async => (
    await widget.calendar.getEventDetails(widget.eventId),
    await widget.calendar.getEventSquad(widget.eventId),
  );

  @override
  void initState() {
    super.initState();
    _load();
    for (final controller in [_theme, _goal]) {
      controller.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    _theme.dispose();
    _goal.dispose();
    super.dispose();
  }

  bool _settingText = false;
  void _markDirty() {
    if (!_settingText && !_dirty && mounted) setState(() => _dirty = true);
  }

  void _show(TrainingSession session) {
    _settingText = true;
    _theme.text = session.theme;
    _goal.text = session.goal;
    _settingText = false;
    _editorRevision++;
    _session = session;
    _sessionPlayers = [...session.roster];
    _blocks = [...session.blocks];
    _published = session.published;
    _dirty = false;
  }

  Future<void> _load() async {
    try {
      final session = await widget.services.getSession(widget.eventId);
      if (!mounted) {
        return;
      }
      setState(() {
        _error = null;
        _missing = session == null;
        if (session != null) _show(session);
      });
    } catch (error) {
      AppErrors.caught('training_session._load', error);
      if (mounted) setState(() => _error = error);
    }
  }

  void _edit(void Function() change) => setState(() {
    change();
    _dirty = true;
  });

  Future<void> _save() async {
    final strings = AppStrings.of(context);
    final session = _session;
    if (session == null || _busy) {
      return;
    }
    if (!(_workspaceForm.currentState?.validate() ?? true)) {
      return;
    }
    if (_blocks.any((block) => block.title.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.feature('Ange ett namn på övningen.'))),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final saved = await widget.services.saveSession(
        eventId: session.eventId,
        expectedRevision: session.revision,
        theme: _theme.text.trim(),
        goal: _goal.text.trim(),
        published: _published,
        blocks: _blocks,
        roster: _sessionPlayers,
      );
      if (!mounted) {
        return;
      }
      setState(() => _show(saved));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved.published
                ? strings.feature('Passet är sparat och visas för spelarna.')
                : strings.feature('Passet är sparat. Bara ledarna ser det.'),
          ),
        ),
      );
    } on TrainingSessionConflict {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Passet har ändrats av någon annan. Det senaste visas nu, gör dina ändringar igen.',
            ),
          ),
        ),
      );
      await _load();
    } catch (error) {
      AppErrors.caught('training_session._save', error);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Passet kunde inte sparas.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Lämna utan att spara?')),
        content: Text(
          AppStrings.of(
            context,
          ).feature('Dina ändringar i passet sparas inte.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).feature('Stanna')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).feature('Lämna')),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _editBlock({int? index, TrainingPart? part}) async {
    final result = await _TrainingBlockDialog.show(
      context,
      block: index == null ? null : _blocks[index],
      part: part,
    );
    if (result == null || !mounted) {
      return;
    }
    _edit(() {
      final blocks = [..._blocks];
      switch (result) {
        case (_, true):
          blocks.removeAt(index!);
        case (final block?, false) when index != null:
          blocks[index] = block;
        case (final block?, false):
          // A new block goes last in its part.
          final last = blocks.lastIndexWhere(
            (b) => b.part.index <= block.part.index,
          );
          blocks.insert(last + 1, block);
        default:
      }
      _blocks = _ordered(blocks);
      _editorRevision++;
      _selectedBlock = null;
    });
  }

  /// Parts in their order, the blocks' order within each kept.
  static List<TrainingBlock> _ordered(List<TrainingBlock> blocks) => [
    for (final part in TrainingPart.values)
      for (final block in blocks)
        if (block.part == part) block,
  ];

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _blocks.length) {
      return;
    }
    if (_blocks[target].part != _blocks[index].part) {
      return;
    }
    _edit(() {
      final blocks = [..._blocks];
      final block = blocks.removeAt(index);
      blocks.insert(target, block);
      _blocks = blocks;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final canEdit = session?.canEdit == true;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) {
          return;
        }
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) {
          _dirty = false;
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppStrings.of(context).feature('Träningspass')),
          actions: [
            if (canEdit)
              IconButton(
                key: const Key('training-guide-open'),
                tooltip: AppStrings.of(context).feature('Guidad planering'),
                onPressed: _busy ? null : _guide,
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            if (canEdit)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  key: const Key('training-session-save'),
                  onPressed: (_dirty || !session!.rosterSaved) && !_busy
                      ? _save
                      : null,
                  child: Text(
                    _busy
                        ? AppStrings.of(context).feature('Sparar…')
                        : AppStrings.of(context).feature('Spara'),
                  ),
                ),
              ),
          ],
        ),
        body: session != null && canEdit
            ? Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: Text(
                              AppStrings.of(context).feature('Översikt'),
                            ),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(
                              AppStrings.of(context).feature('Planering'),
                            ),
                          ),
                          ButtonSegment(
                            value: 2,
                            label: Text(
                              AppStrings.of(context).feature('Förberedelser'),
                            ),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (value) {
                          if (_workspaceForm.currentState?.validate() ?? true) {
                            setState(() => _view = value.single);
                          }
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _view == 0
                        ? _dashboard(session)
                        : _view == 2
                        ? _body(session)
                        : LayoutBuilder(
                            builder: (context, constraints) =>
                                constraints.maxWidth < 1200
                                ? _body(session)
                                : _program(session),
                          ),
                  ),
                ],
              )
            : _body(session),
      ),
    );
  }

  final _workspaceForm = GlobalKey<FormState>();
  int _editorRevision = 0;

  void _selectExercise(int index) {
    if (!(_workspaceForm.currentState?.validate() ?? true)) {
      return;
    }
    setState(() => _selectedBlock = index);
  }

  void _updateExercise(int index, TrainingBlock block) {
    _edit(() => _blocks = [..._blocks]..[index] = block);
  }

  Widget _program(TrainingSession session) {
    final strings = AppStrings.of(context);
    final selected = _selectedBlock != null && _selectedBlock! < _blocks.length
        ? _selectedBlock
        : (_blocks.isEmpty ? null : 0);
    final block = selected == null ? null : _blocks[selected];
    final colors = Theme.of(context).colorScheme;
    final minutes = _blocks.fold(0, (sum, b) => sum + b.minutes);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                strings.feature(
                  (_dirty || !session.rosterSaved)
                      ? 'Osparade ändringar'
                      : 'Sparat',
                ),
              ),
              const SizedBox(width: 12),
              Text(strings.feature('Visa passet för spelarna')),
              Switch(
                key: const Key('training-program-published'),
                value: _published,
                onChanged: (value) => _edit(() => _published = value),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: _workspaceForm,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 200,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Text(
                        strings.feature('Passets delar'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final part in TrainingPart.values) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(strings.feature(part.label)),
                          trailing: IconButton(
                            tooltip: strings.feature('Lägg till övning'),
                            onPressed: () => _editBlock(part: part),
                            icon: const Icon(Icons.add),
                          ),
                        ),
                        for (var i = 0; i < _blocks.length; i++)
                          if (_blocks[i].part == part)
                            ListTile(
                              selected: selected == i,
                              title: Text(_blocks[i].title),
                              subtitle: Text('${_blocks[i].minutes} min'),
                              onTap: () => _selectExercise(i),
                            ),
                      ],
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ColoredBox(
                    color: colors.surfaceContainerLowest,
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        TextField(
                          controller: _theme,
                          maxLength: 200,
                          decoration: InputDecoration(
                            labelText: strings.feature('Träningsfokus'),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                strings.feature('Tidslinje'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              strings.trainingMinutes(
                                minutes,
                                session.eventMinutes,
                                planned: true,
                              ),
                              style: TextStyle(
                                color:
                                    session.eventMinutes > 0 &&
                                        minutes > session.eventMinutes
                                    ? colors.error
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final length =
                                (minutes > session.eventMinutes
                                        ? minutes
                                        : session.eventMinutes)
                                    .clamp(1, 1440);
                            final scale = ((constraints.maxWidth - 32) / length)
                                .clamp(8.0, double.infinity);
                            final width = length * scale;
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: width + 32,
                                height: 132,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: 0,
                                      top: 94,
                                      width: width,
                                      child: Container(
                                        height: 2,
                                        color:
                                            minutes > session.eventMinutes &&
                                                session.eventMinutes > 0
                                            ? colors.error
                                            : colors.outline,
                                      ),
                                    ),
                                    for (
                                      var minute = 0;
                                      minute <= length;
                                      minute += 15
                                    ) ...[
                                      Positioned(
                                        left: minute * scale,
                                        top: 94,
                                        child: Container(
                                          width: 1,
                                          height: 7,
                                          color: colors.outline,
                                        ),
                                      ),
                                      Positioned(
                                        left: (minute * scale - 15).clamp(
                                          0.0,
                                          width,
                                        ),
                                        top: 105,
                                        child: SizedBox(
                                          width: 30,
                                          child: Text(
                                            '$minute',
                                            textAlign: minute == 0
                                                ? TextAlign.left
                                                : TextAlign.center,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelMedium,
                                          ),
                                        ),
                                      ),
                                    ],
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      width: width,
                                      height: 94,
                                      child: ReorderableListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        buildDefaultDragHandles: false,
                                        itemCount: _blocks.length,
                                        onReorderItem: (oldIndex, newIndex) {
                                          if (!(_workspaceForm.currentState
                                                  ?.validate() ??
                                              true)) {
                                            return;
                                          }
                                          final item = _blocks[oldIndex];
                                          final items = [..._blocks]
                                            ..removeAt(oldIndex);
                                          items.insert(newIndex, item);
                                          if (newIndex > 0 &&
                                              items[newIndex - 1].part.index >
                                                  item.part.index) {
                                            return;
                                          }
                                          if (newIndex + 1 < items.length &&
                                              items[newIndex + 1].part.index <
                                                  item.part.index) {
                                            return;
                                          }
                                          _edit(() {
                                            _blocks = items;
                                            _selectedBlock = newIndex;
                                            _editorRevision++;
                                          });
                                        },
                                        itemBuilder: (context, i) {
                                          final item = _blocks[i];
                                          final start = _blocks
                                              .take(i)
                                              .fold(
                                                0,
                                                (sum, b) => sum + b.minutes,
                                              );
                                          return SizedBox(
                                            key: ObjectKey(item),
                                            width: item.minutes * scale,
                                            child: Tooltip(
                                              message:
                                                  '${item.title} · $start–${start + item.minutes} min',
                                              child: Card(
                                                margin: const EdgeInsets.only(
                                                  left: 2,
                                                  right: 2,
                                                  top: 4,
                                                ),
                                                color: selected == i
                                                    ? colors.secondaryContainer
                                                    : colors
                                                          .surfaceContainerHigh,
                                                child: InkWell(
                                                  onTap: () =>
                                                      _selectExercise(i),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            item.title,
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        Text(
                                                          '$start–${start + item.minutes} min',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .labelSmall,
                                                        ),
                                                        SizedBox(
                                                          height: 24,
                                                          child: Align(
                                                            alignment: Alignment
                                                                .centerRight,
                                                            child: ReorderableDragStartListener(
                                                              index: i,
                                                              child: const SizedBox(
                                                                width: 24,
                                                                height: 24,
                                                                child: Icon(
                                                                  Icons
                                                                      .drag_indicator,
                                                                  size: 18,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        if (block == null) ...[
                          Text(strings.feature('Inga övningar än.')),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _guide,
                            child: Text(strings.feature('Guidad planering')),
                          ),
                        ] else ...[
                          Text(
                            strings.feature('Övning'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: ValueKey(
                              'workspace-title-$_editorRevision-$selected',
                            ),
                            initialValue: block.title,
                            maxLength: 120,
                            decoration: InputDecoration(
                              labelText: strings.feature('Övning'),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? strings.feature('Ange ett namn på övningen.')
                                : null,
                            onChanged: (value) => _updateExercise(
                              selected!,
                              _blocks[selected].copyWith(title: value),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _playersFor(selected!, true),
                          TextFormField(
                            key: ValueKey(
                              'workspace-organisation-$_editorRevision-$selected',
                            ),
                            initialValue: block.organisation,
                            minLines: 5,
                            maxLines: 12,
                            maxLength: 2000,
                            decoration: InputDecoration(
                              labelText: strings.feature('Organisation'),
                              hintText: strings.feature(
                                'Yta, antal spelare, regler',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) => _updateExercise(
                              selected,
                              _blocks[selected].copyWith(organisation: value),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: ValueKey(
                              'workspace-coaching-$_editorRevision-$selected',
                            ),
                            initialValue: block.coachingPoints,
                            minLines: 4,
                            maxLines: 10,
                            maxLength: 2000,
                            decoration: InputDecoration(
                              labelText: strings.feature('Coachpunkter'),
                              hintText: strings.feature(
                                'Vad ledarna lyfter under övningen',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) => _updateExercise(
                              selected,
                              _blocks[selected].copyWith(coachingPoints: value),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 220,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        strings.feature('Egenskaper'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
                      if (block == null)
                        Text(strings.feature('Välj en övning i tidslinjen.'))
                      else ...[
                        TextFormField(
                          key: ValueKey(
                            'workspace-minutes-$_editorRevision-$selected',
                          ),
                          initialValue: '${block.minutes}',
                          keyboardType: TextInputType.number,
                          maxLength: 3,
                          decoration: InputDecoration(
                            labelText: strings.feature('Minuter'),
                          ),
                          validator: (value) {
                            final number = int.tryParse(value ?? '');
                            return number == null || number < 0 || number > 240
                                ? strings.feature('Ange 0–240 minuter.')
                                : null;
                          },
                          onChanged: (value) {
                            final number = int.tryParse(value);
                            if (number != null &&
                                number >= 0 &&
                                number <= 240) {
                              _updateExercise(
                                selected!,
                                _blocks[selected].copyWith(minutes: number),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<TrainingPart>(
                          key: ValueKey(
                            'workspace-part-$_editorRevision-$selected',
                          ),
                          initialValue: block.part,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: strings.feature('Passdel'),
                          ),
                          items: [
                            for (final part in TrainingPart.values)
                              DropdownMenuItem(
                                value: part,
                                child: Text(strings.feature(part.label)),
                              ),
                          ],
                          onChanged: (part) {
                            if (part == null ||
                                !(_workspaceForm.currentState?.validate() ??
                                    true)) {
                              return;
                            }
                            final changed = block.copyWith(part: part);
                            _edit(() {
                              final items = [..._blocks]..[selected!] = changed;
                              _blocks = _ordered(items);
                              _selectedBlock = _blocks.indexOf(changed);
                              _editorRevision++;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(strings.feature('Skede som tränas (valfritt)')),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<PrincipleArea?>(
                          key: ValueKey(
                            'workspace-phase-$_editorRevision-$selected',
                          ),
                          initialValue: block.phase,
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(strings.feature('Inget skede')),
                            ),
                            for (final area in PrincipleArea.values)
                              DropdownMenuItem(
                                value: area,
                                child: Text(strings.feature(area.label)),
                              ),
                          ],
                          onChanged: (value) => _updateExercise(
                            selected!,
                            _blocks[selected].copyWith(
                              phase: value,
                              clearPhase: value == null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            IconButton(
                              tooltip: strings.feature('Flytta upp'),
                              onPressed:
                                  selected! > 0 &&
                                      _blocks[selected - 1].part == block.part
                                  ? () {
                                      if (!(_workspaceForm.currentState
                                              ?.validate() ??
                                          true)) {
                                        return;
                                      }
                                      _move(selected, -1);
                                      setState(() {
                                        _selectedBlock = selected - 1;
                                        _editorRevision++;
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.arrow_back),
                            ),
                            IconButton(
                              tooltip: strings.feature('Flytta ned'),
                              onPressed:
                                  selected < _blocks.length - 1 &&
                                      _blocks[selected + 1].part == block.part
                                  ? () {
                                      if (!(_workspaceForm.currentState
                                              ?.validate() ??
                                          true)) {
                                        return;
                                      }
                                      _move(selected, 1);
                                      setState(() {
                                        _selectedBlock = selected + 1;
                                        _editorRevision++;
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.arrow_forward),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () => _editBlock(index: selected),
                          icon: const Icon(Icons.more_horiz),
                          label: Text(strings.feature('Fler alternativ')),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A part of the session, as wide as is readable, beside the preparation's.
  Widget _part(List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  Widget _body(TrainingSession? session) {
    if (_error != null) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: Text(
            AppStrings.of(
              context,
            ).feature('Passet kunde inte hämtas. Försök igen.'),
          ),
        ),
      );
    }
    if (_missing) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            AppStrings.of(context).feature(
              'Ledarna har inte publicerat något pass för träningen än.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (session == null) {
      return Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final canEdit = session.canEdit;
    final minutes = _blocks.fold(0, (sum, b) => sum + b.minutes);
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _part([
          Text(
            _trainingDay(context, session.startsAt),
            style: theme.textTheme.labelLarge,
          ),
          Text(session.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          _TrainingMinutes(minutes: minutes, length: session.eventMinutes),
        ]),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 852),
            child: _TrainingSeasonPlan(
              suggestion: _suggestion,
              focus: _theme.text,
              onTake: canEdit
                  ? (label) async => _edit(() {
                      final text = _theme.text.trim();
                      _theme.text = text.isEmpty ? label : '$text, $label';
                    })
                  : null,
            ),
          ),
        ),
        // One focus for the session, the event's theme; its goals follow
        // as a list (the preparation's "Mål för träningen").
        _part([
          if (canEdit)
            TextField(
              key: const Key('training-session-theme'),
              controller: _theme,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).feature('Träningsfokus'),
                hintText: AppStrings.of(
                  context,
                ).feature('Till exempel press och återerövring'),
              ),
            )
          else if (session.theme.trim().isNotEmpty) ...[
            Text(
              AppStrings.of(context).feature('Träningsfokus'),
              style: theme.textTheme.labelLarge,
            ),
            Text(session.theme, style: theme.textTheme.titleMedium),
          ],
        ]),
      ],
    );
    final exercises = _part([
      Text(
        AppStrings.of(context).feature('Övningar'),
        style: theme.textTheme.titleMedium,
      ),
      if (canEdit && _blocks.isEmpty && session.eventPlan != null)
        Card(
          key: const Key('training-session-event-plan'),
          child: ListTile(
            leading: const Icon(Icons.notes),
            title: Text(
              AppStrings.of(context).feature('Träningsplanen från eventet'),
            ),
            subtitle: Text(
              session.eventPlan!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: () => _edit(
                () => _blocks = [
                  TrainingBlock(
                    part: TrainingPart.main,
                    title: AppStrings.of(context).feature('Träningsplan'),
                    organisation: session.eventPlan!,
                  ),
                ],
              ),
              child: Text(AppStrings.of(context).feature('Använd')),
            ),
          ),
        ),
      for (final part in TrainingPart.values) _partSection(part, canEdit),
    ]);
    final tail = _part([
      if (canEdit)
        SwitchListTile(
          key: const Key('training-session-published'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            AppStrings.of(context).feature('Visa passet för spelarna'),
          ),
          subtitle: Text(
            AppStrings.of(context).feature(
              'Spelarna ser övningarna, tiderna, organisationen och coachpunkterna.',
            ),
          ),
          value: _published,
          onChanged: (value) => _edit(() => _published = value),
        ),
      if (canEdit && !session.startsAt.isAfter(DateTime.now()))
        _TrainingEvaluationSection(
          eventId: session.eventId,
          services: widget.services,
          blockTitles: [for (final block in session.blocks) block.title],
        ),
      if (session.updatedBy != null)
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          child: Text(
            '${AppStrings.of(context).feature('Senast ändrat av')} ${session.updatedBy}',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ]);
    // One plan: the session's parts woven into the event's preparation
    // (focus, goals, notes, material, tasks, files), the same items as on
    // the event. Without it, the session alone.
    return FutureBuilder<(EventDetails, SquadDetails)>(
      future: _event,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          if (!snapshot.hasError) {
            return Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              head,
              exercises,
              tail,
              _part([
                TextButton(
                  onPressed: () => setState(() {
                    _event = _loadEvent();
                  }),
                  child: Text(
                    AppStrings.of(context).feature(
                      'Fokus, anteckningar, material, uppgifter och filer kunde inte hämtas. Försök igen.',
                    ),
                  ),
                ),
              ]),
            ],
          );
        }
        final (event, squad) = data;
        return _PreparationTab(
          key: ValueKey('training-plan-${event.id}'),
          event: event,
          people: [
            for (final person in [...squad.roster, ..._guestRosterFor(squad)])
              if (_sessionPlayers.any(
                (player) => player.personId == person.personId,
              ))
                person,
          ],
          services: widget.calendar.preparation,
          allowEdit: canEdit && event.archivedAt == null,
          sessionParts: (head: head, exercises: exercises, tail: tail),
        );
      },
    );
  }

  Widget _partSection(TrainingPart part, bool canEdit) {
    final theme = Theme.of(context);
    final indices = [
      for (var i = 0; i < _blocks.length; i++)
        if (_blocks[i].part == part) i,
    ];
    if (indices.isEmpty && !canEdit) return const SizedBox.shrink();
    final minutes = indices.fold(0, (sum, i) => sum + _blocks[i].minutes);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.of(context).feature(part.label),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (minutes > 0)
                Text('$minutes min', style: theme.textTheme.labelLarge),
              if (canEdit)
                IconButton(
                  key: ValueKey('training-add-${part.name}'),
                  tooltip: AppStrings.of(context).feature('Lägg till övning'),
                  icon: const Icon(Icons.add),
                  onPressed: () => _editBlock(part: part),
                ),
            ],
          ),
          if (indices.isEmpty)
            Text(
              AppStrings.of(context).feature('Inga övningar än.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final i in indices) ...[
            _TrainingBlockCard(
              key: ValueKey('training-block-$i'),
              block: _blocks[i],
              canEdit: canEdit,
              onTap: canEdit ? () => _editBlock(index: i) : null,
              onUp: canEdit && i > 0 && _blocks[i - 1].part == part
                  ? () => _move(i, -1)
                  : null,
              onDown:
                  canEdit &&
                      i < _blocks.length - 1 &&
                      _blocks[i + 1].part == part
                  ? () => _move(i, 1)
                  : null,
            ),
            _playersFor(i, canEdit),
          ],
        ],
      ),
    );
  }
}

/// How the session's minutes fit the training: a bar, red when it runs over.
class _TrainingGuide extends StatefulWidget {
  const _TrainingGuide({
    required this.focus,
    required this.minutes,
    required this.hasBlocks,
  });
  final String focus;
  final int minutes;
  final bool hasBlocks;
  @override
  State<_TrainingGuide> createState() => _TrainingGuideState();
}

class _TrainingGuideState extends State<_TrainingGuide> {
  late final _focus = TextEditingController(text: widget.focus);
  final List<TextEditingController> _titles = [];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_titles.isEmpty) {
      for (final part in TrainingPart.values) {
        _titles.add(
          TextEditingController(
            text: AppStrings.of(context).feature(part.label),
          ),
        );
      }
    }
  }

  int _step = 0;
  @override
  void dispose() {
    _focus.dispose();
    for (final title in _titles) {
      title.dispose();
    }
    super.dispose();
  }

  List<TrainingBlock> get _draft {
    final total = widget.minutes.clamp(0, 720);
    final warmup = (total * .2).round();
    final finish = (total * .1).round();
    final times = [warmup, total - warmup - finish, finish];
    return [
      for (var i = 0; i < 3; i++)
        TrainingBlock(
          part: TrainingPart.values[i],
          title: _titles[i].text.trim(),
          minutes: times[i],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.feature('Guidad planering')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${_step + 1} / 3'),
              const SizedBox(height: 16),
              if (_step == 0) ...[
                Text(strings.feature('Vad vill ni träna på?')),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('training-guide-focus'),
                  controller: _focus,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: strings.feature('Träningsfokus'),
                  ),
                ),
              ] else if (_step == 1) ...[
                Text(strings.feature('Ge passets tre delar namn.')),
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: _titles[i],
                      maxLength: 200,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: strings.feature(
                          TrainingPart.values[i].label,
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                Text(_focus.text.trim()),
                for (final block in _draft)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(block.title),
                    trailing: Text('${block.minutes} min'),
                  ),
                Text(
                  strings.feature(
                    'Du kan ändra namn, tider och innehåll efteråt. Utkastet sparas inte automatiskt.',
                  ),
                ),
                if (widget.hasBlocks)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      strings.feature(
                        'Detta ersätter övningarna i ditt nuvarande utkast.',
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.feature('Avbryt')),
        ),
        if (_step > 0)
          TextButton(
            onPressed: () => setState(() => _step--),
            child: Text(strings.feature('Tillbaka')),
          ),
        FilledButton(
          key: const Key('training-guide-next'),
          onPressed:
              _step == 1 && _titles.any((title) => title.text.trim().isEmpty)
              ? null
              : () {
                  if (_step < 2) {
                    setState(() => _step++);
                  } else {
                    Navigator.pop(context, (_focus.text.trim(), _draft));
                  }
                },
          child: Text(strings.feature(_step == 2 ? 'Använd utkast' : 'Nästa')),
        ),
      ],
    );
  }
}

class _TrainingMinutes extends StatelessWidget {
  const _TrainingMinutes({required this.minutes, required this.length});
  final int minutes, length;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final over = length > 0 && minutes > length;
    return Column(
      key: const Key('training-session-minutes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.of(
            context,
          ).trainingMinutes(minutes, length, planned: true),
          style: TextStyle(color: over ? colors.error : null),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: length <= 0 ? 0 : (minutes / length).clamp(0, 1),
            minHeight: 6,
            color: over ? colors.error : colors.primary,
          ),
        ),
      ],
    );
  }
}

class _TrainingBlockCard extends StatelessWidget {
  const _TrainingBlockCard({
    super.key,
    required this.block,
    required this.canEdit,
    this.onTap,
    this.onUp,
    this.onDown,
  });
  final TrainingBlock block;
  final bool canEdit;
  final VoidCallback? onTap, onUp, onDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = block.phase;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            block.title,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          '${block.minutes} min',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                    if (phase != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          AppStrings.of(context).feature(phase.label),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    if (block.organisation.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(block.organisation.trim()),
                    ],
                    if (block.coachingPoints.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        AppStrings.of(context).feature('Coachpunkter'),
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(block.coachingPoints.trim()),
                    ],
                  ],
                ),
              ),
              if (canEdit)
                Column(
                  children: [
                    IconButton(
                      tooltip: AppStrings.of(context).feature('Flytta upp'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: onUp,
                    ),
                    IconButton(
                      tooltip: AppStrings.of(context).feature('Flytta ned'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: onDown,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
