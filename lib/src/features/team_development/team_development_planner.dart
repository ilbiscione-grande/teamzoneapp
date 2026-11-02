part of '../../app/teamzone_app.dart';

/// Planera (decisions 10–11, 2026-11-01): the timeline of periods and blocks
/// across the whole width on top (2026-11-02), then the panel for the one
/// picked (its focus, principles and short-term goals) beside the season's
/// long-term goals. Nothing picked, the panel tells how to plan and what is
/// shared with the players.
class _TdpPlanner extends StatefulWidget {
  const _TdpPlanner({required this.controller});
  final _TdpController controller;

  @override
  State<_TdpPlanner> createState() => _TdpPlannerState();
}

class _TdpPlannerState extends State<_TdpPlanner> {
  _TdpPick? _picked;

  _TdpController get controller => widget.controller;

  /// Saves where a period or block was laid out, and picks it.
  Future<void> _layout(SeasonPlan plan, _TdpLayout layout) async {
    final strings = AppStrings.of(context);
    final saved = await controller.change(
      context,
      () => layout.block
          ? _saveBlock(plan, layout, strings)
          : _savePeriod(plan, layout, strings),
    );
    final now = controller.plan;
    if (!saved || now == null || !mounted) return;
    bool at(DateTime startsOn) => startsOn == layout.startsOn;
    final id =
        layout.id ??
        (layout.block
            ? now.blocks.where((b) => at(b.startsOn)).firstOrNull?.id
            : now.periods.where((p) => at(p.startsOn)).firstOrNull?.id);
    if (id != null) setState(() => _picked = (block: layout.block, id: id));
  }

  Future<SeasonPlan> _savePeriod(
    SeasonPlan plan,
    _TdpLayout layout,
    AppStrings strings,
  ) {
    final period = plan.periods.where((p) => p.id == layout.id).firstOrNull;
    return controller.services.savePeriod(
      plan,
      periodId: period?.id,
      name: period?.name ?? (strings.isSwedish ? 'Ny period' : 'New period'),
      phase: period?.phase ?? PeriodPhase.other,
      startsOn: layout.startsOn,
      endsOn: layout.endsOn,
      focus: period?.focus ?? '',
    );
  }

  Future<SeasonPlan> _saveBlock(
    SeasonPlan plan,
    _TdpLayout layout,
    AppStrings strings,
  ) {
    final block = plan.blocks.where((b) => b.id == layout.id).firstOrNull;
    return controller.services.saveBlock(
      plan,
      blockId: block?.id,
      periodId: block?.periodId ?? layout.periodId!,
      name: block?.name ?? (strings.isSwedish ? 'Nytt block' : 'New block'),
      startsOn: layout.startsOn,
      endsOn: layout.endsOn,
      focus: block?.focus ?? '',
      principleIds: block?.principleIds ?? const [],
    );
  }

  Future<void> _editSeason(SeasonPlan plan) async {
    final draft = await _SeasonDialog.show(context, plan: plan);
    if (draft == null || !mounted) return;
    await controller.change(
      context,
      () => controller.services.savePlan(
        plan,
        title: draft.title,
        startsOn: draft.startsOn,
        endsOn: draft.endsOn,
        vision: draft.vision,
        checkinEveryDays: draft.checkinEveryDays,
      ),
      done: AppStrings.of(context).feature('Säsongen är sparad.'),
    );
  }

  /// A pick that is gone (deleted, or another season) is let go.
  _TdpPick? _pickIn(SeasonPlan plan) => switch (_picked) {
    (block: true, :final id) when plan.blocks.any((b) => b.id == id) => _picked,
    (block: false, :final id) when plan.periods.any((p) => p.id == id) =>
      _picked,
    _ => null,
  };

  @override
  Widget build(BuildContext context) => _TdpFrame(
    controller: controller,
    maxWidth: 1600,
    top: (plan) {
      final theme = Theme.of(context);
      final picked = _pickIn(plan);
      return Card(
        key: const Key('tdp-timeline'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.canEdit
                          ? _tdpText(
                              context,
                              'Dra i ett tomt fält för att lägga ut en period eller ett block, dra i kanterna för att ändra datum och i mitten för att flytta. Klicka för att öppna.',
                              'Drag on an empty stretch to lay out a period or a block, drag its edges to change the dates and its middle to move it. Click to open.',
                            )
                          : _tdpText(
                              context,
                              'Klicka på en period eller ett block för att öppna.',
                              'Click a period or a block to open it.',
                            ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    key: const Key('tdp-planner-calendar'),
                    onPressed: () => _TdpCalendar.open(
                      context,
                      controller: controller,
                      plan: plan,
                    ),
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(
                      _tdpText(context, 'Årskalender', 'Year calendar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TdpTimelineEditor(
                plan: plan,
                canEdit: controller.canEdit,
                picked: picked,
                onPick: (pick) => setState(() => _picked = pick),
                onLayout: (layout) => _layout(plan, layout),
              ),
            ],
          ),
        ),
      );
    },
    builder: (plan) {
      final theme = Theme.of(context);
      final picked = _pickIn(plan);
      final panel = _TdpPlanPanel(
        controller: controller,
        plan: plan,
        picked: picked,
        onPick: (pick) => setState(() => _picked = pick),
      );
      final goals = _TdpGoalGroup(
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
      );
      return [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.of(context).feature('Planera säsongen'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${plan.title} · ${_tdpRange(context, plan.startsOn, plan.endsOn)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (controller.canEdit)
              OutlinedButton.icon(
                key: const Key('tdp-edit-season'),
                onPressed: () => _editSeason(plan),
                icon: const Icon(Icons.edit_outlined),
                label: Text(AppStrings.of(context).feature('Ändra säsongen')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 1000
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: panel),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: goals),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [panel, const SizedBox(height: 12), goals],
                ),
        ),
      ];
    },
  );
}
