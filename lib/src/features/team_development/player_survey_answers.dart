part of '../../app/teamzone_app.dart';

/// The Enkäter tab on a player's profile, for the team's leaders with
/// Säsongsplanering: the player's answers in the team's surveys, newest
/// first, as a basis for the player talk.
class _PlayerSurveyAnswersView extends StatefulWidget {
  const _PlayerSurveyAnswersView({
    super.key,
    required this.teamId,
    required this.personId,
    this.header,
  });
  final String teamId, personId;
  final Widget? header;

  @override
  State<_PlayerSurveyAnswersView> createState() =>
      _PlayerSurveyAnswersViewState();
}

class _PlayerSurveyAnswersViewState extends State<_PlayerSurveyAnswersView> {
  late Future<List<PlayerSurveyAnswer>> _load = _read();

  Future<List<PlayerSurveyAnswer>> _read() =>
      TeamSurveysFeature.services.playerAnswers(widget.teamId, widget.personId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return FutureBuilder<List<PlayerSurveyAnswer>>(
      future: _load,
      builder: (context, snapshot) {
        final answers = snapshot.data;
        final Widget body;
        if (snapshot.hasError) {
          final error = snapshot.error;
          body = error is TeamSurveyException && error.code == 'not_found'
              ? Text(
                  _tdpText(
                    context,
                    'Enkätsvar visas här för ledare med Säsongsplanering.',
                    'Survey answers show here for leaders with Season planning.',
                  ),
                  style: muted,
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        _tdpText(
                          context,
                          'Svaren kunde inte läsas.',
                          'The answers could not be read.',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _load = _read()),
                      child: Text(_tdpText(context, 'Försök igen', 'Retry')),
                    ),
                  ],
                );
        } else if (answers == null) {
          body = const Center(child: CircularProgressIndicator());
        } else if (answers.isEmpty) {
          body = Text(
            _tdpText(
              context,
              'Spelaren har inte svarat på någon enkät. Enkäter skickas från Säsongsplanering → Enkäter.',
              'The player has not answered a survey. Surveys are sent from Season planning → Surveys.',
            ),
            style: muted,
          );
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final answer in answers)
                Card(
                  key: Key('player-survey-${answer.surveyId}'),
                  child: ExpansionTile(
                    initiallyExpanded: answer == answers.first,
                    title: Text(answer.title),
                    subtitle: Text(
                      _tdpText(
                        context,
                        'Svarade ${_surveyDate(answer.updatedAt)} · ${answer.responseCount} svar i laget',
                        'Answered ${_surveyDate(answer.updatedAt)} · ${answer.responseCount} in the team',
                      ),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      _SurveyAnswerList(
                        questions: answer.questions,
                        answers: answer.answers,
                        averages: answer.responseCount > 1
                            ? answer.averages
                            : const {},
                      ),
                    ],
                  ),
                ),
            ],
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _load = _read());
            await _load.catchError((_) => const <PlayerSurveyAnswer>[]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 16),
              ],
              Text(
                _tdpText(context, 'Enkätsvar', 'Survey answers'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              body,
            ],
          ),
        );
      },
    );
  }
}

/// `/enkat/<token>`, from a notification: the player's own survey opens on
/// Webtools' page in the browser.
class _SurveyLinkPage extends StatefulWidget {
  const _SurveyLinkPage({required this.token});
  final String token;

  @override
  State<_SurveyLinkPage> createState() => _SurveyLinkPageState();
}

class _SurveyLinkPageState extends State<_SurveyLinkPage> {
  bool get _valid => RegExp(r'^[a-f0-9]{32}$').hasMatch(widget.token);

  @override
  void initState() {
    super.initState();
    if (_valid) unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await launchUrl(
        Uri.parse(surveyLinkUrl(widget.token)),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      AppErrors.caught('survey_link.open', error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_tdpText(context, 'Enkät', 'Survey'))),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _valid
                  ? _tdpText(
                      context,
                      'Enkäten öppnas i webbläsaren.',
                      'The survey opens in the browser.',
                    )
                  : _tdpText(
                      context,
                      'Länken är inte giltig.',
                      'The link is not valid.',
                    ),
              textAlign: TextAlign.center,
            ),
            if (_valid) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  _tdpText(context, 'Öppna enkäten', 'Open the survey'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
