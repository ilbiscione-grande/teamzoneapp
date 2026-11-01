part of '../../app/teamzone_app.dart';

/// Three steps to a first draft: a focus, the parts' names, and a review.
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
