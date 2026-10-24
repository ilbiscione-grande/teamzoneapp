part of '../../app/teamzone_app.dart';

typedef _TdpNewGoal = ({GoalHorizon horizon, String? periodId});

/// Mål: every goal of the season, the season's first, then each period's
/// in date order, then the short-term ones by their date.
class _TdpGoals extends StatelessWidget {
  const _TdpGoals({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) => _TdpFrame(
    controller: controller,
    action: (plan) => FilledButton.tonalIcon(
      key: const Key('tdp-new-goal'),
      onPressed: () => _TdpGoalDialog.edit(context, controller, plan),
      icon: const Icon(Icons.add),
      label: const Text('Nytt mål'),
    ),
    builder: (plan) {
      final short = plan.goalsOf(GoalHorizon.short)
        ..sort((a, b) => a.targetOn!.compareTo(b.targetOn!));
      return [
        _TdpGoalGroup(
          controller: controller,
          plan: plan,
          title: 'Säsongsmål',
          goals: plan.goalsOf(GoalHorizon.season),
          empty: 'Långsiktiga mål för hela säsongen.',
          newGoal: (horizon: GoalHorizon.season, periodId: null),
        ),
        for (final period in plan.periods) ...[
          const SizedBox(height: 16),
          _TdpGoalGroup(
            controller: controller,
            plan: plan,
            title: period.name,
            subtitle: _tdpRange(context, period.startsOn, period.endsOn),
            goals: plan.goalsOf(GoalHorizon.period, periodId: period.id),
            empty: 'Tillfälliga mål för perioden.',
            newGoal: (horizon: GoalHorizon.period, periodId: period.id),
          ),
        ],
        const SizedBox(height: 16),
        _TdpGoalGroup(
          controller: controller,
          plan: plan,
          title: 'Kortsiktiga mål',
          goals: short,
          empty: 'Mål inför en viss match eller ett block av träningar.',
          newGoal: (horizon: GoalHorizon.short, periodId: null),
        ),
      ];
    },
  );
}

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
                  tooltip: 'Lägg till mål',
                  icon: const Icon(Icons.add),
                  onPressed: () => _TdpGoalDialog.edit(
                    context,
                    controller,
                    plan,
                    horizon: newGoal.horizon,
                    periodId: newGoal.periodId,
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
      if (goal.targetOn != null) 'Senast ${_tdpDate(context, goal.targetOn!)}',
      if (goal.state != GoalState.open) goal.state.label,
      if (plan.checkinsOfGoal(goal.id).firstOrNull?.status case final status?)
        status.label,
      if (goal.description.trim().isNotEmpty) goal.description.trim(),
    ];
    return ListTile(
      key: ValueKey('tdp-goal-${goal.id}'),
      contentPadding: EdgeInsets.symmetric(horizontal: flat ? 0 : 16),
      leading: controller.canEdit
          ? IconButton(
              tooltip: goal.state == GoalState.achieved
                  ? 'Markera som pågående'
                  : 'Markera som uppnått',
              icon: Icon(icon, color: color),
              onPressed: () => controller.change(
                context,
                () => controller.services.saveGoal(
                  plan,
                  goalId: goal.id,
                  horizon: goal.horizon,
                  periodId: goal.periodId,
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
