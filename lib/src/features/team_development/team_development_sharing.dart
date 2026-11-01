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
    final strings = AppStrings.of(context);
    final parts = [
      (
        'vision',
        strings.feature('Inriktning'),
        strings.feature('Vilket lag ni vill vara'),
        sharing.vision,
        (bool on) => sharing.copyWith(vision: on),
      ),
      (
        'periods',
        strings.feature('Perioder och fokus'),
        strings.feature('Vad laget arbetar med just nu'),
        sharing.periods,
        (bool on) => sharing.copyWith(periods: on),
      ),
      (
        'blocks',
        _tdpText(context, 'Block', 'Blocks'),
        _tdpText(
          context,
          'Blockens fokus och principer',
          "The blocks' focus and principles",
        ),
        sharing.blocks,
        (bool on) => sharing.copyWith(blocks: on),
      ),
      (
        'principles',
        strings.feature('Spelprinciper'),
        strings.feature('Spelidén i spelets fyra skeden'),
        sharing.principles,
        (bool on) => sharing.copyWith(principles: on),
      ),
      (
        'goals',
        _tdpText(context, 'Mål', 'Goals'),
        _tdpText(
          context,
          'Säsongens, periodernas och blockens mål, med de länkar ni visar för spelarna',
          "The season's, periods' and blocks' goals, with the links you show the players",
        ),
        sharing.goals,
        (bool on) => sharing.copyWith(goals: on),
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
                title: Text(title),
                subtitle: Text(subtitle),
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
