part of '../../app/teamzone_app.dart';

/// The session's evaluation on its page, once the training has started: how
/// it went at a glance, the attendance, and the way into writing it.
class _TrainingEvaluationSection extends StatefulWidget {
  const _TrainingEvaluationSection({
    required this.eventId,
    required this.services,
    required this.blockTitles,
  });
  final String eventId;
  final TrainingServices services;

  /// The session's exercises, to evaluate one by one.
  final List<String> blockTitles;

  @override
  State<_TrainingEvaluationSection> createState() =>
      _TrainingEvaluationSectionState();
}

class _TrainingEvaluationSectionState
    extends State<_TrainingEvaluationSection> {
  late Future<TrainingEvaluation?> _evaluation = _load();

  Future<TrainingEvaluation?> _load() => widget.services
      .getEvaluation(widget.eventId)
      .then<TrainingEvaluation?>(
        (value) => value,
        onError: (Object error) {
          AppErrors.caught('training_evaluation._load', error);
          return null;
        },
      );

  Future<void> _open(TrainingEvaluation evaluation) async {
    await _ModuleScope.push<void>(
      context,
      (_) => _TrainingEvaluationPage(
        evaluation: evaluation,
        services: widget.services,
        blockTitles: widget.blockTitles,
      ),
    );
    if (mounted) {
      setState(() {
        _evaluation = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TrainingEvaluation?>(
    future: _evaluation,
    builder: (context, snapshot) {
      final evaluation = snapshot.data;
      if (evaluation == null || !evaluation.started) {
        return const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      return Card(
        key: const Key('training-evaluation'),
        margin: const EdgeInsets.only(top: 20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Utvärdering', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(_attendanceLine(evaluation)),
              if (evaluation.written) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    _Stars(value: evaluation.rating),
                    if (evaluation.goalReached case final reached?) ...[
                      const SizedBox(width: 12),
                      Text('Målet nått: ${reached.label.toLowerCase()}'),
                    ],
                  ],
                ),
                if (evaluation.nextTime.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Till nästa pass: ${evaluation.nextTime.trim()}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Passet är inte utvärderat än.'),
                ),
              if (evaluation.canEdit) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  key: const Key('training-evaluation-open'),
                  onPressed: () => _open(evaluation),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: Text(
                    evaluation.written
                        ? 'Ändra utvärderingen'
                        : 'Utvärdera passet',
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

String _attendanceLine(TrainingEvaluation evaluation) {
  if (evaluation.recorded == 0 && evaluation.called == 0) {
    return 'Ingen kallelse eller närvaro registrerad.';
  }
  return [
    if (evaluation.recorded > 0) '${evaluation.attended} närvarade',
    if (evaluation.called > 0)
      '${evaluation.called} kallade, ${evaluation.accepted} tackade ja',
    if (evaluation.recorded == 0) 'närvaron är inte registrerad',
  ].join(' · ');
}

/// One to five stars; tappable when [onChanged] is given.
class _Stars extends StatelessWidget {
  const _Stars({required this.value, this.onChanged});
  final int? value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          onChanged == null
              ? Icon(
                  star <= (value ?? 0) ? Icons.star : Icons.star_border,
                  color: color,
                  size: 20,
                )
              : IconButton(
                  key: ValueKey('training-evaluation-star-$star'),
                  tooltip: '$star av 5',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onChanged!(star),
                  icon: Icon(
                    star <= (value ?? 0) ? Icons.star : Icons.star_border,
                    color: color,
                  ),
                ),
      ],
    );
  }
}

/// Writing the evaluation: the session's stars, whether its goal was
/// reached, each exercise as it went, and the three questions.
class _TrainingEvaluationPage extends StatefulWidget {
  const _TrainingEvaluationPage({
    required this.evaluation,
    required this.services,
    required this.blockTitles,
  });
  final TrainingEvaluation evaluation;
  final TrainingServices services;
  final List<String> blockTitles;

  @override
  State<_TrainingEvaluationPage> createState() =>
      _TrainingEvaluationPageState();
}

class _TrainingEvaluationPageState extends State<_TrainingEvaluationPage> {
  late TrainingEvaluation _evaluation = widget.evaluation;
  late int? _rating = _evaluation.rating;
  late GoalReached? _reached = _evaluation.goalReached;
  late final _wentWell = TextEditingController(text: _evaluation.wentWell);
  late final _differently = TextEditingController(
    text: _evaluation.doDifferently,
  );
  late final _nextTime = TextEditingController(text: _evaluation.nextTime);

  /// Each exercise of the session, with what was said of it before.
  late final Map<String, BlockRating?> _blocks = {
    for (final title in {
      ...widget.blockTitles,
      for (final block in _evaluation.blocks) block.title,
    })
      title: _evaluation.blocks
          .where((block) => block.title == title)
          .firstOrNull
          ?.rating,
  };
  bool _busy = false;

  @override
  void dispose() {
    _wentWell.dispose();
    _differently.dispose();
    _nextTime.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      _evaluation = await widget.services.saveEvaluation(
        eventId: _evaluation.eventId,
        expectedRevision: _evaluation.revision,
        rating: _rating,
        goalReached: _reached,
        wentWell: _wentWell.text.trim(),
        doDifferently: _differently.text.trim(),
        nextTime: _nextTime.text.trim(),
        blocks: [
          for (final MapEntry(key: title, value: rating) in _blocks.entries)
            EvaluatedBlock(title: title, rating: rating),
        ],
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Utvärderingen är sparad.')),
      );
      navigator.pop();
    } on TrainingSessionConflict {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Utvärderingen har ändrats av någon annan. Stäng och öppna den igen.',
          ),
        ),
      );
    } catch (error) {
      AppErrors.caught('training_evaluation._save', error);
      messenger.showSnackBar(
        const SnackBar(content: Text('Utvärderingen kunde inte sparas.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration field(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    );
    final children = <Widget>[
      Text(_attendanceLine(_evaluation)),
      const SizedBox(height: 16),
      Text('Hur gick passet?', style: theme.textTheme.titleMedium),
      _Stars(
        value: _rating,
        onChanged: (value) => setState(() => _rating = value),
      ),
      const SizedBox(height: 12),
      Text('Nådde ni passets mål?', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      _TdpChoices<GoalReached?>(
        key: const Key('training-evaluation-goal'),
        values: {for (final value in GoalReached.values) value: value.label},
        selected: _reached,
        onSelected: (value) => setState(() => _reached = value),
      ),
      if (_blocks.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Övningarna', style: theme.textTheme.titleMedium),
        for (final title in _blocks.keys)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 4),
                _TdpChoices<BlockRating?>(
                  key: ValueKey('training-evaluation-block-$title'),
                  values: {
                    for (final value in BlockRating.values) value: value.label,
                  },
                  selected: _blocks[title],
                  onSelected: (value) => setState(() => _blocks[title] = value),
                ),
              ],
            ),
          ),
      ],
      const SizedBox(height: 20),
      TextField(
        key: const Key('training-evaluation-well'),
        controller: _wentWell,
        maxLength: 2000,
        minLines: 2,
        maxLines: 5,
        decoration: field('Vad fungerade?', 'Det ni vill behålla'),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('training-evaluation-differently'),
        controller: _differently,
        maxLength: 2000,
        minLines: 2,
        maxLines: 5,
        decoration: field('Vad gör ni annorlunda?', 'Det som inte fungerade'),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('training-evaluation-next'),
        controller: _nextTime,
        maxLength: 2000,
        minLines: 2,
        maxLines: 5,
        decoration: field('Till nästa pass', 'Det ni tar med er'),
      ),
      if (_evaluation.updatedBy != null)
        Text(
          'Senast ändrad av ${_evaluation.updatedBy}',
          style: theme.textTheme.bodySmall,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Utvärdera passet'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const Key('training-evaluation-save'),
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Sparar…' : 'Spara'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          for (final child in children)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Align(alignment: Alignment.centerLeft, child: child),
              ),
            ),
        ],
      ),
    );
  }
}
