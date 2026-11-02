part of '../../app/teamzone_app.dart';

/// A block's exercise (Team Development Plan step 7) as the session takes
/// it in: a library item keeps its origin, the leaders' own is the
/// session's own.
TrainingPass _trainingPassOf(BlockExercise exercise) {
  final pass = TrainingPass.fromJson(exercise.pass);
  if (exercise.source != 'own') return pass;
  return TrainingPass(
    source: pass.source,
    id: pass.id,
    title: pass.title,
    single: true,
    exercises: [
      for (final row in exercise.exercises)
        TrainingBlock.fromJson({...row, 'source_kind': 'own'}),
    ],
  );
}

/// The season plan at the top of the session: the day's block and period,
/// their focus, the principles and the goals ahead, and the block's
/// exercises ("Tips för perioden"), chosen by the leaders or from the
/// library for the block's principles. A tap on a principle or goal makes
/// it the training focus (via [onTake]); a tap on an exercise puts it in
/// the session (via [onTakePass]). Without a team plan, nothing.
class _TrainingSeasonPlan extends StatelessWidget {
  const _TrainingSeasonPlan({
    required this.suggestion,
    required this.focus,
    this.onTake,
    this.onTakePass,
  });
  final Future<TeamPlanSuggestion?> suggestion;
  final String focus;
  final Future<Object?> Function(String label)? onTake;
  final Future<void> Function(TrainingPass pass)? onTakePass;

  @override
  Widget build(BuildContext context) => FutureBuilder<TeamPlanSuggestion?>(
    future: suggestion,
    builder: (context, snapshot) {
      final plan = snapshot.data;
      if (plan == null) return const SizedBox.shrink();
      final tips = plan.exercises.all;
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
                : AppStrings.of(
                    context,
                  ).feature('Ett tryck gör den till passets träningsfokus.'),
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
                      AppStrings.of(context).feature('Tips för perioden'),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                    child: Text(
                      _tdpText(
                        context,
                        'Övningar för blocket${plan.blockName == null ? '' : ' ${plan.blockName}'}.',
                        'Exercises for the block${plan.blockName == null ? '' : ' ${plan.blockName}'}.',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  for (final tip in tips)
                    ListTile(
                      key: ValueKey('training-tip-${tip.source}-${tip.itemId}'),
                      leading: Icon(_tdpExerciseIcon(tip)),
                      title: Text(tip.title),
                      subtitle: Text(
                        _tdpExerciseLine(context, tip),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: onTakePass == null || tip.exercises.isEmpty
                          ? null
                          : TextButton(
                              key: ValueKey(
                                'training-tip-take-${tip.source}-${tip.itemId}',
                              ),
                              onPressed: () =>
                                  onTakePass!(_trainingPassOf(tip)),
                              child: Text(_tdpText(context, 'Lägg in', 'Add')),
                            ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
