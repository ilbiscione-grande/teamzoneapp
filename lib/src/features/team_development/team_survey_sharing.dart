part of '../../app/teamzone_app.dart';

typedef _SurveyChange =
    Future<bool> Function(Future<TeamSurvey> Function() run, {String? done});

/// Enkät → Dela: open or close the survey, the players' personal links and
/// the open link. Registered players are told in the app when the survey
/// is open; the others get their link from a leader (copied into a text
/// message, an email or a chat).
class _SurveySharing extends StatelessWidget {
  const _SurveySharing({
    required this.survey,
    required this.busy,
    required this.onChange,
    required this.onEdit,
    required this.onRefresh,
  });
  final TeamSurvey survey;
  final bool busy;
  final _SurveyChange onChange;
  final VoidCallback onEdit;
  final Future<void> Function() onRefresh;

  TeamSurveyServices get _services => TeamSurveysFeature.services;

  Future<void> _copy(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _tdpText(context, 'Länken är kopierad.', 'Link copied.');
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addPlayers(BuildContext context) async {
    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (_) => _SurveyPlayerPicker(players: survey.uninvited),
    );
    if (chosen == null || chosen.isEmpty || !context.mounted) return;
    await onChange(
      () => _services.invite(survey.id, chosen),
      done: _tdpText(
        context,
        survey.open
            ? 'Länkarna är klara. Spelare med konto har fått en notis.'
            : 'Länkarna är klara. Spelare med konto får en notis när du öppnar enkäten.',
        'The links are ready.',
      ),
    );
  }

  Future<void> _remove(BuildContext context, SurveyInvite invite) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tdpText(context, 'Ta bort länken?', 'Remove link?')),
        content: Text(
          _tdpText(
            context,
            '${invite.name}s länk slutar fungera.',
            '${invite.name}\'s link stops working.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tdpText(context, 'Avbryt', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tdpText(context, 'Ta bort', 'Remove')),
          ),
        ],
      ),
    );
    if (sure == true) await onChange(() => _services.removeInvite(invite.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final canEdit = survey.canEdit && !busy;
    final answered = survey.invites.where((i) => i.answeredAt != null).length;
    final openUrl = survey.openUrl;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_surveyStateIcon(survey.state)),
                      const SizedBox(width: 8),
                      Text(
                        _surveyStateLabel(context, survey.state),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(switch (survey.state) {
                    'open' => _tdpText(
                      context,
                      'Länkarna tar emot svar. En spelare kan öppna sin länk igen och ändra sina svar.',
                      'The links take answers. A player can open their link again and change the answers.',
                    ),
                    'closed' => _tdpText(
                      context,
                      'Enkäten tar inte emot fler svar. Svaren finns kvar.',
                      'The survey takes no more answers. The answers are kept.',
                    ),
                    _ => _tdpText(
                      context,
                      'Ett utkast. Länkarna fungerar först när du öppnar enkäten.',
                      'A draft. The links work once you open the survey.',
                    ),
                  }),
                  const SizedBox(height: 4),
                  Text(
                    _tdpText(
                      context,
                      '${survey.questions.length} frågor',
                      '${survey.questions.length} questions',
                    ),
                    style: muted,
                  ),
                  if (survey.canEdit) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!survey.open)
                          FilledButton.icon(
                            key: const Key('survey-open'),
                            onPressed: canEdit
                                ? () => onChange(
                                    () => _services.setState(survey.id, 'open'),
                                    done: _tdpText(
                                      context,
                                      'Enkäten är öppen.',
                                      'The survey is open.',
                                    ),
                                  )
                                : null,
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              survey.closed
                                  ? _tdpText(context, 'Öppna igen', 'Reopen')
                                  : _tdpText(
                                      context,
                                      'Öppna enkäten',
                                      'Open survey',
                                    ),
                            ),
                          ),
                        if (survey.open)
                          OutlinedButton.icon(
                            key: const Key('survey-close'),
                            onPressed: canEdit
                                ? () => onChange(
                                    () =>
                                        _services.setState(survey.id, 'closed'),
                                    done: _tdpText(
                                      context,
                                      'Enkäten är stängd.',
                                      'The survey is closed.',
                                    ),
                                  )
                                : null,
                            icon: const Icon(Icons.lock_outline),
                            label: Text(
                              _tdpText(
                                context,
                                'Stäng enkäten',
                                'Close survey',
                              ),
                            ),
                          ),
                        if (!survey.hasAnswers)
                          TextButton.icon(
                            onPressed: canEdit ? onEdit : null,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(
                              _tdpText(context, 'Ändra frågorna', 'Edit'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _tdpText(context, 'Personliga länkar', 'Personal links'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _tdpText(
              context,
              'Svaren kopplas direkt till spelaren. Spelare med konto får en notis i appen. Kopiera länken till de andra och skicka den till exempel som sms. Länken är personlig, så dela den inte i en gruppchatt.',
              'The answers belong to the player at once. Players with an account get a notification. Copy the link for the others and send it, for example by text message. The link is personal: do not share it in a group chat.',
            ),
            style: muted,
          ),
          if (survey.invites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _tdpText(
                  context,
                  '$answered av ${survey.invites.length} har svarat',
                  '$answered of ${survey.invites.length} have answered',
                ),
                style: theme.textTheme.labelLarge,
              ),
            ),
          for (final invite in survey.invites)
            ListTile(
              key: Key('survey-invite-${invite.personId}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                invite.answeredAt != null
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: invite.answeredAt != null
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              title: Text(invite.name),
              subtitle: Text(
                [
                  if (invite.answeredAt case final at?)
                    _tdpText(
                      context,
                      'Svarade ${_surveyDate(at)}',
                      'Answered ${_surveyDate(at)}',
                    )
                  else
                    _tdpText(context, 'Inte svarat', 'Not answered'),
                  if (invite.notifiedAt != null)
                    _tdpText(context, 'notis skickad', 'notified')
                  else if (!invite.hasAccount)
                    _tdpText(context, 'inget konto', 'no account'),
                ].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _tdpText(context, 'Kopiera länk', 'Copy link'),
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copy(context, invite.url),
                  ),
                  if (survey.canEdit && invite.answeredAt == null)
                    IconButton(
                      tooltip: _tdpText(context, 'Ta bort länken', 'Remove'),
                      icon: const Icon(Icons.close),
                      onPressed: canEdit
                          ? () => _remove(context, invite)
                          : null,
                    ),
                ],
              ),
            ),
          if (survey.canEdit && survey.uninvited.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  key: const Key('survey-add-players'),
                  onPressed: canEdit ? () => _addPlayers(context) : null,
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(
                    survey.invites.isEmpty
                        ? _tdpText(
                            context,
                            'Skapa länkar till spelarna',
                            'Create links for the players',
                          )
                        : _tdpText(context, 'Lägg till spelare', 'Add players'),
                  ),
                ),
              ),
            ),
          const Divider(height: 40),
          SwitchListTile(
            key: const Key('survey-open-link'),
            contentPadding: EdgeInsets.zero,
            value: openUrl != null,
            onChanged: canEdit
                ? (on) => onChange(() => _services.setOpenLink(survey.id, on))
                : null,
            title: Text(_tdpText(context, 'Öppen länk', 'Open link')),
            subtitle: Text(
              _tdpText(
                context,
                'En gemensam länk där man skriver sitt namn, till exempel för den som inte finns i truppen. Svaren kopplar du sedan till en spelare under Svar.',
                'One link for everyone, where one writes one\'s name. You link the answers to a player under Answers.',
              ),
            ),
          ),
          if (openUrl != null)
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    openUrl,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: _tdpText(context, 'Kopiera länk', 'Copy link'),
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copy(context, openUrl),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _surveyDate(DateTime value) =>
    '${value.day}/${value.month} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

/// The team's players without a link, all chosen at first.
class _SurveyPlayerPicker extends StatefulWidget {
  const _SurveyPlayerPicker({required this.players});
  final List<SurveyPlayer> players;

  @override
  State<_SurveyPlayerPicker> createState() => _SurveyPlayerPickerState();
}

class _SurveyPlayerPickerState extends State<_SurveyPlayerPicker> {
  late final Set<String> _chosen = {
    for (final player in widget.players) player.personId,
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tdpText(context, 'Välj spelare', 'Choose players')),
    content: SizedBox(
      width: 420,
      child: ListView(
        shrinkWrap: true,
        children: [
          CheckboxListTile(
            value: _chosen.length == widget.players.length,
            title: Text(_tdpText(context, 'Alla', 'All')),
            onChanged: (all) => setState(() {
              _chosen.clear();
              if (all == true) {
                _chosen.addAll(widget.players.map((p) => p.personId));
              }
            }),
          ),
          const Divider(height: 1),
          for (final player in widget.players)
            CheckboxListTile(
              value: _chosen.contains(player.personId),
              title: Text(player.name),
              subtitle: player.hasAccount
                  ? null
                  : Text(_tdpText(context, 'Inget konto', 'No account')),
              onChanged: (on) => setState(
                () => on == true
                    ? _chosen.add(player.personId)
                    : _chosen.remove(player.personId),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_tdpText(context, 'Avbryt', 'Cancel')),
      ),
      FilledButton(
        onPressed: _chosen.isEmpty
            ? null
            : () => Navigator.pop(context, _chosen.toList()),
        child: Text(
          _tdpText(
            context,
            'Skapa ${_chosen.length} länkar',
            'Create ${_chosen.length} links',
          ),
        ),
      ),
    ],
  );
}
