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
  final _goal = TextEditingController();
  TrainingSession? _session;
  List<TrainingBlock> _blocks = const [];
  bool _published = false, _dirty = false, _busy = false, _missing = false;
  Object? _error;

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
    _session = session;
    _blocks = [...session.blocks];
    _published = session.published;
    _dirty = false;
  }

  Future<void> _load() async {
    try {
      final session = await widget.services.getSession(widget.eventId);
      if (!mounted) return;
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
    final session = _session;
    if (session == null || _busy) return;
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
      );
      if (!mounted) return;
      setState(() => _show(saved));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved.published
                ? 'Passet är sparat och visas för spelarna.'
                : 'Passet är sparat. Bara ledarna ser det.',
          ),
        ),
      );
    } on TrainingSessionConflict {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Passet har ändrats av någon annan. Det senaste visas nu, '
            'gör dina ändringar igen.',
          ),
        ),
      );
      await _load();
    } catch (error) {
      AppErrors.caught('training_session._save', error);
      messenger.showSnackBar(
        const SnackBar(content: Text('Passet kunde inte sparas.')),
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
        title: const Text('Lämna utan att spara?'),
        content: const Text('Dina ändringar i passet sparas inte.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stanna'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lämna'),
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
    if (result == null || !mounted) return;
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
    if (target < 0 || target >= _blocks.length) return;
    if (_blocks[target].part != _blocks[index].part) return;
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
        if (popped) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) {
          _dirty = false;
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Träningspass'),
          actions: [
            if (canEdit)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  key: const Key('training-session-save'),
                  onPressed: _dirty && !_busy ? _save : null,
                  child: Text(_busy ? 'Sparar…' : 'Spara'),
                ),
              ),
          ],
        ),
        body: _body(session),
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

  Widget _body(TrainingSession? session) {
    if (_error != null) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: const Text('Passet kunde inte hämtas. Försök igen.'),
        ),
      );
    }
    if (_missing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ledarna har inte publicerat något pass för träningen än.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final canEdit = session.canEdit;
    final minutes = _blocks.fold(0, (sum, b) => sum + b.minutes);
    final head = _part([
      Text(
        _trainingDay(context, session.startsAt),
        style: theme.textTheme.labelLarge,
      ),
      Text(session.title, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 12),
      _TrainingMinutes(minutes: minutes, length: session.eventMinutes),
      const SizedBox(height: 16),
      if (canEdit)
        TextField(
          key: const Key('training-session-theme'),
          controller: _theme,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Tema',
            hintText: 'Till exempel press och återerövring',
          ),
        )
      else if (session.theme.trim().isNotEmpty)
        Text(session.theme, style: theme.textTheme.titleMedium),
    ]);
    final goal = _part([
      Text('Mål för träningen', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      if (canEdit) ...[
        TextField(
          key: const Key('training-session-goal'),
          controller: _goal,
          maxLength: 2000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Passets mål',
            hintText: 'Vad spelarna ska ta med sig från passet',
            border: OutlineInputBorder(),
          ),
        ),
        FutureBuilder<TeamPlanSuggestion?>(
          future: _suggestion,
          builder: (context, snapshot) => switch (snapshot.data) {
            final suggestion? => _PlanSuggestionBox(
              suggestion: suggestion,
              taken: {
                for (final line in _goal.text.split('\n'))
                  line.replaceFirst(RegExp(r'^•\s*'), '').trim().toLowerCase(),
              },
              onTake: (label) async => _edit(() {
                final text = _goal.text.trimRight();
                _goal.text = text.isEmpty ? '• $label' : '$text\n• $label';
              }),
              takeHint: 'Ett tryck lägger in den i passets mål.',
            ),
            null => const SizedBox.shrink(),
          },
        ),
      ] else
        Text(session.goal.trim().isEmpty ? 'Inget mål skrivet.' : session.goal),
    ]);
    final exercises = _part([
      Text('Övningar', style: theme.textTheme.titleMedium),
      if (canEdit && _blocks.isEmpty && session.eventPlan != null)
        Card(
          key: const Key('training-session-event-plan'),
          child: ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('Träningsplanen från eventet'),
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
                    title: 'Träningsplan',
                    organisation: session.eventPlan!,
                  ),
                ],
              ),
              child: const Text('Använd'),
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
          title: const Text('Visa passet för spelarna'),
          subtitle: const Text(
            'Spelarna ser övningarna, tiderna, organisationen och coachpunkterna.',
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
            'Senast ändrat av ${session.updatedBy}',
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
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              head,
              goal,
              exercises,
              tail,
              _part([
                TextButton(
                  onPressed: () => setState(() {
                    _event = _loadEvent();
                  }),
                  child: const Text(
                    'Fokus, anteckningar, material, uppgifter och filer kunde inte hämtas. Försök igen.',
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
          people: [...squad.roster, ..._guestRosterFor(squad)],
          services: widget.calendar.preparation,
          allowEdit: canEdit && event.archivedAt == null,
          sessionParts: (
            head: head,
            goal: goal,
            exercises: exercises,
            tail: tail,
          ),
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
                child: Text(part.label, style: theme.textTheme.titleMedium),
              ),
              if (minutes > 0)
                Text('$minutes min', style: theme.textTheme.labelLarge),
              if (canEdit)
                IconButton(
                  key: ValueKey('training-add-${part.name}'),
                  tooltip: 'Lägg till övning',
                  icon: const Icon(Icons.add),
                  onPressed: () => _editBlock(part: part),
                ),
            ],
          ),
          if (indices.isEmpty)
            Text(
              'Inga övningar än.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final i in indices)
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
          length > 0 ? '$minutes av $length min planerade' : '$minutes min',
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
                          phase.label,
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
                      Text('Coachpunkter', style: theme.textTheme.labelMedium),
                      Text(block.coachingPoints.trim()),
                    ],
                  ],
                ),
              ),
              if (canEdit)
                Column(
                  children: [
                    IconButton(
                      tooltip: 'Flytta upp',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: onUp,
                    ),
                    IconButton(
                      tooltip: 'Flytta ned',
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
