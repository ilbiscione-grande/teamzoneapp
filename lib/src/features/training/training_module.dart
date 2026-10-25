part of '../../app/teamzone_app.dart';

/// The Training module (decision package 11, MFD-08) as its own app:
/// Översikt with the next training and the team's trainings, each opening
/// its session.
abstract final class _TrainingModule {
  static const _key = 'module.training';

  static Future<void> open(
    BuildContext context, {
    required TeamZoneContext team,
    required CalendarServices calendar,
  }) => _ModuleShell.open(
    context,
    _ModuleShell(
      title: 'Träning',
      subtitle: team.teamName,
      icon: Icons.fitness_center,
      seed: _ModuleShell.seeds[_key]!,
      sections: [
        _ModuleSection(
          label: 'Översikt',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          builder: (_) => _TrainingOverview(
            teamId: team.teamId!,
            services: calendar.trainingSessions,
          ),
        ),
      ],
    ),
  );

  /// One training's session in the module's look, from inside the module
  /// or from the event in TeamZone.
  static Future<void> openSession(
    BuildContext context, {
    required String eventId,
    required TrainingServices services,
  }) => _ModuleScope.push<void>(
    context,
    (_) => _TrainingSessionPage(eventId: eventId, services: services),
    seed: _ModuleShell.seeds[_key],
  );
}

String _trainingDay(BuildContext context, DateTime value) {
  final date = MaterialLocalizations.of(context).formatMediumDate(value);
  final time = TimeOfDay.fromDateTime(value).format(context);
  return '$date $time';
}

/// A session's status in words and icon.
(String, IconData) _sessionStatus(String session) => switch (session) {
  'published' => ('Publicerat', Icons.check_circle),
  'draft' => ('Utkast', Icons.edit_note),
  _ => ('Inget pass', Icons.add_circle_outline),
};

/// Översikt: the next training up front, then the coming or past ones.
class _TrainingOverview extends StatefulWidget {
  const _TrainingOverview({required this.teamId, required this.services});
  final String teamId;
  final TrainingServices services;

  @override
  State<_TrainingOverview> createState() => _TrainingOverviewState();
}

class _TrainingOverviewState extends State<_TrainingOverview> {
  bool _past = false;
  late Future<List<ModuleTraining>> _upcoming = _load(past: false);
  Future<List<ModuleTraining>>? _pastLoad;

  Future<List<ModuleTraining>> _load({required bool past}) {
    final now = DateTime.now();
    return past
        ? widget.services.listTrainings(
            teamId: widget.teamId,
            from: now.subtract(const Duration(days: 120)),
            to: now,
          )
        : widget.services.listTrainings(
            teamId: widget.teamId,
            from: now.subtract(const Duration(hours: 3)),
            to: now.add(const Duration(days: 90)),
          );
  }

  void _reload() => setState(() {
    _upcoming = _load(past: false);
    if (_pastLoad != null) _pastLoad = _load(past: true);
  });

  Future<void> _open(ModuleTraining training) async {
    await _TrainingModule.openSession(
      context,
      eventId: training.eventId,
      services: widget.services,
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ModuleTraining>>(
    future: _upcoming,
    builder: (context, upcoming) {
      if (upcoming.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Träningarna kunde inte hämtas. Passen planeras av ledare '
                  'med behörighet för träningsupplägg.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: _reload,
                  child: const Text('Försök igen'),
                ),
              ],
            ),
          ),
        );
      }
      if (!upcoming.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final trainings = [
        for (final training in upcoming.data!)
          if (training.state != 'cancelled') training,
      ];
      final next = trainings.firstOrNull;
      return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            for (final child in [
              if (next == null)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.event_busy),
                    title: Text('Inga kommande träningar'),
                    subtitle: Text(
                      'Lägg in träningar i kalendern, så planerar du passen här.',
                    ),
                  ),
                )
              else
                _NextTrainingCard(training: next, onOpen: () => _open(next)),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                key: const Key('training-module-period'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Kommande')),
                  ButtonSegment(value: true, label: Text('Tidigare')),
                ],
                selected: {_past},
                onSelectionChanged: (value) => setState(() {
                  _past = value.first;
                  _pastLoad ??= _load(past: true);
                }),
              ),
              const SizedBox(height: 8),
              if (!_past)
                ..._rows(
                  trainings.where((t) => t.eventId != next?.eventId),
                  'Inga fler kommande träningar.',
                )
              else
                FutureBuilder<List<ModuleTraining>>(
                  future: _pastLoad,
                  builder: (context, past) => past.hasData
                      ? Column(
                          children: _rows(
                            past.data!.reversed,
                            'Inga tidigare träningar.',
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: past.hasError
                                ? const Text('Träningarna kunde inte hämtas.')
                                : const CircularProgressIndicator(),
                          ),
                        ),
                ),
            ])
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: child,
                ),
              ),
          ],
        ),
      );
    },
  );

  List<Widget> _rows(Iterable<ModuleTraining> trainings, String empty) {
    if (trainings.isEmpty) {
      return [Padding(padding: const EdgeInsets.all(16), child: Text(empty))];
    }
    return [
      for (final training in trainings)
        Card(
          child: ListTile(
            key: ValueKey('training-row-${training.eventId}'),
            leading: Icon(_sessionStatus(training.session).$2),
            title: Text(
              training.theme?.trim().isNotEmpty == true
                  ? training.theme!
                  : training.title,
            ),
            subtitle: Text(
              [
                _trainingDay(context, training.startsAt),
                _sessionStatus(training.session).$1,
                if (training.blocks > 0)
                  '${training.blocks} övningar · ${training.minutes} min',
                if (!training.startsAt.isAfter(DateTime.now()) &&
                    training.state != 'cancelled')
                  training.evaluated
                      ? 'Utvärderad${training.rating == null ? '' : ' ${'★' * training.rating!}'}'
                      : 'Ej utvärderad',
                if (training.state == 'cancelled') 'Inställd',
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(training),
          ),
        ),
    ];
  }
}

class _NextTrainingCard extends StatelessWidget {
  const _NextTrainingCard({required this.training, required this.onOpen});
  final ModuleTraining training;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(training.startsAt).difference(today).inDays;
    final when = switch (days) {
      <= 0 => 'Idag',
      1 => 'Imorgon',
      _ => 'Om $days dagar',
    };
    final length = training.endsAt.difference(training.startsAt).inMinutes;
    const white = TextStyle(color: Colors.white);
    return DecoratedBox(
      key: const Key('module-next-training'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, Colors.black, 0.45)!,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$when · ${_trainingDay(context, training.startsAt)}',
              style: white.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              training.theme?.trim().isNotEmpty == true
                  ? training.theme!
                  : training.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              training.blocks == 0
                  ? 'Inget pass planerat än · $length min'
                  : '${training.blocks} övningar · ${training.minutes} av $length min · '
                        '${_sessionStatus(training.session).$1}',
              style: white,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const Key('module-next-training-open'),
              onPressed: onOpen,
              icon: Icon(training.blocks == 0 ? Icons.add : Icons.edit_note),
              label: Text(
                training.blocks == 0 ? 'Planera passet' : 'Öppna passet',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
