part of '../../app/teamzone_app.dart';

class _TrainingSessionOverview extends StatelessWidget {
  const _TrainingSessionOverview({
    this.evaluation,
    required this.session,
    required this.blocks,
    required this.theme,
    required this.published,
    required this.squad,
    required this.candidates,
    required this.onFocus,
    required this.event,
    required this.preparation,
    required this.goals,
    required this.rosterEditor,
    required this.onPlanning,
    required this.onPreparation,
    required this.onPublished,
    required this.onRetry,
  });
  final Widget? evaluation;
  final TrainingSession session;
  final List<TrainingBlock> blocks;
  final TextEditingController theme;
  final bool published;
  final List<TrainingBlockPlayer> squad;
  final Future<List<EventRosterPerson>> candidates;
  final VoidCallback onFocus;
  final Future<(EventDetails, SquadDetails)> event;
  final Future<EventPreparation> preparation;
  final Future<EventFollowup> goals;
  final Widget rosterEditor;
  final VoidCallback onPlanning, onPreparation, onRetry;
  final ValueChanged<bool> onPublished;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cards = _cards(context);
      final evaluation = this.evaluation == null
          ? null
          : _panelCards(context, this.evaluation!);
      if (constraints.maxWidth < 1200) {
        return _TrainingOverviewMobile(
          session: session,
          blocks: blocks,
          theme: theme,
          published: published,
          squad: squad,
          candidates: candidates,
          event: event,
          preparation: preparation,
          goals: goals,
          squadCard: cards.squad,
          settingsCard: cards.settings,
          evaluation: evaluation,
          onPlanning: onPlanning,
          onPreparation: onPreparation,
          onPublished: onPublished,
          onFocus: onFocus,
        );
      }
      Widget column(List<Widget?> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items.whereType<Widget>())
            Padding(padding: const EdgeInsets.only(bottom: 16), child: item),
        ],
      );
      return ListView(
        key: const Key('training-session-overview'),
        padding: const EdgeInsets.all(16),
        children: [
          // The programme's header already names the training.
          _stats(context),
          const SizedBox(height: 16),
          Row(
            key: const Key('training-dashboard-columns'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: column([cards.session, cards.settings])),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: column([cards.squad])),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: column([cards.exercises, cards.preparation, evaluation]),
              ),
            ],
          ),
        ],
      );
    },
  );

  /// Cards inside [child] drawn as the programme's panels.
  Widget _panelCards(BuildContext context, Widget child) {
    final colors = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        cardTheme: CardThemeData(
          color: colors.surfaceContainerLowest,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .6),
            ),
          ),
        ),
      ),
      child: child,
    );
  }

  /// The session at a glance: time, exercises, squad and visibility.
  Widget _stats(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final minutes = blocks.fold(0, (sum, block) => sum + block.minutes);
    final over = session.eventMinutes > 0 && minutes > session.eventMinutes;
    Widget tile(IconData icon, String label, String value, [Widget? extra]) =>
        Expanded(
          child: _ProgramPanel(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: colors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.feature(label),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      ?extra,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    // Equal tiles, whether or not they carry a bar.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(
            Icons.schedule,
            'Planerad tid',
            '$minutes / ${session.eventMinutes} min',
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: session.eventMinutes <= 0
                      ? 0
                      : (minutes / session.eventMinutes).clamp(0, 1),
                  minHeight: 5,
                  color: over ? colors.error : colors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          tile(
            Icons.view_timeline_outlined,
            'Övningar',
            strings.trainingExerciseCount(blocks.length),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  for (final part in TrainingPart.values)
                    if (blocks.any((block) => block.part == part))
                      Expanded(
                        flex: blocks
                            .where((block) => block.part == part)
                            .fold(1, (sum, block) => sum + block.minutes),
                        child: Container(
                          height: 5,
                          margin: const EdgeInsets.only(right: 2),
                          decoration: BoxDecoration(
                            color: _trainingPartColors(part).accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          tile(
            Icons.groups_outlined,
            'Sessionstrupp',
            strings.formatFeature('{count} spelare', {'count': squad.length}),
          ),
          const SizedBox(width: 16),
          tile(
            published
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            'Synlighet',
            strings.feature(
              published ? 'Visas för spelarna' : 'Bara ledarna ser passet',
            ),
          ),
        ],
      ),
    );
  }

  ({
    Widget session,
    Widget squad,
    Widget settings,
    Widget exercises,
    Widget preparation,
  })
  _cards(BuildContext context) {
    final strings = AppStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    Widget card(String title, List<Widget> children, {Widget? action}) =>
        _ProgramPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        );

    Widget link(String label, VoidCallback onPressed) => TextButton.icon(
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.chevron_right, size: 18),
      label: Text(strings.feature(label)),
    );

    final session = card(strings.feature('Träningspass'), [
      // The focus is edited in the header.
      Text(
        strings.trainingMinutes(
          blocks.fold(0, (sum, block) => sum + block.minutes),
          this.session.eventMinutes,
          planned: true,
        ),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        key: const Key('training-session-published'),
        contentPadding: EdgeInsets.zero,
        title: Text(strings.feature('Visa passet för spelarna')),
        value: published,
        onChanged: onPublished,
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('training-open-planning'),
          onPressed: onPlanning,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.view_timeline_outlined),
          label: Text(strings.feature('Öppna planeringen')),
        ),
      ),
    ]);
    final squad = card(strings.feature('Sessionstrupp'), [
      Text(
        strings.feature(
          'Accepterade kallelser är förvalda när sessionstruppen skapas. Sparade val ändras inte automatiskt.',
        ),
      ),
      rosterEditor,
    ]);
    final settings = card(strings.feature('Inställningar'), [
      FutureBuilder<(EventDetails, SquadDetails)>(
        future: event,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton(
              onPressed: onRetry,
              child: Text(
                strings.feature(
                  'Eventets inställningar kunde inte hämtas. Försök igen.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const LinearProgressIndicator();
          }
          final details = snapshot.data!.$1;
          final rows = <(IconData, String)>[
            (Icons.flag_outlined, strings.domainValue(details.state)),
            (
              Icons.place_outlined,
              [
                    details.locationName,
                    details.locationPitch,
                    details.locationSurface,
                  ]
                  .whereType<String>()
                  .where((text) => text.trim().isNotEmpty)
                  .join(' · '),
            ),
            if (details.assemblyMinutesBefore != null)
              (
                Icons.alarm_outlined,
                '${strings.feature('Samling')}: ${details.assemblyMinutesBefore} min',
              ),
            (
              Icons.mail_outline,
              strings.feature(
                details.callupsRequired
                    ? 'Kallelser används'
                    : 'Utan kallelser',
              ),
            ),
            for (final team in details.teams)
              if (team['name'] is String || team['team_name'] is String)
                (Icons.shield_outlined, '${team['name'] ?? team['team_name']}'),
            if (details.description?.trim().isNotEmpty == true)
              (Icons.notes, details.description!),
          ].where((row) => row.$2.trim().isNotEmpty);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (icon, text) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(text)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ]);
    final exercises = card(strings.feature('Övningar'), [
      if (blocks.isEmpty) Text(strings.feature('Inga övningar än.')),
      for (final (i, block) in blocks.indexed)
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPlanning,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _trainingPartColors(block.part).accent,
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    block.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${block.minutes} min', style: textTheme.bodySmall),
              ],
            ),
          ),
        ),
    ], action: link('Planering', onPlanning));
    final preparationCard = card(strings.feature('Förberedelser'), [
      FutureBuilder<EventFollowup>(
        future: goals,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Text(
              strings.feature('Träningsmålen visas under Förberedelser.'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final goal in snapshot.data!.kpis)
                Text('${goal.label}: ${goal.target}'),
            ],
          );
        },
      ),
      FutureBuilder<EventPreparation>(
        future: preparation,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton(
              onPressed: onRetry,
              child: Text(
                strings.feature(
                  'Förberedelserna kunde inte hämtas. Försök igen.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const LinearProgressIndicator();
          }
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.note.body.isNotEmpty) Text(data.note.body),
              for (final kind in [
                PreparationKind.focus,
                PreparationKind.material,
                PreparationKind.task,
                PreparationKind.agenda,
              ])
                if (data.itemsOf(kind).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.feature(switch (kind) {
                      'material' => 'Material',
                      'task' => 'Uppgifter',
                      'agenda' => 'Agenda',
                      _ => 'Fokus',
                    }),
                    style: textTheme.labelLarge,
                  ),
                  for (final item in data.itemsOf(kind))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        item.done
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(item.label),
                      subtitle: item.assigneeName == null
                          ? null
                          : Text(item.assigneeName!),
                    ),
                ],
              for (final file in data.files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.attach_file),
                  title: Text(file.name),
                ),
            ],
          );
        },
      ),
    ], action: link('Förberedelser', onPreparation));
    return (
      session: session,
      squad: squad,
      settings: settings,
      exercises: exercises,
      preparation: preparationCard,
    );
  }
}
