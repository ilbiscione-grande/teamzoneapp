part of '../../app/teamzone_app.dart';

/// Where an exercise for a block comes from, in words.
String _tdpExerciseSource(BuildContext context, String source) =>
    switch (source) {
      'club' => _tdpText(context, 'Klubbens bibliotek', "The club's library"),
      'teamzone' => 'TeamZone',
      _ => _tdpText(context, 'Egen övning', 'Own exercise'),
    };

/// An exercise's details on one line: where from, minutes, phase or theme.
String _tdpExerciseLine(BuildContext context, BlockExercise exercise) => [
  _tdpExerciseSource(context, exercise.source),
  if (!exercise.single)
    _tdpText(
      context,
      'pass med ${exercise.exercises.length} övningar',
      'pass of ${exercise.exercises.length} exercises',
    ),
  if (exercise.minutes > 0) '${exercise.minutes} min',
  if (exercise.phase case final phase?)
    AppStrings.of(context).feature(phase.label),
  if (exercise.detail.isNotEmpty) exercise.detail,
].join(' · ');

IconData _tdpExerciseIcon(BlockExercise exercise) => switch (exercise.source) {
  'club' => Icons.groups_outlined,
  'teamzone' => Icons.auto_awesome_outlined,
  _ => Icons.edit_note,
};

/// A block's exercises (step 7): those the leaders chose, and the club's
/// and TeamZone's library exercises that train its principles. They show
/// when a session in the block is prepared.
class _TdpBlockExercisesView extends StatefulWidget {
  const _TdpBlockExercisesView({
    super.key,
    required this.controller,
    required this.plan,
    required this.block,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final DevelopmentBlock block;

  @override
  State<_TdpBlockExercisesView> createState() => _TdpBlockExercisesViewState();
}

class _TdpBlockExercisesViewState extends State<_TdpBlockExercisesView> {
  BlockExercises? _exercises;
  Object? _error;
  bool _busy = false;

  TeamDevelopmentServices get _services => widget.controller.services;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await _services.blockExercises(
        widget.plan,
        widget.block.id,
      );
      if (mounted) setState(() => _exercises = value);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _change(
    Future<BlockExercises> Function() run, {
    String? done,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final value = await run();
      if (!mounted) return;
      setState(() => _exercises = value);
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } on TeamDevelopmentException catch (refused) {
      messenger.showSnackBar(SnackBar(content: Text(refused.message)));
    } catch (error) {
      AppErrors.caught('tdp_block_exercises', error);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _tdpText(
              context,
              'Ändringen gick inte igenom.',
              'The change did not go through.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromLibrary() async {
    final picked = await showDialog<BlockExercise>(
      context: context,
      builder: (_) => _TdpLibraryPicker(services: _services),
    );
    if (picked == null || !mounted) return;
    await _change(
      () => _services.addBlockExercise(
        widget.plan,
        widget.block.id,
        sharedItemId: picked.itemId,
      ),
      done: _tdpText(
        context,
        '${picked.title} är vald för blocket.',
        '${picked.title} is chosen for the block.',
      ),
    );
  }

  Future<void> _own() async {
    final written = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: '',
        second: '',
        builder: (context, title, description) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(_tdpText(context, 'Egen övning', 'Own exercise')),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('tdp-own-exercise-title'),
                    controller: title,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: _tdpText(context, 'Övning', 'Exercise'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    key: const Key('tdp-own-exercise-description'),
                    controller: description,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: _tdpText(
                        context,
                        'Organisation (valfritt)',
                        'Organisation (optional)',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.of(context).feature('Avbryt')),
              ),
              FilledButton(
                key: const Key('tdp-own-exercise-save'),
                onPressed: title.text.trim().length < 2
                    ? null
                    : () => Navigator.pop(context, (
                        title.text.trim(),
                        description.text.trim(),
                      )),
                child: Text(AppStrings.of(context).feature('Spara')),
              ),
            ],
          ),
        ),
      ),
    );
    if (written == null || !mounted) return;
    await _change(
      () => _services.addBlockExercise(
        widget.plan,
        widget.block.id,
        title: written.$1,
        description: written.$2,
      ),
    );
  }

  Widget _tile(BlockExercise exercise, {required bool chosen}) {
    final canEdit = widget.controller.canEdit;
    return ListTile(
      key: ValueKey(
        chosen
            ? 'tdp-block-exercise-${exercise.id}'
            : 'tdp-block-suggested-${exercise.itemId}',
      ),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(_tdpExerciseIcon(exercise)),
      title: Text(exercise.title),
      subtitle: Text(
        _tdpExerciseLine(context, exercise),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: !canEdit
          ? null
          : chosen
          ? IconButton(
              key: ValueKey('tdp-block-exercise-remove-${exercise.id}'),
              tooltip: _tdpText(context, 'Ta bort', 'Remove'),
              icon: const Icon(Icons.close),
              onPressed: _busy
                  ? null
                  : () => _change(
                      () => _services.deleteBlockExercise(
                        widget.plan,
                        exercise.id!,
                      ),
                    ),
            )
          : TextButton(
              key: ValueKey('tdp-block-exercise-pick-${exercise.itemId}'),
              onPressed: _busy
                  ? null
                  : () => _change(
                      () => _services.addBlockExercise(
                        widget.plan,
                        widget.block.id,
                        sharedItemId: exercise.itemId,
                      ),
                    ),
              child: Text(_tdpText(context, 'Välj', 'Choose')),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercises = _exercises;
    final hint = theme.textTheme.bodySmall;
    return Column(
      key: const Key('tdp-block-exercises'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _tdpText(context, 'Övningar för blocket', 'Exercises for the block'),
          style: theme.textTheme.labelLarge,
        ),
        Text(
          _tdpText(
            context,
            'Visas när ett pass i blocket förbereds och läggs in med ett tryck.',
            'Shown when a session in the block is prepared, added with a tap.',
          ),
          style: hint,
        ),
        if (exercises == null && _error == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Text(
            _tdpText(
              context,
              'Övningarna kunde inte hämtas.',
              'The exercises could not be loaded.',
            ),
            style: hint,
          ),
        if (exercises != null) ...[
          for (final exercise in exercises.chosen)
            _tile(exercise, chosen: true),
          const SizedBox(height: 8),
          Text(
            _tdpText(
              context,
              'Förslag ur biblioteket',
              'Suggestions from the library',
            ),
            style: theme.textTheme.labelMedium,
          ),
          if (exercises.matched.isEmpty)
            Text(
              widget.block.principleIds.isEmpty
                  ? _tdpText(
                      context,
                      'Välj principer för blocket, så föreslås övningar som tränar dem.',
                      'Pick principles for the block, and exercises that train them are suggested.',
                    )
                  : _tdpText(
                      context,
                      'Biblioteket har inga fler övningar för blockets principer.',
                      'The library has no more exercises for the block\'s principles.',
                    ),
              style: hint,
            ),
          for (final exercise in exercises.matched)
            _tile(exercise, chosen: false),
        ],
        if (widget.controller.canEdit) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('tdp-block-exercise-library'),
                onPressed: _busy ? null : _fromLibrary,
                icon: const Icon(Icons.library_books_outlined, size: 18),
                label: Text(
                  _tdpText(context, 'Från biblioteket', 'From the library'),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('tdp-block-exercise-own'),
                onPressed: _busy ? null : _own,
                icon: const Icon(Icons.add, size: 18),
                label: Text(_tdpText(context, 'Egen övning', 'Own exercise')),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The club's and TeamZone's library, searched, to choose from.
class _TdpLibraryPicker extends StatefulWidget {
  const _TdpLibraryPicker({required this.services});
  final TeamDevelopmentServices services;

  @override
  State<_TdpLibraryPicker> createState() => _TdpLibraryPickerState();
}

class _TdpLibraryPickerState extends State<_TdpLibraryPicker> {
  String _source = 'club';
  String _search = '';
  late Future<List<BlockExercise>> _items = _list();

  Future<List<BlockExercise>> _list() =>
      widget.services.listLibrary(_source, search: _search);

  void _reload() => setState(() {
    _items = _list();
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tdpText(context, 'Från biblioteket', 'From the library')),
    content: SizedBox(
      width: 520,
      height: 460,
      child: Column(
        children: [
          SegmentedButton<String>(
            key: const Key('tdp-library-source'),
            segments: [
              ButtonSegment(
                value: 'club',
                label: Text(_tdpText(context, 'Klubben', 'The club')),
              ),
              const ButtonSegment(value: 'teamzone', label: Text('TeamZone')),
            ],
            selected: {_source},
            onSelectionChanged: (value) {
              _source = value.first;
              _reload();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('tdp-library-search'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _tdpText(context, 'Sök', 'Search'),
              isDense: true,
            ),
            onSubmitted: (value) {
              _search = value.trim();
              _reload();
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<BlockExercise>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      _tdpText(
                        context,
                        'Biblioteket kunde inte hämtas.',
                        'The library could not be loaded.',
                      ),
                    ),
                  );
                }
                final items = snapshot.data;
                if (items == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      _tdpText(context, 'Inget hittades.', 'Nothing found.'),
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final item in items)
                      ListTile(
                        key: ValueKey('tdp-library-item-${item.itemId}'),
                        leading: Icon(
                          item.single
                              ? Icons.sports_soccer
                              : Icons.view_list_outlined,
                        ),
                        title: Text(item.title),
                        subtitle: Text(
                          _tdpExerciseLine(context, item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, item),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppStrings.of(context).feature('Avbryt')),
      ),
    ],
  );
}
