part of '../../app/teamzone_app.dart';

/// A check-in status's color and icon.
(Color, IconData) _tdpStatusLook(CheckinStatus status) => switch (status) {
  CheckinStatus.onTrack => (const Color(0xFF2E7D5B), Icons.trending_up),
  CheckinStatus.atRisk => (const Color(0xFFC77700), Icons.trending_flat),
  CheckinStatus.offTrack => (const Color(0xFFB3261E), Icons.trending_down),
};

class _TdpStatusChip extends StatelessWidget {
  const _TdpStatusChip({required this.status});
  final CheckinStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _tdpStatusLook(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            AppStrings.of(context).feature(status.label),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A goal on its own: what it is, how it has gone at each check-in, and the
/// ways to check it now or change it.
abstract final class _TdpGoalSheet {
  static Future<void> show(
    BuildContext context,
    _TdpController controller,
    String goalId,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: controller,
      builder: (sheetContext, _) {
        final plan = controller.plan;
        final goal = plan?.goals.where((g) => g.id == goalId).firstOrNull;
        if (plan == null || goal == null) return const SizedBox(height: 120);
        final theme = Theme.of(sheetContext);
        final history = plan.checkinsOfGoal(goal.id);
        final period = plan.periods
            .where((p) => p.id == goal.periodId)
            .firstOrNull;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                [
                  AppStrings.of(context).feature(goal.horizon.label),
                  if (period != null) period.name,
                  if (goal.targetOn != null)
                    'senast ${_tdpDate(sheetContext, goal.targetOn!)}',
                ].join(' · '),
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(goal.title, style: theme.textTheme.titleLarge),
              if (history.firstOrNull?.status case final status?) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _TdpStatusChip(status: status),
                ),
              ],
              if (goal.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(goal.description),
              ],
              if (goal.state != GoalState.open) ...[
                const SizedBox(height: 8),
                Text(
                  AppStrings.of(context).feature(goal.state.label),
                  style: theme.textTheme.labelLarge,
                ),
              ],
              if (controller.canEdit) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('tdp-goal-checkin'),
                      onPressed: () => _TdpCheckinDialog.goal(
                        sheetContext,
                        controller,
                        goal,
                      ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(AppStrings.of(context).feature('Stäm av')),
                    ),
                    OutlinedButton.icon(
                      key: const Key('tdp-goal-edit'),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _TdpGoalDialog.edit(
                          context,
                          controller,
                          plan,
                          goal: goal,
                        );
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        AppStrings.of(context).feature('Ändra målet'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              _TdpGoalLinks(controller: controller, plan: plan, goal: goal),
              const SizedBox(height: 20),
              Text(
                AppStrings.of(context).feature('Avstämningar'),
                style: theme.textTheme.titleMedium,
              ),
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    plan.checkinEveryDays == null
                        ? AppStrings.of(
                            context,
                          ).feature('Inga avstämningar än.')
                        : (AppStrings.of(context).isSwedish
                              ? 'Inga avstämningar än. Målen stäms av var ${plan.checkinEveryDays! ~/ 7}:e vecka.'
                              : 'No check-ins yet. Goals are reviewed every ${plan.checkinEveryDays! ~/ 7} weeks.'),
                  ),
                ),
              for (final checkin in history)
                _TdpCheckinTile(
                  controller: controller,
                  plan: plan,
                  checkin: checkin,
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _TdpCheckinTile extends StatelessWidget {
  const _TdpCheckinTile({
    required this.controller,
    required this.plan,
    required this.checkin,
    this.unit = '',
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final TeamCheckin checkin;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final status = checkin.status;
    final value = checkin.value;
    return ListTile(
      key: ValueKey('tdp-checkin-${checkin.id}'),
      contentPadding: EdgeInsets.zero,
      leading: status != null
          ? Icon(_tdpStatusLook(status).$2, color: _tdpStatusLook(status).$1)
          : const Icon(Icons.show_chart),
      title: Text(
        [
          _tdpDate(context, checkin.checkedOn),
          if (status != null) AppStrings.of(context).feature(status.label),
          if (value != null) '${_tdpNumber(value)} $unit'.trim(),
        ].join(' · '),
      ),
      subtitle: Text(
        [
          if (checkin.note.trim().isNotEmpty) checkin.note.trim(),
          if (checkin.createdBy != null) checkin.createdBy!,
        ].join('\n'),
      ),
      isThreeLine: checkin.note.trim().isNotEmpty && checkin.createdBy != null,
      trailing: controller.canEdit
          ? IconButton(
              tooltip: AppStrings.of(context).feature('Ta bort avstämningen'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final sure = await _tdpConfirm(
                  context,
                  AppStrings.of(context).feature('Ta bort avstämningen?'),
                  (AppStrings.of(context).isSwedish
                      ? 'Avstämningen från ${_tdpDate(context, checkin.checkedOn)} tas bort ur historiken.'
                      : 'The check-in from ${_tdpDate(context, checkin.checkedOn)} is deleted from history.'),
                );
                if (sure && context.mounted) {
                  await controller.change(
                    context,
                    () => controller.services.deleteCheckin(plan, checkin.id),
                  );
                }
              },
            )
          : null,
    );
  }
}

/// A number as Swedish text: no decimals when whole, else one or two.
String _tdpNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0$'), '')
          .replaceAll('.', ',');

/// Checking a goal (how it goes) or recording a key figure's value.
abstract final class _TdpCheckinDialog {
  static Future<void> goal(
    BuildContext context,
    _TdpController controller,
    TeamGoal goal,
  ) => _show(context, controller, goal: goal);

  static Future<void> kpi(
    BuildContext context,
    _TdpController controller,
    TeamKpi kpi,
  ) => _show(context, controller, kpi: kpi);

  static Future<void> _show(
    BuildContext context,
    _TdpController controller, {
    TeamGoal? goal,
    TeamKpi? kpi,
  }) async {
    final plan = controller.plan;
    if (plan == null) return;
    final today = DateUtils.dateOnly(DateTime.now());
    final last = today.isAfter(plan.endsOn) ? plan.endsOn : today;
    var checked = last.isBefore(plan.startsOn) ? plan.startsOn : last;
    var status =
        (goal == null ? null : plan.checkinsOfGoal(goal.id).firstOrNull)
            ?.status ??
        CheckinStatus.onTrack;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: '',
        second: '',
        builder: (context, value, note) => StatefulBuilder(
          builder: (context, setState) {
            final number = double.tryParse(
              value.text.trim().replaceAll(',', '.'),
            );
            final valid = goal != null || number != null;
            return AlertDialog(
              title: Text(
                goal != null
                    ? AppStrings.of(context).feature('Stäm av målet')
                    : kpi!.title,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (goal != null) ...[
                      Text(goal.title),
                      const SizedBox(height: 12),
                      _TdpChoices<CheckinStatus>(
                        key: const Key('tdp-checkin-status'),
                        values: {
                          for (final value in CheckinStatus.values)
                            value: AppStrings.of(context).feature(value.label),
                        },
                        selected: status,
                        onSelected: (value) => setState(() => status = value),
                      ),
                    ] else
                      TextField(
                        key: const Key('tdp-checkin-value'),
                        controller: value,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: InputDecoration(
                          labelText: AppStrings.of(context).feature('Värde'),
                          suffixText: kpi!.unit.isEmpty ? null : kpi.unit,
                          helperText: kpi.target == null
                              ? null
                              : _tdpKpiTarget(context, kpi),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TdpDateField(
                        label: 'Datum',
                        value: checked,
                        first: plan.startsOn,
                        last: last.isBefore(plan.startsOn)
                            ? plan.startsOn
                            : last,
                        onChanged: (value) => setState(() => checked = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('tdp-checkin-note'),
                      controller: note,
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).feature('Anteckning'),
                        hintText: goal != null
                            ? AppStrings.of(
                                context,
                              ).feature('Vad ser ni, och vad gör ni härnäst?')
                            : AppStrings.of(
                                context,
                              ).feature('Till exempel vilken match'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppStrings.of(context).feature('Avbryt')),
                ),
                FilledButton(
                  key: const Key('tdp-checkin-save'),
                  onPressed: valid
                      ? () => Navigator.pop(context, (
                          value.text.trim(),
                          note.text.trim(),
                        ))
                      : null,
                  child: Text(AppStrings.of(context).feature('Spara')),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    await controller.change(
      context,
      () => controller.services.addCheckin(
        plan,
        goalId: goal?.id,
        kpiId: kpi?.id,
        checkedOn: checked,
        status: goal == null ? null : status,
        value: kpi == null
            ? null
            : double.parse(result.$1.replaceAll(',', '.')),
        note: result.$2,
      ),
      done: goal != null ? 'Avstämningen är sparad.' : 'Värdet är sparat.',
    );
  }
}

/// Översikt: the goals due for a check-in, each a tap from its check-in.
class _TdpDue extends StatelessWidget {
  const _TdpDue({required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  @override
  Widget build(BuildContext context) {
    final due = plan.goalsDue(DateTime.now());
    if (due.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      key: const Key('tdp-due'),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(
                due.length == 1
                    ? (AppStrings.of(context).isSwedish
                          ? 'Dags att stämma av ett mål'
                          : 'Time to review a goal')
                    : (AppStrings.of(context).isSwedish
                          ? 'Dags att stämma av ${due.length} mål'
                          : 'Time to review ${due.length} goals'),
              ),
              subtitle: Text(
                (AppStrings.of(context).isSwedish
                    ? 'Ni stämmer av målen var ${plan.checkinEveryDays! ~/ 7}:e vecka.'
                    : 'You review goals every ${plan.checkinEveryDays! ~/ 7} weeks.'),
              ),
            ),
            for (final goal in due)
              ListTile(
                key: ValueKey('tdp-due-${goal.id}'),
                dense: true,
                title: Text(goal.title),
                subtitle: Text(switch (plan
                    .checkinsOfGoal(goal.id)
                    .firstOrNull) {
                  final last? =>
                    'Senast ${_tdpDate(context, last.checkedOn)}: ${last.status?.label ?? ''}',
                  null => AppStrings.of(context).feature('Inte avstämt än'),
                }),
                trailing: controller.canEdit
                    ? TextButton(
                        onPressed: () =>
                            _TdpCheckinDialog.goal(context, controller, goal),
                        child: Text(AppStrings.of(context).feature('Stäm av')),
                      )
                    : null,
                onTap: () => _TdpGoalSheet.show(context, controller, goal.id),
              ),
          ],
        ),
      ),
    );
  }
}
