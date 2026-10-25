part of '../../app/teamzone_app.dart';

/// Förberedelser for a training: its session from the Training module in
/// full, the theme, the goal and the exercises of each part with minutes,
/// organisation and coaching points, and the way into the module. Hidden
/// without the module, or for a player when nothing is published.
class _TrainingSessionSection extends StatefulWidget {
  const _TrainingSessionSection({
    super.key,
    required this.eventId,
    required this.calendar,
  });
  final String eventId;
  final CalendarServices calendar;

  @override
  State<_TrainingSessionSection> createState() =>
      _TrainingSessionSectionState();
}

class _TrainingSessionSectionState extends State<_TrainingSessionSection> {
  late Future<TrainingSession?> _session = _load();

  Future<TrainingSession?> _load() => widget.calendar.trainingSessions
      .getSession(widget.eventId)
      .then<TrainingSession?>((session) => session, onError: (_) => null);

  Future<void> _open() async {
    await _TrainingModule.openSession(
      context,
      eventId: widget.eventId,
      calendar: widget.calendar,
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
      final planned = session.revision > 0 && session.blocks.isNotEmpty;
      return Card(
        key: const Key('event-training-session'),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Träningspass',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (planned)
                    Text(
                      '${session.minutes} av ${session.eventMinutes} min',
                      style: theme.textTheme.labelLarge,
                    ),
                ],
              ),
              if (session.canEdit && planned)
                Text(
                  session.published
                      ? 'Publicerat för spelarna'
                      : 'Utkast, bara ledarna ser det',
                  style: theme.textTheme.bodySmall,
                ),
              if (session.theme.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(session.theme.trim(), style: theme.textTheme.titleSmall),
              ],
              if (session.goal.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(session.goal.trim()),
              ],
              if (!planned)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Inget pass planerat än.'),
                ),
              for (final part in TrainingPart.values)
                if (session.blocks.any((block) => block.part == part)) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${part.label} · ${session.blocks.where((block) => block.part == part).fold(0, (sum, block) => sum + block.minutes)} min',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  for (final block in session.blocks)
                    if (block.part == part)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${block.title} · ${block.minutes} min',
                              style: theme.textTheme.titleSmall,
                            ),
                            if (block.organisation.trim().isNotEmpty)
                              Text(block.organisation.trim()),
                            if (block.coachingPoints.trim().isNotEmpty)
                              Text(
                                'Coachpunkter: ${block.coachingPoints.trim()}',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                ],
              const SizedBox(height: 12),
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
                        ? (planned
                              ? 'Ändra i träningsmodulen'
                              : 'Planera passet')
                        : 'Öppna i träningsmodulen',
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
