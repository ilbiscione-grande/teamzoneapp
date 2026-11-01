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

  TrainingPassServices? get _passes =>
      widget.services is TrainingPassSourceServices
      ? (widget.services as TrainingPassSourceServices).passes
      : null;

  /// Takes a pass or an exercise from the library in as blocks, each last
  /// in its part, as many as the session has room for.
  Future<void> _fromLibrary() async {
    final passes = _passes;
    if (passes == null) return;
    final pass = await showDialog<TrainingPass>(
      context: context,
      builder: (_) => _TrainingPassPicker(services: passes),
    );
    if (pass == null || !mounted) return;
    final strings = AppStrings.of(context);
    final room = _maxBlocks - _blocks.length;
    final taken = pass.exercises.take(max(0, room)).toList();
    if (taken.isNotEmpty) {
      _edit(() {
        if (_theme.text.trim().isEmpty && pass.theme.isNotEmpty) {
          _theme.text = pass.theme;
        }
        _blocks = _ordered([..._blocks, ...taken]);
        _editorRevision++;
        _selectedBlock = null;
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          taken.length < pass.exercises.length
              ? strings.formatFeature(
                  'Passet rymmer högst {max} övningar. {count} lades in.',
                  {'max': _maxBlocks, 'count': taken.length},
                )
              : strings.formatFeature(
                  '{count} övningar lades in. Spara passet för att behålla dem.',
                  {'count': taken.length},
                ),
        ),
      ),
    );
  }

  /// Links a board from the library to an exercise, in place of its empty
  /// board when the session is saved as a pass.
  Future<void> _linkBoard(int index) async {
    final passes = _passes;
    if (passes == null) return;
    final board = await showDialog<TrainingBoardLink>(
      context: context,
      builder: (_) => _TrainingPassPicker(services: passes, board: true),
    );
    if (board == null || !mounted || index >= _blocks.length) return;
    _updateExercise(index, _blocks[index].copyWith(board: board));
  }

  /// The most blocks a session holds, as the server allows.
  static const _maxBlocks = 30;

  /// Saves the session as saved as a pass, to use again and share.
  Future<void> _savePass() async {
    final passes = _passes;
    final session = _session;
    if (passes == null || session == null) return;
    final strings = AppStrings.of(context);
    if (_dirty || session.rosterSaved == false || session.revision == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.feature('Spara passet först.'))),
      );
      return;
    }
    if (_blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.feature('Lägg till övningar först.'))),
      );
      return;
    }
    final theme = _theme.text.trim();
    await showDialog<void>(
      context: context,
      builder: (_) => _TrainingPassSaveDialog(
        services: passes,
        eventId: session.eventId,
        title: theme.isEmpty ? session.title : theme,
      ),
    );
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
    squad: _sessionPlayers,
    candidates: _playerRoster,
    onFocus: _editFocus,
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

  /// The focus on a phone, where the header has no room for its field.
  Future<void> _editFocus() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppStrings.of(context).feature('Träningsfokus')),
      content: TextField(
        key: const Key('training-session-theme'),
        controller: _theme,
        autofocus: true,
        maxLength: 200,
        decoration: InputDecoration(
          hintText: AppStrings.of(
            context,
          ).feature('Till exempel press och återerövring'),
        ),
        onSubmitted: (_) => Navigator.pop(context),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.of(context).feature('Klar')),
        ),
      ],
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
      setState(() {
        _show(saved);
        _savedAt = DateTime.now();
      });
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
      // An edited exercise stays chosen, also when its part moved it.
      final edited = index != null && !result.$2 ? result.$1 : null;
      _selectedBlock = edited == null ? null : _blocks.indexOf(edited);
      if (_selectedBlock == -1) _selectedBlock = null;
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
    final desktop = canEdit && MediaQuery.sizeOf(context).width >= 1200;
    final strings = AppStrings.of(context);
    final unsaved = _dirty || session?.rosterSaved == false;
    void changeView(int view) {
      if (_workspaceForm.currentState?.validate() ?? true) {
        setState(() => _view = view);
      }
    }

    // Who may not edit reads the published session, without these views.
    final views = session == null || !canEdit
        ? null
        : _view == 0
        ? _dashboard(session)
        : _view == 2
        ? _body(session, programme: true)
        : desktop
        ? _program(session)
        : _planningMobile(session);
    final exercise =
        !desktop &&
        _exerciseOpen &&
        _selectedBlock != null &&
        _selectedBlock! < _blocks.length;
    return PopScope(
      canPop: !_dirty && !exercise,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) {
          return;
        }
        if (exercise) {
          _closeExercise();
          return;
        }
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) {
          _dirty = false;
          navigator.pop();
        }
      },
      child: desktop && session != null
          ? Scaffold(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerLow,
              body: SafeArea(
                child: Column(
                  children: [
                    _TrainingProgramHeader(
                      session: session,
                      event: _event,
                      theme: _theme,
                      unsaved: unsaved,
                      busy: _busy,
                      savedAt: _savedAt,
                      published: _published,
                      onSave: unsaved && !_busy ? _save : null,
                      onGuide: _busy ? null : _guide,
                      onAdd: () => _editBlock(),
                      onPublished: (value) => _edit(() => _published = value),
                      onLibrary: _passes == null || _busy ? null : _fromLibrary,
                      onSavePass: _passes == null || _busy ? null : _savePass,
                    ),
                    _TrainingProgramTabs(view: _view, onChanged: changeView),
                    Expanded(child: views!),
                  ],
                ),
              ),
            )
          : canEdit && session != null
          ? Scaffold(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerLow,
              body: SafeArea(
                child: exercise
                    ? _exerciseMobile(session)
                    : Column(
                        children: [
                          _TrainingMobileHeader(
                            session: session,
                            event: _event,
                            theme: _theme,
                            overview: _view == 0,
                            unsaved: unsaved,
                            busy: _busy,
                            published: _published,
                            onSave: unsaved && !_busy ? _save : null,
                            onGuide: _busy ? null : _guide,
                            onAdd: () => _editBlock(),
                            onPublished: (value) =>
                                _edit(() => _published = value),
                            onFocus: _editFocus,
                            onLibrary: _passes == null || _busy
                                ? null
                                : _fromLibrary,
                            onSavePass: _passes == null || _busy
                                ? null
                                : _savePass,
                          ),
                          _TrainingProgramTabs(
                            view: _view,
                            onChanged: changeView,
                            expand: true,
                          ),
                          Expanded(child: views!),
                        ],
                      ),
              ),
            )
          : Scaffold(
              // Who may not edit reads the published session.
              appBar: AppBar(title: Text(strings.feature('Träningspass'))),
              body: _body(session),
            ),
    );
  }

  final _workspaceForm = GlobalKey<FormState>();
  int _editorRevision = 0;

  /// When this page last saved the session, for the header's status.
  DateTime? _savedAt;

  /// On a phone, whether the selected exercise is open over the session,
  /// and which of its tabs shows.
  bool _exerciseOpen = false;
  int _exerciseTab = 0;

  void _openExercise(int index) => setState(() {
    _selectedBlock = index;
    _exerciseOpen = true;
    _exerciseTab = 0;
  });

  void _closeExercise() {
    if (_workspaceForm.currentState?.validate() ?? true) {
      setState(() => _exerciseOpen = false);
    }
  }

  Widget _planningMobile(TrainingSession session) => _TrainingPlanningMobile(
    blocks: _blocks,
    header: [
      _ProgramPanel(
        child: _TrainingMinutes(
          minutes: _blocks.fold(0, (sum, b) => sum + b.minutes),
          length: session.eventMinutes,
        ),
      ),
      ?_eventPlanCard(session),
    ],
    onOpen: _openExercise,
    onAdd: (part) => _editBlock(part: part),
    onEdit: (index) => _editBlock(index: index),
    onMove: _move,
    onCopy: _copyExercise,
    onRemove: _removeExercise,
  );

  Widget _exerciseMobile(TrainingSession session) {
    final selected = _selectedBlock!;
    final editorKey = '$_editorRevision-$selected';
    return Form(
      key: _workspaceForm,
      child: _TrainingExerciseMobile(
        block: _blocks[selected],
        editorKey: editorKey,
        tab: _exerciseTab,
        roster: _sessionPlayers,
        settings: _propertiesFor(selected, editorKey),
        onTab: (tab) {
          if (_workspaceForm.currentState?.validate() ?? true) {
            setState(() => _exerciseTab = tab);
          }
        },
        onClose: _closeExercise,
        onChanged: (block) => _updateExercise(selected, block),
        onEdit: () => _editBlock(index: selected),
        onCopy: () => _copyExercise(selected),
        onRemove: () {
          setState(() => _exerciseOpen = false);
          _removeExercise(selected);
        },
        onManageRoster: () => setState(() {
          _exerciseOpen = false;
          _view = 0;
        }),
        onAddUnnamed: _sessionPlayers.length < 80
            ? () => _addUnnamed(selected)
            : null,
        onLinkBoard: _passes == null ? null : () => _linkBoard(selected),
      ),
    );
  }

  /// The selected exercise's properties, beside it on a desktop and as its
  /// settings tab on a phone.
  Widget _propertiesFor(int? selected, String editorKey) {
    final block = selected == null ? null : _blocks[selected];
    return _TrainingProperties(
      block: block,
      editorKey: editorKey,
      published: _published,
      canMoveUp:
          selected != null &&
          selected > 0 &&
          _blocks[selected - 1].part == block!.part,
      canMoveDown:
          selected != null &&
          selected < _blocks.length - 1 &&
          _blocks[selected + 1].part == block!.part,
      onChanged: (changed) => _updateExercise(selected!, changed),
      onPart: (part) {
        if (!(_workspaceForm.currentState?.validate() ?? true)) {
          return;
        }
        final changed = block!.copyWith(part: part);
        _edit(() {
          final items = [..._blocks]..[selected!] = changed;
          _blocks = _ordered(items);
          _selectedBlock = _blocks.indexOf(changed);
          _editorRevision++;
        });
      },
      onMove: (delta) => _reorder(selected!, selected + delta),
      onPublished: (value) => _edit(() => _published = value),
    );
  }

  /// The event's own plan, offered as a first exercise while there is none.
  Widget? _eventPlanCard(TrainingSession session) {
    if (!session.canEdit || _blocks.isNotEmpty || session.eventPlan == null) {
      return null;
    }
    return Card(
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
    );
  }

  void _selectExercise(int index) {
    if (!(_workspaceForm.currentState?.validate() ?? true)) {
      return;
    }
    setState(() => _selectedBlock = index);
  }

  void _updateExercise(int index, TrainingBlock block) {
    _edit(() => _blocks = [..._blocks]..[index] = block);
  }

  /// Moves an exercise to [newIndex], within its own part only.
  void _reorder(int oldIndex, int newIndex) {
    if (!(_workspaceForm.currentState?.validate() ?? true)) {
      return;
    }
    final item = _blocks[oldIndex];
    final items = [..._blocks]..removeAt(oldIndex);
    items.insert(newIndex, item);
    if (newIndex > 0 && items[newIndex - 1].part.index > item.part.index) {
      return;
    }
    if (newIndex + 1 < items.length &&
        items[newIndex + 1].part.index < item.part.index) {
      return;
    }
    _edit(() {
      _blocks = items;
      _selectedBlock = newIndex;
      _editorRevision++;
    });
  }

  void _removeExercise(int index) {
    final removed = _blocks[index];
    final messenger = ScaffoldMessenger.of(context);
    _edit(() {
      _blocks = [..._blocks]..removeAt(index);
      _selectedBlock = _blocks.isEmpty ? null : min(index, _blocks.length - 1);
      _editorRevision++;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).feature('Övningen togs bort.')),
        action: SnackBarAction(
          label: AppStrings.of(context).feature('Ångra'),
          onPressed: () {
            if (!mounted) return;
            _edit(() {
              _blocks = [..._blocks]
                ..insert(min(index, _blocks.length), removed);
              _blocks = _ordered(_blocks);
              _selectedBlock = _blocks.indexOf(removed);
              _editorRevision++;
            });
          },
        ),
      ),
    );
  }

  void _copyExercise(int index) {
    if (!(_workspaceForm.currentState?.validate() ?? true)) {
      return;
    }
    _edit(() {
      _blocks = [..._blocks]..insert(index + 1, _blocks[index].copyWith());
      _selectedBlock = index + 1;
      _editorRevision++;
    });
  }

  /// An unnamed player joins the session squad and the exercise at once.
  void _addUnnamed(int index) {
    final player = TrainingBlockPlayer(
      rosterId: 'anonymous-${DateTime.now().microsecondsSinceEpoch}',
    );
    _edit(() {
      _sessionPlayers = [..._sessionPlayers, player];
      _blocks = [..._blocks]
        ..[index] = _blocks[index].copyWith(
          players: [..._blocks[index].players, player],
        );
    });
  }

  Widget _program(TrainingSession session) {
    final selected = _selectedBlock != null && _selectedBlock! < _blocks.length
        ? _selectedBlock
        : (_blocks.isEmpty ? null : 0);
    final block = selected == null ? null : _blocks[selected];
    final editorKey = '$_editorRevision-$selected';
    return Form(
      key: _workspaceForm,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            _TrainingTimeline(
              blocks: _blocks,
              eventMinutes: session.eventMinutes,
              selected: selected,
              onSelect: _selectExercise,
              onReorder: _reorder,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 290,
                    child: _ProgramPanel(
                      padding: EdgeInsets.zero,
                      child: _TrainingStructure(
                        blocks: _blocks,
                        selected: selected,
                        onSelect: _selectExercise,
                        onAdd: (part) => _editBlock(part: part),
                        onEdit: (index) => _editBlock(index: index),
                        onRemove: _removeExercise,
                        onReorder: _reorder,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProgramPanel(
                      padding: EdgeInsets.zero,
                      child: _TrainingExercisePanel(
                        block: block,
                        editorKey: editorKey,
                        onChanged: (changed) =>
                            _updateExercise(selected!, changed),
                        onSwap: () => _editBlock(index: selected),
                        onCopy: () => _copyExercise(selected!),
                        onRemove: () => _removeExercise(selected!),
                        onGuide: _guide,
                        onLinkBoard: _passes == null
                            ? null
                            : () => _linkBoard(selected!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width >= 1440 ? 340 : 300,
                    child: _ProgramPanel(
                      child: block == null
                          ? const SizedBox.shrink()
                          : _TrainingPlayerPanel(
                              key: ValueKey('training-player-panel-$selected'),
                              roster: _sessionPlayers,
                              players: block.players,
                              onManageRoster: () => setState(() => _view = 0),
                              onAddUnnamed: _sessionPlayers.length < 80
                                  ? () => _addUnnamed(selected!)
                                  : null,
                              onChanged: (players) => _updateExercise(
                                selected!,
                                block.copyWith(players: players),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 240,
                    child: _ProgramPanel(
                      padding: EdgeInsets.zero,
                      child: _propertiesFor(selected, editorKey),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

  Widget _body(TrainingSession? session, {bool programme = false}) {
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
        if (!programme)
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
        if (!programme)
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
      ?_eventPlanCard(session),
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
          sessionLayout: programme
              ? (goals, preparation) => _TrainingPreparationProgramme(
                  seasonPlan: head,
                  goals: goals,
                  preparation: preparation,
                  blocks: _blocks,
                  eventMinutes: session.eventMinutes,
                  tail: tail,
                  onPlanning: () => setState(() => _view = 1),
                )
              : null,
        );
      },
    );
  }

  /// Opens the exercise's board in the shared view, through a short link of
  /// your own. Only boards from a training project: the players cannot see
  /// the library's yet.
  VoidCallback? _boardOpener(TrainingBlock block) {
    final passes = _passes, id = block.id;
    if (passes == null || id == null || block.board?.source != 'mine') {
      return null;
    }
    return () async {
      try {
        final path = await passes.openBlockBoard(id);
        await launchUrl(
          Uri.parse('$webtoolsOrigin$path'),
          mode: LaunchMode.externalApplication,
        );
      } catch (error) {
        AppErrors.caught('training_session._board', error);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Tavlan kunde inte öppnas.'),
            ),
          ),
        );
      }
    };
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
              onBoard: _boardOpener(_blocks[i]),
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
    this.onBoard,
    this.onUp,
    this.onDown,
  });
  final TrainingBlock block;
  final bool canEdit;
  final VoidCallback? onTap, onBoard, onUp, onDown;

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
                    if (onBoard != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextButton.icon(
                          key: const Key('training-block-board'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onBoard,
                          icon: const Icon(Icons.sports_soccer, size: 18),
                          label: Text(
                            AppStrings.of(context).feature('Visa tavla'),
                          ),
                        ),
                      ),
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
