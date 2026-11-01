part of '../../app/teamzone_app.dart';

/// Where a new goal goes: its horizon, and its period or block.
typedef _TdpNewGoal = ({
  GoalHorizon horizon,
  String? periodId,
  String? blockId,
});

/// A heading with its goals and a way to add one there.
class _TdpGoalGroup extends StatelessWidget {
  const _TdpGoalGroup({
    required this.controller,
    required this.plan,
    required this.title,
    required this.goals,
    required this.empty,
    required this.newGoal,
    this.subtitle,
    this.flat = false,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final String title, empty;
  final String? subtitle;
  final List<TeamGoal> goals;
  final _TdpNewGoal newGoal;

  /// Inside another card: no card of its own.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(flat ? 0 : 16, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (controller.canEdit)
                IconButton(
                  tooltip: AppStrings.of(context).feature('Lägg till mål'),
                  icon: const Icon(Icons.add),
                  onPressed: () => _TdpGoalDialog.edit(
                    context,
                    controller,
                    plan,
                    horizon: newGoal.horizon,
                    periodId: newGoal.periodId,
                    blockId: newGoal.blockId,
                  ),
                ),
            ],
          ),
        ),
        if (goals.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(flat ? 0 : 16, 0, 16, 12),
            child: Text(
              empty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final goal in goals)
          _TdpGoalTile(
            controller: controller,
            plan: plan,
            goal: goal,
            flat: flat,
          ),
        if (!flat) const SizedBox(height: 4),
      ],
    );
    return flat ? content : Card(child: content);
  }
}

class _TdpGoalTile extends StatelessWidget {
  const _TdpGoalTile({
    required this.controller,
    required this.plan,
    required this.goal,
    this.flat = false,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final TeamGoal goal;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (goal.state) {
      GoalState.achieved => (Icons.check_circle, Colors.green.shade600),
      GoalState.dropped => (Icons.remove_circle_outline, colors.outline),
      GoalState.open => (Icons.radio_button_unchecked, colors.primary),
    };
    final details = [
      if (goal.targetOn != null)
        (AppStrings.of(context).isSwedish
            ? 'Senast ${_tdpDate(context, goal.targetOn!)}'
            : 'Due by ${_tdpDate(context, goal.targetOn!)}'),
      if (goal.state != GoalState.open)
        AppStrings.of(context).feature(goal.state.label),
      if (plan.checkinsOfGoal(goal.id).firstOrNull?.status case final status?)
        AppStrings.of(context).feature(status.label),
      if (goal.description.trim().isNotEmpty) goal.description.trim(),
    ];
    return ListTile(
      key: ValueKey('tdp-goal-${goal.id}'),
      contentPadding: EdgeInsets.symmetric(horizontal: flat ? 0 : 16),
      leading: controller.canEdit
          ? IconButton(
              tooltip: goal.state == GoalState.achieved
                  ? AppStrings.of(context).feature('Markera som pågående')
                  : AppStrings.of(context).feature('Markera som uppnått'),
              icon: Icon(icon, color: color),
              onPressed: () => controller.change(
                context,
                () => controller.services.saveGoal(
                  plan,
                  goalId: goal.id,
                  horizon: goal.horizon,
                  periodId: goal.periodId,
                  blockId: goal.blockId,
                  title: goal.title,
                  description: goal.description,
                  targetOn: goal.targetOn,
                  state: goal.state == GoalState.achieved
                      ? GoalState.open
                      : GoalState.achieved,
                ),
              ),
            )
          : Icon(icon, color: color),
      title: Text(
        goal.title,
        style: goal.state == GoalState.dropped
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: colors.outline,
              )
            : null,
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: () => _TdpGoalSheet.show(context, controller, goal.id),
    );
  }
}
