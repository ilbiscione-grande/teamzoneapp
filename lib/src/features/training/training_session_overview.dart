part of '../../app/teamzone_app.dart';

class _TrainingSessionOverview extends StatelessWidget {
  const _TrainingSessionOverview({
    this.evaluation,
    required this.session,
    required this.blocks,
    required this.theme,
    required this.published,
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
  final Future<(EventDetails, SquadDetails)> event;
  final Future<EventPreparation> preparation;
  final Future<EventFollowup> goals;
  final Widget rosterEditor;
  final VoidCallback onPlanning, onPreparation, onRetry;
  final ValueChanged<bool> onPublished;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    Widget card(String title, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
    return ListView(
      key: const Key('training-session-overview'),
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  session.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${_trainingDay(context, session.startsAt)} – ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(session.endsAt))}',
                ),
                const SizedBox(height: 16),
                card(strings.feature('Träningspass'), [
                  TextField(
                    controller: theme,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: strings.feature('Träningsfokus'),
                    ),
                  ),
                  Text(
                    strings.trainingMinutes(
                      blocks.fold(0, (sum, block) => sum + block.minutes),
                      session.eventMinutes,
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
                  FilledButton.icon(
                    key: const Key('training-open-planning'),
                    onPressed: onPlanning,
                    icon: const Icon(Icons.view_timeline_outlined),
                    label: Text(strings.feature('Öppna planeringen')),
                  ),
                ]),
                card(strings.feature('Sessionstrupp'), [
                  Text(
                    strings.feature(
                      'Accepterade kallelser är förvalda när sessionstruppen skapas. Sparade val ändras inte automatiskt.',
                    ),
                  ),
                  rosterEditor,
                ]),
                card(strings.feature('Inställningar'), [
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
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(strings.domainValue(details.state)),
                          Text(
                            '${strings.feature('Plats')}: ${[details.locationName, details.locationPitch, details.locationSurface].whereType<String>().where((text) => text.trim().isNotEmpty).join(' · ')}',
                          ),
                          if (details.assemblyMinutesBefore != null)
                            Text(
                              '${strings.feature('Samling')}: ${details.assemblyMinutesBefore} min',
                            ),
                          Text(
                            strings.feature(
                              details.callupsRequired
                                  ? 'Kallelser används'
                                  : 'Utan kallelser',
                            ),
                          ),
                          for (final team in details.teams)
                            if (team['name'] is String ||
                                team['team_name'] is String)
                              Text('${team['name'] ?? team['team_name']}'),
                          if (details.description?.trim().isNotEmpty == true)
                            Text(details.description!),
                        ],
                      );
                    },
                  ),
                ]),
                card(strings.feature('Övningar'), [
                  if (blocks.isEmpty)
                    Text(strings.feature('Inga övningar än.')),
                  for (final block in blocks)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(block.title),
                      subtitle: Text(strings.feature(block.part.label)),
                      trailing: Text('${block.minutes} min'),
                      onTap: onPlanning,
                    ),
                ]),
                ?evaluation,
                card(strings.feature('Förberedelser'), [
                  FutureBuilder<EventFollowup>(
                    future: goals,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Text(
                          strings.feature(
                            'Träningsmålen visas under Förberedelser.',
                          ),
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
                              ),
                              for (final item in data.itemsOf(kind))
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
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
                              leading: const Icon(Icons.attach_file),
                              title: Text(file.name),
                            ),
                        ],
                      );
                    },
                  ),
                  TextButton(
                    onPressed: onPreparation,
                    child: Text(strings.feature('Öppna förberedelser')),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
