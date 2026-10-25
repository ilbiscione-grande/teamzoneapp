part of '../../app/teamzone_app.dart';

/// A tip for the season's current period, shown beside the session plan.
/// Two sources are planned, neither built yet: short built-in tips per game
/// phase and period type, and exercises from the TeamZone and club library
/// matching the period's principles (with the Tacticsboard link, TBL step
/// 4). A library tip carries its item, so a tap can put it in the session.
class TrainingTip {
  const TrainingTip({
    required this.title,
    this.detail = '',
    this.libraryItemId,
  });
  final String title, detail;
  final String? libraryItemId;
}

/// The tips for a period of the team's plan. None yet; see [TrainingTip].
List<TrainingTip> _trainingTipsFor(TeamPlanSuggestion suggestion) => const [];

/// The season plan at the top of the session: the current period, its focus,
/// the principles and the goals ahead, and tips for the period. A tap on a
/// principle or goal makes it the training focus (via [onTake]); without a
/// team plan, nothing.
class _TrainingSeasonPlan extends StatelessWidget {
  const _TrainingSeasonPlan({
    required this.suggestion,
    required this.focus,
    this.onTake,
  });
  final Future<TeamPlanSuggestion?> suggestion;
  final String focus;
  final Future<Object?> Function(String label)? onTake;

  @override
  Widget build(BuildContext context) => FutureBuilder<TeamPlanSuggestion?>(
    future: suggestion,
    builder: (context, snapshot) {
      final plan = snapshot.data;
      if (plan == null) return const SizedBox.shrink();
      final tips = _trainingTipsFor(plan);
      final theme = Theme.of(context);
      return Column(
        key: const Key('training-season-plan'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PlanSuggestionBox(
            suggestion: plan,
            taken: {
              for (final part in focus.split(','))
                if (part.trim().isNotEmpty) part.trim().toLowerCase(),
            },
            onTake: onTake,
            takeHint: onTake == null
                ? null
                : 'Ett tryck gör den till passets träningsfokus.',
          ),
          if (tips.isNotEmpty)
            Card(
              key: const Key('training-period-tips'),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'Tips för perioden',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  for (final tip in tips)
                    ListTile(
                      leading: const Icon(Icons.lightbulb_outline),
                      title: Text(tip.title),
                      subtitle: tip.detail.isEmpty ? null : Text(tip.detail),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
