part of '../../app/teamzone_app.dart';

/// The panel beside Planera's timeline: the period or block picked, or,
/// with nothing picked, how to plan and what the players see.
class _TdpPlanPanel extends StatelessWidget {
  const _TdpPlanPanel({
    required this.controller,
    required this.plan,
    required this.picked,
    required this.onPick,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final _TdpPick? picked;
  final ValueChanged<_TdpPick?> onPick;

  @override
  Widget build(BuildContext context) {
    final picked = this.picked;
    if (picked != null && picked.block) {
      final block = plan.blocks.firstWhere((b) => b.id == picked.id);
      return _TdpBlockPanel(controller: controller, plan: plan, block: block);
    }
    if (picked != null) {
      final period = plan.periods.firstWhere((p) => p.id == picked.id);
      return _TdpPeriodPanel(
        controller: controller,
        plan: plan,
        period: period,
        onPick: onPick,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.touch_app_outlined),
            title: Text(
              plan.periods.isEmpty
                  ? AppStrings.of(context).feature(
                      'Lägg till perioder, till exempel försäsong, tävling del 1, '
                      'uppehåll och tävling del 2.',
                    )
                  : _tdpText(
                      context,
                      'Klicka på en period eller ett block för att öppna det.',
                      'Click a period or a block to open it.',
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _TdpSharingCard(controller: controller, plan: plan),
      ],
    );
  }
}

/// A picked period: its phase, dates and focus, its short-term goals under
/// the season's, and its blocks.
class _TdpPeriodPanel extends StatelessWidget {
  const _TdpPeriodPanel({
    required this.controller,
    required this.plan,
    required this.period,
    required this.onPick,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final DevelopmentPeriod period;
  final ValueChanged<_TdpPick?> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = plan.blocksOf(period.id);
    return Card(
      key: ValueKey('tdp-panel-${period.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TdpPhaseChip(phase: period.phase),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tdpText(
                      context,
                      'Period · v${_tdpWeek(period.startsOn)}–${_tdpWeek(period.endsOn)}',
                      'Period · w${_tdpWeek(period.startsOn)}–${_tdpWeek(period.endsOn)}',
                    ),
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                if (controller.canEdit)
                  IconButton(
                    key: const Key('tdp-panel-edit'),
                    tooltip: _tdpText(
                      context,
                      'Ändra perioden',
                      'Edit the period',
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _TdpPeriodDialog.edit(
                      context,
                      controller,
                      plan,
                      period: period,
                    ),
                  ),
              ],
            ),
            Text(period.name, style: theme.textTheme.titleLarge),
            Text(_tdpRange(context, period.startsOn, period.endsOn)),
            if (period.focus.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                AppStrings.of(context).feature('Fokus'),
                style: theme.textTheme.labelLarge,
              ),
              Text(period.focus),
            ],
            const Divider(height: 24),
            _TdpGoalGroup(
              controller: controller,
              plan: plan,
              title: _tdpText(
                context,
                'Periodens kortsiktiga mål',
                'The period\'s short-term goals',
              ),
              goals: plan.goalsOf(GoalHorizon.period, periodId: period.id),
              empty: AppStrings.of(
                context,
              ).feature('Inga mål för perioden än.'),
              newGoal: (
                horizon: GoalHorizon.period,
                periodId: period.id,
                blockId: null,
              ),
              flat: true,
            ),
            _TdpAbove(
              title: _tdpText(
                context,
                'Bidrar till säsongsmålen',
                'Contributes to the season goals',
              ),
              goals: plan.goalsOf(GoalHorizon.season),
            ),
            const Divider(height: 24),
            Text(
              _tdpText(context, 'Block i perioden', 'Blocks in the period'),
              style: theme.textTheme.titleSmall,
            ),
            if (blocks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _tdpText(
                    context,
                    'Inga block än. Dra ut dem i blockfältet under perioden.',
                    'No blocks yet. Drag them out on the block lane under the period.',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (final block in blocks)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.view_week_outlined),
                title: Text(block.name),
                subtitle: Text(
                  _tdpRange(context, block.startsOn, block.endsOn),
                ),
                onTap: () => onPick((block: true, id: block.id)),
              ),
          ],
        ),
      ),
    );
  }
}

/// A picked block: its dates, focus and principles, its own short-term
/// goals with the period's above them, and how many trainings start from it.
class _TdpBlockPanel extends StatelessWidget {
  const _TdpBlockPanel({
    required this.controller,
    required this.plan,
    required this.block,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final DevelopmentBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = plan.periods
        .where((p) => p.id == block.periodId)
        .firstOrNull;
    final principles = _tdpPrinciples(plan, block.principleIds);
    return Card(
      key: ValueKey('tdp-panel-${block.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      _tdpText(
                        context,
                        'Block · v${_tdpWeek(block.startsOn)}–${_tdpWeek(block.endsOn)}',
                        'Block · w${_tdpWeek(block.startsOn)}–${_tdpWeek(block.endsOn)}',
                      ),
                      if (period != null) period.name,
                    ].join(' · '),
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                if (controller.canEdit) ...[
                  IconButton(
                    key: const Key('tdp-panel-edit'),
                    tooltip: _tdpText(
                      context,
                      'Ändra blocket',
                      'Edit the block',
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () =>
                        _TdpBlockDialog.edit(context, controller, plan, block),
                  ),
                  IconButton(
                    key: const Key('tdp-block-delete'),
                    tooltip: _tdpText(
                      context,
                      'Ta bort blocket',
                      'Delete the block',
                    ),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context),
                  ),
                ],
              ],
            ),
            Text(block.name, style: theme.textTheme.titleLarge),
            Text(_tdpRange(context, block.startsOn, block.endsOn)),
            if (block.focus.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                AppStrings.of(context).feature('Fokus'),
                style: theme.textTheme.labelLarge,
              ),
              Text(block.focus),
            ],
            const SizedBox(height: 12),
            Text(
              _tdpText(context, 'Principer i fokus', 'Principles in focus'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            if (principles.isEmpty)
              Text(
                _tdpText(
                  context,
                  'Inga principer valda.',
                  'No principles chosen.',
                ),
                style: theme.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final principle in principles)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(principle.title),
                    ),
                ],
              ),
            const Divider(height: 24),
            _TdpGoalGroup(
              controller: controller,
              plan: plan,
              title: _tdpText(
                context,
                'Blockets kortsiktiga mål',
                'The block\'s short-term goals',
              ),
              goals: plan.goalsOf(GoalHorizon.block, blockId: block.id),
              empty: _tdpText(
                context,
                'Inga mål för blocket än.',
                'No goals for the block yet.',
              ),
              newGoal: (
                horizon: GoalHorizon.block,
                periodId: null,
                blockId: block.id,
              ),
              flat: true,
            ),
            if (period != null)
              _TdpAbove(
                title: _tdpText(
                  context,
                  'Periodens mål ovanför',
                  'The period\'s goals above',
                ),
                goals: plan.goalsOf(GoalHorizon.period, periodId: period.id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final goals = plan.goalsOf(GoalHorizon.block, blockId: block.id).length;
    final sure = await _tdpConfirm(
      context,
      _tdpText(context, 'Ta bort ${block.name}?', 'Delete ${block.name}?'),
      goals == 0
          ? _tdpText(
              context,
              'Blocket tas bort ur perioden.',
              'The block is deleted from the period.',
            )
          : _tdpText(
              context,
              'Blocket och dess $goals mål tas bort ur perioden.',
              'The block and its $goals goals are deleted from the period.',
            ),
    );
    if (!sure || !context.mounted) return;
    await controller.change(
      context,
      () => controller.services.deleteBlock(plan, block.id),
      done: _tdpText(context, 'Blocket är borttaget.', 'The block is deleted.'),
    );
  }
}

/// The goals one level up, to read beside the short-term ones.
class _TdpAbove extends StatelessWidget {
  const _TdpAbove({required this.title, required this.goals});
  final String title;
  final List<TeamGoal> goals;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          for (final goal in goals) Text('↑ ${goal.title}', style: style),
        ],
      ),
    );
  }
}

/// A block's name, focus and principles in focus (up to eight of the plan's,
/// in the order picked). Its dates are set on the timeline.
abstract final class _TdpBlockDialog {
  static Future<void> edit(
    BuildContext context,
    _TdpController controller,
    SeasonPlan plan,
    DevelopmentBlock block,
  ) async {
    final chosen = [...block.principleIds];
    // Without a game model the block picks from the base list, and the
    // picked ones become the plan's principles when the block is saved.
    final standard = <_TdpIdea>[];
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: block.name,
        second: block.focus,
        builder: (context, name, focus) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(_tdpText(context, 'Ändra blocket', 'Edit the block')),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('tdp-block-name'),
                      controller: name,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: _tdpText(context, 'Namn', 'Name'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      key: const Key('tdp-block-focus'),
                      controller: focus,
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).feature('Fokus'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _tdpText(
                        context,
                        'Principer i fokus (högst åtta)',
                        'Principles in focus (at most eight)',
                      ),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    if (plan.principles.isEmpty) ...[
                      Text(
                        _tdpText(
                          context,
                          'Laget har ingen spelidé än, så välj ur grundlistan. '
                              'Spelidén skrivs under Spelidé.',
                          'The team has no game model yet, so pick from the '
                              'base list. The game model is written under '
                              'Game model.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (i, idea) in _tdpStandardIdeas.indexed)
                            FilterChip(
                              key: ValueKey('tdp-block-standard-$i'),
                              label: Text(idea.title),
                              tooltip: AppStrings.of(
                                context,
                              ).feature(idea.area.label),
                              selected: standard.contains(idea),
                              onSelected: (on) => setState(
                                () => on
                                    ? standard.add(idea)
                                    : standard.remove(idea),
                              ),
                            ),
                        ],
                      ),
                    ] else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final principle in plan.principles)
                            FilterChip(
                              key: ValueKey(
                                'tdp-block-principle-${principle.id}',
                              ),
                              label: Text(principle.title),
                              tooltip: AppStrings.of(
                                context,
                              ).feature(principle.area.label),
                              selected: chosen.contains(principle.id),
                              onSelected:
                                  !chosen.contains(principle.id) &&
                                      chosen.length >= 8
                                  ? null
                                  : (on) => setState(
                                      () => on
                                          ? chosen.add(principle.id)
                                          : chosen.remove(principle.id),
                                    ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.of(context).feature('Avbryt')),
              ),
              FilledButton(
                key: const Key('tdp-block-save'),
                onPressed: name.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, (
                        name.text.trim(),
                        focus.text.trim(),
                      )),
                child: Text(AppStrings.of(context).feature('Spara')),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    await controller.change(context, () async {
      final saved = await _tdpAddIdeas(controller.services, plan, standard);
      return controller.services.saveBlock(
        saved,
        blockId: block.id,
        periodId: block.periodId,
        name: result.$1,
        startsOn: block.startsOn,
        endsOn: block.endsOn,
        focus: result.$2,
        principleIds: [
          ...chosen,
          for (final idea in standard)
            if (_tdpPrincipleOf(saved, idea) case final principle?)
              principle.id,
        ],
      );
    }, done: _tdpText(context, 'Blocket är sparat.', 'The block is saved.'));
  }
}
