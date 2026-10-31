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
/// set and changed here or under Förberedelser in the event, one and the same.
class _MatchGoalsCard extends StatelessWidget {
  const _MatchGoalsCard({
    required this.eventId,
    required this.goals,
    required this.services,
    required this.onChanged,
  });
  final String eventId;
  final Future<EventFollowup?> goals;
  final EventPreparationServices services;
  final VoidCallback onChanged;

  Future<void> _edit(BuildContext context, [EventKpi? kpi]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) =>
          _KpiGoalSheet(eventId: eventId, services: services, existing: kpi),
    );
    if (saved == true) onChanged();
  }

  Future<void> _delete(BuildContext context, EventKpi kpi) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await services.deleteKpiTarget(eventId, kpi.id);
      onChanged();
    } catch (error) {
      AppErrors.caught('match_plan_parts._delete', error);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Målet kunde inte tas bort.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<EventFollowup?>(
      future: goals,
      builder: (context, snapshot) {
        final kpis = snapshot.data?.kpis ?? const <EventKpi>[];
        final canEdit = snapshot.data?.canEditTargets ?? false;
        return Card(
          key: const Key('match-plan-goals'),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.feature('Matchmål'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (canEdit)
                      TextButton.icon(
                        key: const Key('match-plan-add-goal'),
                        onPressed: () => _edit(context),
                        icon: const Icon(Icons.add),
                        label: Text(strings.feature('Lägg till mål')),
                      ),
                  ],
                ),
                if (kpis.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      strings.feature(
                        'Sätt mål som ni följer upp efteråt, till exempel närvaro eller skott på mål.',
                      ),
                    ),
                  ),
                for (final kpi in kpis)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _localizedKpiLabel(context, kpi.kpiKey, kpi.label),
                    ),
                    subtitle: Text(_kpiGoalText(context, kpi)),
                    onTap: canEdit ? () => _edit(context, kpi) : null,
                    trailing: canEdit
                        ? PopupMenuButton<String>(
                            tooltip: strings.feature('Åtgärder för målet'),
                            onSelected: (value) => value == 'edit'
                                ? _edit(context, kpi)
                                : _delete(context, kpi),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(strings.feature('Ändra')),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(strings.feature('Ta bort')),
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
