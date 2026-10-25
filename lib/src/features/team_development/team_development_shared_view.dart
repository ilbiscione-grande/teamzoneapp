part of '../../app/teamzone_app.dart';

/// Laget → Översikt: what the leaders share of the team's plan, for the
/// players, guardians and leaders alike. Nothing shows until something is
/// shared.
class _TeamPlanCard extends StatefulWidget {
  const _TeamPlanCard({required this.teamId, required this.services});
  final String teamId;
  final TeamDevelopmentServices services;

  @override
  State<_TeamPlanCard> createState() => _TeamPlanCardState();
}

class _TeamPlanCardState extends State<_TeamPlanCard> {
  late Future<SharedTeamPlan?> _plan = _load();

  Future<SharedTeamPlan?> _load() =>
      widget.services.getShared(widget.teamId).catchError((Object error) {
        AppErrors.caught('team_plan_card._load', error);
        return null;
      });

  @override
  void didUpdateWidget(covariant _TeamPlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) _plan = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SharedTeamPlan?>(
    future: _plan,
    builder: (context, snapshot) {
      final plan = snapshot.data;
      if (plan == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final today = DateUtils.dateOnly(DateTime.now());
      final period =
          plan.periods?.where((p) => p.contains(today)).firstOrNull ??
          plan.periods?.where((p) => p.startsOn.isAfter(today)).firstOrNull;
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Card(
          key: const Key('team-plan-card'),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _SharedTeamPlanPage(plan: plan),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_note, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppStrings.of(context).feature('Lagets plan'),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(plan.title, style: theme.textTheme.bodySmall),
                  if (plan.vision != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      plan.vision!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                  if (period != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${period.contains(today) ? 'Nu' : 'Nästa'}: ${period.name}',
                      style: theme.textTheme.labelLarge,
                    ),
                    if (period.focus.trim().isNotEmpty)
                      Text(
                        period.focus,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Everything shared of the plan: the vision, the periods, the principles
/// in the game's four phases, and the season's and periods' goals.
class _SharedTeamPlanPage extends StatelessWidget {
  const _SharedTeamPlanPage({required this.plan});
  final SharedTeamPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final periods = plan.periods;
    final principles = plan.principles;
    final goals = plan.goals;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(text, style: theme.textTheme.titleLarge),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context).feature('Lagets plan')),
      ),
      body: ListView(
        key: const Key('shared-team-plan'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          for (final child in [
            Text(plan.title, style: theme.textTheme.headlineSmall),
            Text(_tdpRange(context, plan.startsOn, plan.endsOn)),
            if (plan.vision != null) ...[
              const SizedBox(height: 12),
              Text(
                plan.vision!,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            if (periods != null && periods.isNotEmpty) ...[
              heading('Perioder'),
              for (final period in periods)
                Card(
                  shape: period.contains(today)
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        )
                      : null,
                  child: ListTile(
                    title: Text(
                      period.contains(today)
                          ? '${period.name} · nu'
                          : period.name,
                    ),
                    subtitle: Text(
                      [
                        '${AppStrings.of(context).feature(period.phase.label)}, ${_tdpRange(context, period.startsOn, period.endsOn)}',
                        if (period.focus.trim().isNotEmpty) period.focus,
                      ].join('\n'),
                    ),
                  ),
                ),
            ],
            if (principles != null && principles.isNotEmpty) ...[
              heading('Spelidé'),
              for (final (withBall, without) in PrincipleArea.pairs)
                if (principles.any(
                  (p) => p.area == withBall || p.area == without,
                ))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final area in [withBall, without])
                            if (principles.any((p) => p.area == area)) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  0,
                                ),
                                child: Text(
                                  '${AppStrings.of(context).feature(area.label)} (${AppStrings.of(context).feature(area.withBall ? 'Med boll' : 'Utan boll').toLowerCase()})',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              for (final principle in principles)
                                if (principle.area == area)
                                  ListTile(
                                    dense: true,
                                    title: Text(principle.title),
                                    subtitle:
                                        principle.description.trim().isEmpty
                                        ? null
                                        : Text(principle.description),
                                  ),
                            ],
                        ],
                      ),
                    ),
                  ),
            ],
            if (goals != null && goals.isNotEmpty) ...[
              heading('Mål'),
              for (final goal in goals)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: Icon(
                            goal.state == GoalState.achieved
                                ? Icons.check_circle
                                : Icons.flag_outlined,
                            color: goal.state == GoalState.achieved
                                ? Colors.green.shade600
                                : theme.colorScheme.primary,
                          ),
                          title: Text(goal.title),
                          subtitle: Text(
                            [
                              goal.horizon == GoalHorizon.season
                                  ? 'Säsongsmål'
                                  : periods
                                            ?.where(
                                              (p) => p.id == goal.periodId,
                                            )
                                            .firstOrNull
                                            ?.name ??
                                        'Periodens mål',
                              if (goal.state == GoalState.achieved) 'Uppnått',
                              if (goal.description.trim().isNotEmpty)
                                goal.description.trim(),
                            ].join(' · '),
                          ),
                        ),
                        for (final link in goal.links)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(
                              left: 72,
                              right: 16,
                            ),
                            leading: const Icon(Icons.link, size: 20),
                            title: Text(link.title),
                            onTap: () => launchUrl(
                              Uri.parse(link.url),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ])
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}
