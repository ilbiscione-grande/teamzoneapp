part of '../../app/teamzone_app.dart';

/// Spelidé: the team's principles per area of the game, and its key figures
/// with their targets and the values recorded over the season.
class _TdpPlay extends StatelessWidget {
  const _TdpPlay({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) => _TdpFrame(
    controller: controller,
    builder: (plan) {
      final theme = Theme.of(context);
      final areas = [
        for (final area in PrincipleArea.values)
          if (plan.principles.any((p) => p.area == area)) area,
      ];
      return [
        Row(
          children: [
            Expanded(
              child: Text('Spelprinciper', style: theme.textTheme.titleLarge),
            ),
            if (controller.canEdit)
              TextButton.icon(
                key: const Key('tdp-new-principle'),
                onPressed: () =>
                    _TdpPrincipleDialog.edit(context, controller, plan),
                icon: const Icon(Icons.add),
                label: const Text('Ny princip'),
              ),
          ],
        ),
        if (areas.isEmpty)
          const _TdpHint(
            icon: Icons.lightbulb_outline,
            text:
                'Beskriv hur laget vill spela, till exempel i försvar: '
                '"Vinn tillbaka bollen inom fem sekunder".',
          ),
        for (final area in areas)
          Card(
            key: ValueKey('tdp-area-${area.key}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(area.label, style: theme.textTheme.titleMedium),
                  ),
                  for (final principle in plan.principles)
                    if (principle.area == area)
                      ListTile(
                        key: ValueKey('tdp-principle-${principle.id}'),
                        title: Text(principle.title),
                        subtitle: principle.description.trim().isEmpty
                            ? null
                            : Text(principle.description),
                        onTap: controller.canEdit
                            ? () => _TdpPrincipleDialog.edit(
                                context,
                                controller,
                                plan,
                                principle: principle,
                              )
                            : null,
                      ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text('Nyckeltal', style: theme.textTheme.titleLarge),
            ),
            if (controller.canEdit)
              TextButton.icon(
                key: const Key('tdp-new-kpi'),
                onPressed: () => _TdpKpiDialog.edit(context, controller, plan),
                icon: const Icon(Icons.add),
                label: const Text('Nytt nyckeltal'),
              ),
          ],
        ),
        if (plan.kpis.isEmpty)
          const _TdpHint(
            icon: Icons.show_chart,
            text:
                'Följ upp det laget arbetar med i siffror, till exempel avslut '
                'per match eller insläppta mål, och registrera värdena över '
                'säsongen.',
          ),
        for (final kpi in plan.kpis)
          _TdpKpiCard(controller: controller, plan: plan, kpi: kpi),
      ];
    },
  );
}

/// A key figure: its target, the latest value and the values over time.
class _TdpKpiCard extends StatelessWidget {
  const _TdpKpiCard({
    required this.controller,
    required this.plan,
    required this.kpi,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final TeamKpi kpi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = plan.checkinsOfKpi(kpi.id);
    final latest = values.firstOrNull?.value;
    final reached = latest == null ? null : kpi.reaches(latest);
    return Card(
      key: ValueKey('tdp-kpi-${kpi.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _TdpKpiSheet.show(context, controller, kpi.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kpi.title, style: theme.textTheme.titleMedium),
                    Text(
                      kpi.target == null
                          ? 'Inget mål satt'
                          : 'Mål: ${kpi.higherIsBetter ? 'minst' : 'högst'} '
                                '${_tdpNumber(kpi.target!)} ${kpi.unit}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    _TdpBars(kpi: kpi, values: values),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    latest == null ? '–' : _tdpNumber(latest),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: switch (reached) {
                        true => const Color(0xFF2E7D5B),
                        false => const Color(0xFFB3261E),
                        null => null,
                      },
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (kpi.unit.isNotEmpty)
                    Text(kpi.unit, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The latest values (up to twelve, oldest left) as bars, green where they
/// reach the target, with the target as a line.
class _TdpBars extends StatelessWidget {
  const _TdpBars({required this.kpi, required this.values});
  final TeamKpi kpi;
  final List<TeamCheckin> values;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shown = values.take(12).toList().reversed.toList();
    if (shown.isEmpty) {
      return Text(
        'Inga värden än',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final numbers = [for (final v in shown) v.value!];
    final top = [...numbers, kpi.target ?? 0].reduce(max);
    final bottom = min(0.0, [...numbers, kpi.target ?? 0].reduce(min));
    final span = top - bottom == 0 ? 1.0 : top - bottom;
    return SizedBox(
      height: 36,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final value in numbers)
                  Expanded(
                    child: Tooltip(
                      message: _tdpNumber(value),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: max(3, 36 * (value - bottom) / span),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: switch (kpi.reaches(value)) {
                            true => const Color(0xFF2E7D5B),
                            false => colors.outline,
                            null => colors.primary,
                          },
                        ),
                      ),
                    ),
                  ),
                // Room for few values, so one bar is not the whole width.
                for (var i = numbers.length; i < 6; i++)
                  const Expanded(child: SizedBox()),
              ],
            ),
            if (kpi.target != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 36 * (kpi.target! - bottom) / span,
                child: Container(height: 1.5, color: colors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// A key figure on its own: its values with dates and notes, and the ways
/// to record a value or change the figure.
abstract final class _TdpKpiSheet {
  static Future<void> show(
    BuildContext context,
    _TdpController controller,
    String kpiId,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: controller,
      builder: (sheetContext, _) {
        final plan = controller.plan;
        final kpi = plan?.kpis.where((k) => k.id == kpiId).firstOrNull;
        if (plan == null || kpi == null) return const SizedBox(height: 120);
        final theme = Theme.of(sheetContext);
        final values = plan.checkinsOfKpi(kpi.id);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(kpi.title, style: theme.textTheme.titleLarge),
              Text(
                kpi.target == null
                    ? 'Inget mål satt'
                    : 'Mål: ${kpi.higherIsBetter ? 'minst' : 'högst'} '
                          '${_tdpNumber(kpi.target!)} ${kpi.unit}',
              ),
              const SizedBox(height: 12),
              _TdpBars(kpi: kpi, values: values),
              if (controller.canEdit) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('tdp-kpi-value'),
                      onPressed: () =>
                          _TdpCheckinDialog.kpi(sheetContext, controller, kpi),
                      icon: const Icon(Icons.add_chart),
                      label: const Text('Registrera värde'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _TdpKpiDialog.edit(
                          context,
                          controller,
                          plan,
                          kpi: kpi,
                        );
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Ändra nyckeltalet'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Text('Värden', style: theme.textTheme.titleMedium),
              if (values.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Inga värden än.'),
                ),
              for (final checkin in values)
                _TdpCheckinTile(
                  controller: controller,
                  plan: plan,
                  checkin: checkin,
                  unit: kpi.unit,
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// A new principle, or [principle] to change or remove.
abstract final class _TdpPrincipleDialog {
  static Future<void> edit(
    BuildContext context,
    _TdpController controller,
    SeasonPlan plan, {
    TeamPrinciple? principle,
  }) async {
    var area = principle?.area ?? PrincipleArea.attack;
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: principle?.title ?? '',
        second: principle?.description ?? '',
        builder: (context, title, description) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(principle == null ? 'Ny princip' : 'Ändra principen'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<PrincipleArea>(
                    isExpanded: true,
                    key: const Key('tdp-principle-area'),
                    initialValue: area,
                    decoration: const InputDecoration(labelText: 'Område'),
                    items: [
                      for (final value in PrincipleArea.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) => setState(() => area = value ?? area),
                  ),
                  TextField(
                    key: const Key('tdp-principle-title'),
                    controller: title,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Princip'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    key: const Key('tdp-principle-description'),
                    controller: description,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Beskrivning',
                      hintText: 'Hur det ser ut på planen',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (principle != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, ('delete', '', '')),
                  child: const Text('Ta bort'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Avbryt'),
              ),
              FilledButton(
                key: const Key('tdp-principle-save'),
                onPressed: title.text.trim().length >= 2
                    ? () => Navigator.pop(context, (
                        'save',
                        title.text.trim(),
                        description.text.trim(),
                      ))
                    : null,
                child: const Text('Spara'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    if (result.$1 == 'delete' && principle != null) {
      final sure = await _tdpConfirm(
        context,
        'Ta bort principen?',
        '"${principle.title}" tas bort ur lagets spelidé.',
      );
      if (!sure || !context.mounted) return;
      await controller.change(
        context,
        () => controller.services.deletePrinciple(plan, principle.id),
        done: 'Principen är borttagen.',
      );
    } else if (result.$1 == 'save') {
      await controller.change(
        context,
        () => controller.services.savePrinciple(
          plan,
          principleId: principle?.id,
          area: area,
          title: result.$2,
          description: result.$3,
        ),
        done: 'Principen är sparad.',
      );
    }
  }
}

/// A new key figure, or [kpi] to change or remove.
abstract final class _TdpKpiDialog {
  static Future<void> edit(
    BuildContext context,
    _TdpController controller,
    SeasonPlan plan, {
    TeamKpi? kpi,
  }) async {
    var higher = kpi?.higherIsBetter ?? true;
    var unitText = kpi?.unit ?? '';
    final result = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: kpi?.title ?? '',
        second: kpi?.target == null ? '' : _tdpNumber(kpi!.target!),
        builder: (context, title, target) => StatefulBuilder(
          builder: (context, setState) {
            final targetText = target.text.trim().replaceAll(',', '.');
            final valid =
                title.text.trim().length >= 2 &&
                (targetText.isEmpty || double.tryParse(targetText) != null);
            return AlertDialog(
              title: Text(kpi == null ? 'Nytt nyckeltal' : 'Ändra nyckeltalet'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('tdp-kpi-title'),
                      controller: title,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Nyckeltal',
                        hintText: 'Till exempel avslut per match',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('tdp-kpi-target'),
                            controller: target,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Mål (valfritt)',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            key: const Key('tdp-kpi-unit'),
                            initialValue: unitText,
                            onChanged: (value) => unitText = value,
                            maxLength: 20,
                            decoration: const InputDecoration(
                              labelText: 'Enhet',
                              hintText: 'st, %',
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TdpChoices<bool>(
                      key: const Key('tdp-kpi-direction'),
                      values: const {
                        true: 'Högre är bättre',
                        false: 'Lägre är bättre',
                      },
                      selected: higher,
                      onSelected: (value) => setState(() => higher = value),
                    ),
                  ],
                ),
              ),
              actions: [
                if (kpi != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, ('delete', '', '')),
                    child: const Text('Ta bort'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
                FilledButton(
                  key: const Key('tdp-kpi-save'),
                  onPressed: valid
                      ? () => Navigator.pop(context, (
                          'save',
                          title.text.trim(),
                          targetText,
                        ))
                      : null,
                  child: const Text('Spara'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    if (result.$1 == 'delete' && kpi != null) {
      final sure = await _tdpConfirm(
        context,
        'Ta bort nyckeltalet?',
        '"${kpi.title}" och alla dess värden tas bort.',
      );
      if (!sure || !context.mounted) return;
      await controller.change(
        context,
        () => controller.services.deleteKpi(plan, kpi.id),
        done: 'Nyckeltalet är borttaget.',
      );
    } else if (result.$1 == 'save') {
      await controller.change(
        context,
        () => controller.services.saveKpi(
          plan,
          kpiId: kpi?.id,
          title: result.$2,
          unit: unitText.trim(),
          target: result.$3.isEmpty ? null : double.parse(result.$3),
          higherIsBetter: higher,
        ),
        done: 'Nyckeltalet är sparat.',
      );
    }
  }
}
