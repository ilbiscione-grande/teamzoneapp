part of '../../app/teamzone_app.dart';

/// MFD-12: what the team's plan says for an event's day, beside its
/// preparation. The day's block is the starting point: its focus, its
/// principles and its goals come first, the period's focus and the plan's
/// other principles after. With [onTake], a tap takes a principle or goal
/// over (as training focus, or into the match plan); it never changes the
/// event by itself, and the leader can always pick something else.
class _PlanSuggestionBox extends StatelessWidget {
  const _PlanSuggestionBox({
    required this.suggestion,
    this.taken = const {},
    this.onTake,
    this.takeHint,
    this.showExercises = false,
  });
  final TeamPlanSuggestion suggestion;

  /// The block's exercises in the box, where the page has no session to
  /// put them in (the event page's preparations).
  final bool showExercises;

  /// Already taken over, in lower case: shown without the add.
  final Set<String> taken;
  final Future<Object?> Function(String label)? onTake;
  final String? takeHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = AppStrings.of(context);
    final block = suggestion.blockName;
    final blockFocus = suggestion.blockFocus.trim();
    final periodFocus = suggestion.periodFocus.trim();
    final inBlock = {
      for (final principle in suggestion.blockPrinciples)
        principle.title.toLowerCase(),
    };
    final others = [
      for (final principle in suggestion.principles)
        if (!inBlock.contains(principle.title.toLowerCase())) principle.title,
    ];
    Widget chips(String title, List<String> labels, {Key? key}) => Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in labels)
              if (onTake == null || taken.contains(label.toLowerCase()))
                Chip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  avatar: taken.contains(label.toLowerCase())
                      ? const Icon(Icons.check, size: 16)
                      : null,
                )
              else
                ActionChip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add, size: 16),
                  onPressed: () => onTake!(label),
                ),
          ],
        ),
      ],
    );
    return Container(
      key: const Key('plan-suggestion'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    strings.feature('Från lagets plan'),
                    ?block,
                    ?suggestion.periodName,
                  ].join(' · '),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (block != null && blockFocus.isNotEmpty) ...[
            const SizedBox(height: 6),
            _TdpRichText(
              blockFocus,
              key: const Key('plan-suggestion-block-focus'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (periodFocus.isNotEmpty && periodFocus != blockFocus) ...[
            const SizedBox(height: 4),
            if (block != null)
              Text(
                _tdpText(context, 'Perioden', 'The period'),
                style: theme.textTheme.labelSmall,
              ),
            _TdpRichText(
              periodFocus,
              style: block == null ? null : theme.textTheme.bodySmall,
            ),
          ],
          if (suggestion.blockPrinciples.isNotEmpty)
            chips(
              _tdpText(context, 'Blockets principer', "The block's principles"),
              [
                for (final principle in suggestion.blockPrinciples)
                  principle.title,
              ],
              key: const Key('plan-suggestion-block-principles'),
            ),
          if (suggestion.goals.isNotEmpty)
            chips(strings.feature('Mål framåt'), suggestion.goals),
          if (others.isNotEmpty)
            chips(
              inBlock.isEmpty
                  ? strings.feature('Spelprinciper')
                  : _tdpText(
                      context,
                      'Andra spelprinciper',
                      'Other playing principles',
                    ),
              others,
            ),
          if (block != null) ...[
            const SizedBox(height: 8),
            Text(
              _tdpText(
                context,
                'Blocket är en utgångspunkt. Du kan alltid välja något annat.',
                'The block is a starting point. You can always choose something else.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (onTake != null && takeHint != null) ...[
            const SizedBox(height: 8),
            Text(takeHint!, style: theme.textTheme.bodySmall),
          ],
          if (showExercises && !suggestion.exercises.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _tdpText(
                context,
                'Övningar för blocket',
                'Exercises for the block',
              ),
              key: const Key('plan-suggestion-exercises'),
              style: theme.textTheme.labelLarge,
            ),
            for (final exercise in suggestion.exercises.all)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(_tdpExerciseIcon(exercise)),
                title: Text(exercise.title),
                subtitle: Text(
                  _tdpExerciseLine(context, exercise),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
