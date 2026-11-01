part of '../../app/teamzone_app.dart';

/// The preparation on the desktop programme: goals and focus, the event's
/// preparation (notes, material, tasks, files) and the exercises with
/// publishing, each in its own panel.
class _TrainingPreparationProgramme extends StatelessWidget {
  const _TrainingPreparationProgramme({
    required this.seasonPlan,
    required this.goals,
    required this.preparation,
    required this.blocks,
    required this.eventMinutes,
    required this.tail,
    required this.onPlanning,
  });
  final Widget seasonPlan, goals, tail;
  final List<Widget> preparation;
  final List<TrainingBlock> blocks;
  final int eventMinutes;
  final VoidCallback onPlanning;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    Widget title(String text, {Widget? action}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.feature(text),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
    // On a phone the panels follow each other in one list.
    final compact = MediaQuery.sizeOf(context).width < 1200;
    Widget panel(int flex, List<Widget> children) => compact
        ? _ProgramPanel(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          )
        : Expanded(
            flex: flex,
            child: _ProgramPanel(
              padding: EdgeInsets.zero,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: children,
              ),
            ),
          );
    const gap = SizedBox(width: 12, height: 12);
    Widget layout(List<Widget> panels) => compact
        ? Align(
            key: const Key('training-preparation-programme'),
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: panels,
              ),
            ),
          )
        : Padding(
            key: const Key('training-preparation-programme'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: panels,
            ),
          );
    return layout([
      panel(4, [
        title('Mål och fokus'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _TrainingMinutes(
            minutes: blocks.fold(0, (sum, b) => sum + b.minutes),
            length: eventMinutes,
          ),
        ),
        seasonPlan,
        goals,
      ]),
      gap,
      panel(5, [title('Förberedelser'), ...preparation]),
      gap,
      panel(4, [
        title(
          'Övningar',
          action: TextButton.icon(
            onPressed: onPlanning,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: Text(strings.feature('Planering')),
          ),
        ),
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(strings.feature('Inga övningar än.')),
          ),
        for (final (i, block) in blocks.indexed)
          InkWell(
            onTap: onPlanning,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: _trainingPartColors(block.part).accent,
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      block.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${block.minutes} min',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 24),
        tail,
      ]),
    ]);
  }
}
