part of '../../app/teamzone_app.dart';

/// Utvecklingsplan's top (2026-11-22): the team development plan as a part
/// of Säsongsplanering, with the season's vision and long-term goals above
/// the way of playing.
class _TdpDevelopmentHead extends StatelessWidget {
  const _TdpDevelopmentHead({required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vision = plan.vision.trim();
    return Column(
      key: const Key('tdp-development-head'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tdpText(
                      context,
                      'Lagets utvecklingsplan (TDP)',
                      "The team's development plan (TDP)",
                    ),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _tdpText(
                      context,
                      'Vart laget ska under ${plan.title}: visionen, säsongens mål och spelidén.',
                      'Where the team is heading in ${plan.title}: the vision, the season goals and the playing philosophy.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (controller.canEdit)
              TextButton.icon(
                key: const Key('tdp-edit-vision'),
                onPressed: () => controller.editSeason(context, plan),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(_tdpText(context, 'Ändra vision', 'Edit vision')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tdpText(context, 'Vision', 'Vision'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                if (vision.isEmpty)
                  Text(
                    _tdpText(
                      context,
                      'Ingen vision än. Beskriv vad laget vill vara i slutet av säsongen.',
                      'No vision yet. Describe what the team wants to be at the end of the season.',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  _TdpRichText(vision, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _TdpGoalGroup(
          controller: controller,
          plan: plan,
          title: _tdpText(
            context,
            'Säsongsmål (långsiktiga)',
            'Season goals (long-term)',
          ),
          goals: plan.goalsOf(GoalHorizon.season),
          empty: AppStrings.of(
            context,
          ).feature('Långsiktiga mål för hela säsongen.'),
          newGoal: (horizon: GoalHorizon.season, periodId: null, blockId: null),
        ),
      ],
    );
  }
}
