part of '../../app/teamzone_app.dart';

/// Laget → Översikt, for a player and their guardians (step 9,
/// PAR-METHOD-02): the player's injuries without the leaders' notes, and
/// under 15 the consent the player or a guardian gives. Nothing shows when
/// there is nothing to show or ask.
class _PlayerInjuryCard extends StatefulWidget {
  const _PlayerInjuryCard({required this.teamId, required this.services});
  final String teamId;
  final TeamDevelopmentServices services;

  @override
  State<_PlayerInjuryCard> createState() => _PlayerInjuryCardState();
}

class _PlayerInjuryCardState extends State<_PlayerInjuryCard> {
  TeamInjuries? _injuries;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run(() => widget.services.myInjuries(widget.teamId)));
  }

  @override
  void didUpdateWidget(covariant _PlayerInjuryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      _injuries = null;
      unawaited(_run(() => widget.services.myInjuries(widget.teamId)));
    }
  }

  Future<void> _run(Future<TeamInjuries> Function() action) async {
    setState(() => _saving = true);
    try {
      final injuries = await action();
      if (mounted) setState(() => _injuries = injuries);
    } catch (error) {
      AppErrors.caught('player_injury_card', error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Something to show: an injury, or a consent to give or withdraw.
  static bool _worthShowing(InjuryPlayer person) =>
      person.injuries.isNotEmpty || (!person.adult && !person.turnedOff);

  @override
  Widget build(BuildContext context) {
    final people = [
      for (final person in _injuries?.players ?? const <InjuryPlayer>[])
        if (_worthShowing(person)) person,
    ];
    if (people.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Card(
        key: const Key('player-injury-card'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.healing, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    _tdpText(context, 'Skador', 'Injuries'),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              for (final person in people) ...[
                if (people.length > 1 || !person.self)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(person.name, style: theme.textTheme.titleSmall),
                  ),
                for (final injury in person.injuries)
                  ListTile(
                    key: ValueKey('player-injury-${injury.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      injury.currentOn(today)
                          ? Icons.healing
                          : Icons.check_circle_outline,
                      color: injury.currentOn(today)
                          ? theme.colorScheme.error
                          : null,
                    ),
                    title: Text(injury.what),
                    subtitle: Text(
                      injury.backOn == null
                          ? _tdpText(
                              context,
                              'Sedan ${_tdpDate(context, injury.startedOn)}',
                              'Since ${_tdpDate(context, injury.startedOn)}',
                            )
                          : _tdpText(
                              context,
                              '${_tdpDate(context, injury.startedOn)} – tillbaka i träning ${_tdpDate(context, injury.backOn!)}',
                              '${_tdpDate(context, injury.startedOn)} – back in training ${_tdpDate(context, injury.backOn!)}',
                            ),
                    ),
                  ),
                if (!person.adult && !person.turnedOff)
                  CheckboxListTile(
                    key: ValueKey('player-injury-consent-${person.personId}'),
                    contentPadding: EdgeInsets.zero,
                    value: person.self
                        ? person.playerConsent
                        : person.guardianConsent,
                    onChanged: _saving
                        ? null
                        : (give) => _run(
                            () => widget.services.setInjuryConsent(
                              widget.teamId,
                              person.personId,
                              give ?? false,
                            ),
                          ),
                    title: Text(
                      person.self
                          ? _tdpText(
                              context,
                              'Jag godkänner att ledarna registrerar mina skador',
                              'I agree that the leaders register my injuries',
                            )
                          : _tdpText(
                              context,
                              'Jag godkänner att ledarna registrerar ${swedishGenitive(person.name)} skador',
                              'I agree that the leaders register ${person.name}\'s injuries',
                            ),
                    ),
                    subtitle: Text(
                      _tdpText(
                        context,
                        'Under 15 år behövs godkännande från spelaren, en vårdnadshavare och klubben. Ledarnas anteckningar visas inte här. Tar du tillbaka godkännandet tas skadorna bort.',
                        'Under 15, the player, a guardian and the club must agree. The leaders\' notes are not shown here. Withdrawing the consent deletes the injuries.',
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
