part of '../../app/teamzone_app.dart';

/// Who the match is against, home or away, and when.
class _MatchPlanHeader extends StatelessWidget {
  const _MatchPlanHeader({required this.plan});
  final MatchPlan plan;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final when = plan.startsAt;
    return Text(
      [
        if (plan.opponentName?.isNotEmpty == true)
          '${strings.feature('Mot')} ${plan.opponentName}',
        if (plan.homeAway == 'home') strings.feature('Hemma'),
        if (plan.homeAway == 'away') strings.feature('Borta'),
        if (when != null)
          MaterialLocalizations.of(context).formatFullDate(when),
      ].join(' · '),
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

/// The event's match goals (its KPI targets), followed up after the match;
/// they are set under Förberedelser in the event.
class _MatchGoalsCard extends StatelessWidget {
  const _MatchGoalsCard({required this.goals});
  final Future<EventFollowup?> goals;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<EventFollowup?>(
      future: goals,
      builder: (context, snapshot) {
        final kpis = snapshot.data?.kpis ?? const <EventKpi>[];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.feature('Matchmål'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                if (kpis.isEmpty)
                  Text(
                    strings.feature(
                      'Inga matchmål än. De sätts under Förberedelser i aktiviteten.',
                    ),
                  )
                else ...[
                  for (final kpi in kpis)
                    Text('• ${kpi.label}: ${_kpiGoalText(kpi)}'),
                  const SizedBox(height: 4),
                  Text(
                    strings.feature(
                      'Ändras under Förberedelser i aktiviteten och följs upp efter matchen.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
