part of '../../app/teamzone_app.dart';

/// A block of the session: the exercise's part, name, minutes, the phase of
/// the game it trains, its organisation and coaching points. Returns the
/// block, or (null, true) when it is removed.
class _TrainingBlockDialog extends StatefulWidget {
  const _TrainingBlockDialog({this.block, this.part});
  final TrainingBlock? block;
  final TrainingPart? part;

  static Future<(TrainingBlock?, bool)?> show(
    BuildContext context, {
    TrainingBlock? block,
    TrainingPart? part,
  }) => showDialog<(TrainingBlock?, bool)>(
    context: context,
    builder: (_) => _TrainingBlockDialog(block: block, part: part),
  );

  @override
  State<_TrainingBlockDialog> createState() => _TrainingBlockDialogState();
}

class _TrainingBlockDialogState extends State<_TrainingBlockDialog> {
  late final _title = TextEditingController(text: widget.block?.title ?? '');
  late final _minutes = TextEditingController(
    text: '${widget.block?.minutes ?? 15}',
  );
  late final _organisation = TextEditingController(
    text: widget.block?.organisation ?? '',
  );
  late final _coaching = TextEditingController(
    text: widget.block?.coachingPoints ?? '',
  );
  late TrainingPart _part =
      widget.block?.part ?? widget.part ?? TrainingPart.main;
  late PrincipleArea? _phase = widget.block?.phase;

  @override
  void dispose() {
    for (final controller in [_title, _minutes, _organisation, _coaching]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? get _minutesValue {
    final value = int.tryParse(_minutes.text.trim());
    return value == null || value < 0 || value > 240 ? null : value;
  }

  bool get _valid => _title.text.trim().isNotEmpty && _minutesValue != null;

  void _save() {
    final base =
        widget.block ?? TrainingBlock(part: _part, title: _title.text.trim());
    Navigator.pop(context, (
      base.copyWith(
        part: _part,
        title: _title.text.trim(),
        minutes: _minutesValue,
        organisation: _organisation.text.trim(),
        coachingPoints: _coaching.text.trim(),
        phase: _phase,
        clearPhase: _phase == null,
      ),
      false,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.block == null
          ? AppStrings.of(context).feature('Ny övning')
          : AppStrings.of(context).feature('Ändra övningen'),
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TdpChoices<TrainingPart>(
              key: const Key('training-block-part'),
              values: {
                for (final part in TrainingPart.values)
                  part: AppStrings.of(context).feature(part.label),
              },
              selected: _part,
              onSelected: (value) => setState(() => _part = value),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('training-block-title'),
                    controller: _title,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).feature('Övning'),
                      hintText: AppStrings.of(
                        context,
                      ).feature('Till exempel rondo 5 mot 2'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    key: const Key('training-block-minutes'),
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).feature('Minuter'),
                      counterText: '',
                    ),
                    maxLength: 3,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<PrincipleArea?>(
              key: const Key('training-block-phase'),
              isExpanded: true,
              initialValue: _phase,
              decoration: InputDecoration(
                labelText: AppStrings.of(
                  context,
                ).feature('Skede som tränas (valfritt)'),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(AppStrings.of(context).feature('Inget skede')),
                ),
                for (final area in PrincipleArea.values)
                  DropdownMenuItem(
                    value: area,
                    child: Text(
                      '${AppStrings.of(context).feature(area.label)} (${area.withBall ? AppStrings.of(context).feature('med boll') : AppStrings.of(context).feature('utan boll')})',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _phase = value),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('training-block-organisation'),
              controller: _organisation,
              maxLength: 2000,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).feature('Organisation'),
                hintText: AppStrings.of(
                  context,
                ).feature('Yta, antal spelare, regler'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('training-block-coaching'),
              controller: _coaching,
              maxLength: 2000,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).feature('Coachpunkter'),
                hintText: AppStrings.of(
                  context,
                ).feature('Vad ledarna lyfter under övningen'),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.block != null)
        TextButton(
          key: const Key('training-block-delete'),
          onPressed: () => Navigator.pop(context, (null, true)),
          child: Text(AppStrings.of(context).feature('Ta bort')),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppStrings.of(context).feature('Avbryt')),
      ),
      FilledButton(
        key: const Key('training-block-save'),
        onPressed: _valid ? _save : null,
        child: Text(AppStrings.of(context).feature('Klar')),
      ),
    ],
  );
}
