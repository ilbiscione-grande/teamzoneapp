part of '../../app/teamzone_app.dart';

/// Säsongen: what the team's players and guardians see of the plan, chosen
/// per part. Check-ins, notes and key figures always stay the leaders'.
class _TdpSharingCard extends StatelessWidget {
  const _TdpSharingCard({required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  Future<void> _set(BuildContext context, PlanSharing sharing) => controller
      .change(context, () => controller.services.setSharing(plan, sharing));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sharing = plan.sharing;
    final parts = [
      (
        'vision',
        'Inriktning',
        'Vilket lag ni vill vara',
        sharing.vision,
        (bool on) => PlanSharing(
          vision: on,
          periods: sharing.periods,
          principles: sharing.principles,
          goals: sharing.goals,
        ),
      ),
      (
        'periods',
        'Perioder och fokus',
        'Vad laget arbetar med just nu',
        sharing.periods,
        (bool on) => PlanSharing(
          vision: sharing.vision,
          periods: on,
          principles: sharing.principles,
          goals: sharing.goals,
        ),
      ),
      (
        'principles',
        'Spelprinciper',
        'Spelidén i spelets fyra skeden',
        sharing.principles,
        (bool on) => PlanSharing(
          vision: sharing.vision,
          periods: sharing.periods,
          principles: on,
          goals: sharing.goals,
        ),
      ),
      (
        'goals',
        'Säsongs- och periodmål',
        'Med de länkar ni visar för spelarna',
        sharing.goals,
        (bool on) => PlanSharing(
          vision: sharing.vision,
          periods: sharing.periods,
          principles: sharing.principles,
          goals: on,
        ),
      ),
    ];
    return Card(
      key: const Key('tdp-sharing'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                AppStrings.of(context).feature('Delas med spelarna'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: Text(
                sharing.any
                    ? (AppStrings.of(context).isSwedish
                          ? 'Spelarna och vårdnadshavarna ser det delade under Laget. Avstämningar, anteckningar och nyckeltal är ledarnas.'
                          : 'Players and guardians see shared content under Team. Check-ins, notes and metrics are for coaches.')
                    : (AppStrings.of(context).isSwedish
                          ? 'Inget delas än. Spelarna och vårdnadshavarna ser det ni delar under Laget.'
                          : 'Nothing is shared yet. Players and guardians see what you share under Team.'),
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final (key, title, subtitle, on, next) in parts)
              SwitchListTile(
                key: ValueKey('tdp-share-$key'),
                title: Text(AppStrings.of(context).feature(title)),
                subtitle: Text(AppStrings.of(context).feature(subtitle)),
                value: on,
                onChanged: controller.canEdit
                    ? (value) => _set(context, next(value))
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// A goal's links in its sheet: open, shown to the players or not, removed;
/// and a new one.
class _TdpGoalLinks extends StatelessWidget {
  const _TdpGoalLinks({
    required this.controller,
    required this.plan,
    required this.goal,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final TeamGoal goal;

  Future<void> _add(BuildContext context) async {
    var visible = false;
    final result = await showDialog<(String, String, bool)>(
      context: context,
      builder: (context) => _TdpTexts(
        first: '',
        second: '',
        builder: (context, title, url) => StatefulBuilder(
          builder: (context, setState) {
            final valid =
                title.text.trim().isNotEmpty &&
                RegExp(r'^https://\S{3,}$').hasMatch(url.text.trim());
            return AlertDialog(
              title: Text(AppStrings.of(context).feature('Ny länk')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('tdp-link-title'),
                      controller: title,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).feature('Namn'),
                        hintText: AppStrings.of(
                          context,
                        ).feature('Till exempel en film eller en övning'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      key: const Key('tdp-link-url'),
                      controller: url,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).feature('Adress'),
                        hintText: 'https://…',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        AppStrings.of(context).feature('Visa för spelarna'),
                      ),
                      subtitle: Text(
                        AppStrings.of(
                          context,
                        ).feature('Syns när målen delas med spelarna.'),
                      ),
                      value: visible,
                      onChanged: (value) => setState(() => visible = value),
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
                  key: const Key('tdp-link-save'),
                  onPressed: valid
                      ? () => Navigator.pop(context, (
                          title.text.trim(),
                          url.text.trim(),
                          visible,
                        ))
                      : null,
                  child: Text(AppStrings.of(context).feature('Lägg till')),
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
      () => controller.services.addGoalLink(
        plan,
        goalId: goal.id,
        title: result.$1,
        url: result.$2,
        visible: result.$3,
      ),
      done: AppStrings.of(context).feature('Länken är tillagd.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (goal.links.isEmpty && !controller.canEdit) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.of(context).feature('Länkar'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (controller.canEdit && goal.links.length < 10)
              TextButton.icon(
                key: const Key('tdp-goal-add-link'),
                onPressed: () => _add(context),
                icon: const Icon(Icons.add_link),
                label: Text(AppStrings.of(context).feature('Lägg till')),
              ),
          ],
        ),
        if (goal.links.isEmpty)
          Text(
            AppStrings.of(
              context,
            ).feature('Filmer, övningar eller dokument som hör till målet.'),
          ),
        for (final link in goal.links)
          ListTile(
            key: ValueKey('tdp-link-${link.id}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link),
            title: Text(link.title),
            subtitle: Text(
              AppStrings.of(
                context,
              ).feature(link.visible ? 'Visas för spelarna' : 'Bara ledarna'),
            ),
            onTap: () => launchUrl(
              Uri.parse(link.url),
              mode: LaunchMode.externalApplication,
            ),
            trailing: controller.canEdit
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: link.visible
                            ? AppStrings.of(
                                context,
                              ).feature('Dölj för spelarna')
                            : AppStrings.of(
                                context,
                              ).feature('Visa för spelarna'),
                        icon: Icon(
                          link.visible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => controller.change(
                          context,
                          () => controller.services.changeGoalLink(
                            plan,
                            link.id,
                            visible: !link.visible,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: AppStrings.of(
                          context,
                        ).feature('Ta bort länken'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => controller.change(
                          context,
                          () => controller.services.changeGoalLink(
                            plan,
                            link.id,
                            visible: null,
                          ),
                          done: AppStrings.of(
                            context,
                          ).feature('Länken är borttagen.'),
                        ),
                      ),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}

/// MFD-12: what the team's plan says for an event's day, beside its
/// preparation: the period's focus, the principles and the goals ahead.
/// With [onTake], a tap takes a principle or goal over (as training focus,
/// or into the match plan); it never changes the event by itself.
class _PlanSuggestionBox extends StatelessWidget {
  const _PlanSuggestionBox({
    required this.suggestion,
    this.taken = const {},
    this.onTake,
    this.takeHint,
  });
  final TeamPlanSuggestion suggestion;

  /// Already taken over, in lower case: shown without the add.
  final Set<String> taken;
  final Future<Object?> Function(String label)? onTake;
  final String? takeHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget chips(String title, List<String> labels) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final label in labels)
              if (onTake == null || taken.contains(label.toLowerCase()))
                Chip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  avatar: taken.contains(label.toLowerCase())
                      ? const Icon(Icons.check, size: 16)
                      : null,
                )
              else
                ActionChip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add, size: 16),
                  onPressed: () => onTake!(label),
                ),
          ],
        ),
      ],
    );
    return Container(
      key: const Key('plan-suggestion'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  suggestion.periodName == null
                      ? AppStrings.of(context).feature('Från lagets plan')
                      : '${AppStrings.of(context).feature('Från lagets plan')} · ${suggestion.periodName}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (suggestion.periodFocus.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(suggestion.periodFocus.trim()),
          ],
          if (suggestion.goals.isNotEmpty)
            chips(
              AppStrings.of(context).feature('Mål framåt'),
              suggestion.goals,
            ),
          if (suggestion.principles.isNotEmpty)
            chips(AppStrings.of(context).feature('Spelprinciper'), [
              for (final principle in suggestion.principles) principle.title,
            ]),
          if (onTake != null && takeHint != null) ...[
            const SizedBox(height: 8),
            Text(takeHint!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
