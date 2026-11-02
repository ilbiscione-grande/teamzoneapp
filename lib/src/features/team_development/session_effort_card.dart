part of '../../app/teamzone_app.dart';

/// "Hur ansträngande var passet?" under Uppföljning after a training
/// (PAR-PRIV-04): the player answers 1–10 for seven days, can take the
/// answer back or stop the questions; a guardian sees the player's answer.
/// Nothing shows when there is no question for the one reading.
class _SessionEffortCard extends StatefulWidget {
  const _SessionEffortCard({super.key, required this.eventId});
  final String eventId;

  @override
  State<_SessionEffortCard> createState() => _SessionEffortCardState();
}

class _SessionEffortCardState extends State<_SessionEffortCard> {
  SessionEffort? _effort;
  bool _saving = false;

  SessionEffortServices get _services => SessionEffortFeature.services;

  @override
  void initState() {
    super.initState();
    unawaited(_run(() => _services.get(widget.eventId)));
  }

  Future<void> _run(Future<SessionEffort> Function() action) async {
    setState(() => _saving = true);
    try {
      final effort = await action();
      if (mounted) {
        setState(() {
          _effort = effort;
        });
      }
    } catch (error) {
      AppErrors.caught('session_effort', error);
      if (mounted && _effort != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tdpText(
                context,
                'Svaret kunde inte sparas.',
                'The answer could not be saved.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _optOut() async {
    final sure = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(
          _tdpText(
            context,
            'Sluta svara på frågan?',
            'Stop answering the question?',
          ),
        ),
        content: Text(
          _tdpText(
            context,
            'Du får inte frågan efter passen längre, och dina tidigare svar tas bort. Du kan börja svara igen när du vill.',
            'You will no longer get the question after sessions, and your earlier answers are deleted. You can start answering again whenever you like.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.of(context).cancel),
          ),
          FilledButton(
            key: const Key('session-effort-opt-out-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_tdpText(context, 'Sluta svara', 'Stop answering')),
          ),
        ],
      ),
    );
    if (sure == true && mounted) {
      await _run(() => _services.setOptOut(widget.eventId, true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final effort = _effort;
    if (effort == null || effort.people.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final me = effort.me;
    final others = [
      for (final person in effort.people)
        if (!person.self) person,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const Key('session-effort'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _tdpText(
                  context,
                  'Hur ansträngande var passet?',
                  'How hard was the session?',
                ),
                style: theme.textTheme.titleMedium,
              ),
              if (me != null) ...[
                if (me.optedOut) ...[
                  const SizedBox(height: 4),
                  Text(
                    _tdpText(
                      context,
                      'Du har valt att inte svara på frågan.',
                      'You have chosen not to answer the question.',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('session-effort-opt-in'),
                      onPressed: _saving
                          ? null
                          : () => _run(
                              () => _services.setOptOut(widget.eventId, false),
                            ),
                      child: Text(
                        _tdpText(
                          context,
                          'Börja svara igen',
                          'Start answering again',
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    _tdpText(
                      context,
                      '1 är mycket lätt och 10 är så hårt det går. Bara du, lagets ledare och dina vårdnadshavare ser svaret.',
                      '1 is very easy and 10 is as hard as it gets. Only you, the team\'s leaders and your guardians see the answer.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var value = 1; value <= 10; value++)
                        ChoiceChip(
                          key: ValueKey('session-effort-$value'),
                          label: Text('$value'),
                          selected: me.rating == value,
                          onSelected: !me.canAnswer || _saving
                              ? null
                              : (_) => _run(
                                  () => _services.rate(
                                    widget.eventId,
                                    me.rating == value ? null : value,
                                  ),
                                ),
                        ),
                    ],
                  ),
                  if (!effort.open)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _tdpText(
                          context,
                          'Frågan kan besvaras i sju dagar efter passet.',
                          'The question can be answered for seven days after the session.',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('session-effort-opt-out'),
                      onPressed: _saving ? null : _optOut,
                      child: Text(
                        _tdpText(
                          context,
                          'Jag vill inte få frågan',
                          'I don\'t want the question',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              for (final person in others)
                ListTile(
                  key: ValueKey('session-effort-child-${person.personId}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(person.name),
                  subtitle: Text(
                    person.optedOut
                        ? _tdpText(
                            context,
                            'Har valt att inte svara.',
                            'Has chosen not to answer.',
                          )
                        : person.rating == null
                        ? _tdpText(
                            context,
                            'Har inte svarat.',
                            'Has not answered.',
                          )
                        : _tdpText(
                            context,
                            '${person.rating} av 10',
                            '${person.rating} of 10',
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
