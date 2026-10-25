part of '../../app/teamzone_app.dart';

/// Förberedelser for a training: its session in the Training module, how
/// far it is planned, and the way into it. Hidden without the module, or
/// for a player when nothing is published.
class _TrainingSessionSection extends StatefulWidget {
  const _TrainingSessionSection({
    super.key,
    required this.eventId,
    required this.services,
  });
  final String eventId;
  final TrainingServices services;

  @override
  State<_TrainingSessionSection> createState() =>
      _TrainingSessionSectionState();
}

class _TrainingSessionSectionState extends State<_TrainingSessionSection> {
  late Future<TrainingSession?> _session = _load();

  Future<TrainingSession?> _load() => widget.services
      .getSession(widget.eventId)
      .then<TrainingSession?>((session) => session, onError: (_) => null);

  Future<void> _open() async {
    await _TrainingModule.openSession(
      context,
      eventId: widget.eventId,
      services: widget.services,
    );
    if (mounted) {
      setState(() {
        _session = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TrainingSession?>(
    future: _session,
    builder: (context, snapshot) {
      final session = snapshot.data;
      if (session == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final status = session.revision == 0
          ? 'Inget pass planerat än'
          : [
              '${session.blocks.length} övningar · ${session.minutes} av ${session.eventMinutes} min',
              session.published
                  ? 'Publicerat för spelarna'
                  : 'Utkast, bara ledarna ser det',
            ].join(' · ');
      return Card(
        key: const Key('event-training-session'),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Träningspass', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(session.canEdit ? status : session.theme),
              if (!session.canEdit)
                for (final block in session.blocks)
                  Text('${block.title} · ${block.minutes} min'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  key: const Key('event-training-session-open'),
                  onPressed: _open,
                  icon: Icon(
                    session.canEdit
                        ? Icons.edit_note
                        : Icons.fitness_center_outlined,
                  ),
                  label: Text(
                    session.canEdit
                        ? (session.revision == 0
                              ? 'Planera passet'
                              : 'Öppna passet')
                        : 'Visa passet',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
