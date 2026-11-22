part of '../../app/teamzone_app.dart';

/// Säsongsplanering → Enkäter (2026-11-22): the team's surveys. A new one
/// starts empty or from the template for individual player talks. A survey
/// opens on its own page with its links and answers.
class _TdpSurveys extends StatefulWidget {
  const _TdpSurveys({required this.teamId});
  final String teamId;

  @override
  State<_TdpSurveys> createState() => _TdpSurveysState();
}

class _TdpSurveysState extends State<_TdpSurveys> {
  TeamSurveyServices get _services => TeamSurveysFeature.services;
  late Future<TeamSurveys> _load = _services.list(widget.teamId);

  void _reload() => setState(() => _load = _services.list(widget.teamId));

  Future<void> _create({required bool template}) async {
    final saved = await _SurveyEditor.open(
      context,
      teamId: widget.teamId,
      template: template ? _playerTalkTemplate(context) : null,
    );
    if (saved == null || !mounted) return;
    _reload();
    await _SurveyPage.open(context, saved);
    if (mounted) _reload();
  }

  Future<void> _open(SurveySummary summary) async {
    await _SurveyPage.open(context, null, surveyId: summary.id);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<TeamSurveys>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SurveyMessage(
            text: _tdpText(
              context,
              'Enkäterna kunde inte läsas.',
              'The surveys could not be read.',
            ),
            onRetry: _reload,
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _load;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                _tdpText(context, 'Enkäter', 'Surveys'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _tdpText(
                  context,
                  'Skicka en kort enkät till spelarna, till exempel inför spelarsamtalen. Varje spelare får en egen länk och behöver inget konto. Bara lagets ledare ser svaren.',
                  'Send the players a short survey, for instance before player talks. Each player gets a personal link and needs no account. Only the team\'s leaders see the answers.',
                ),
                style: theme.textTheme.bodyMedium,
              ),
              if (data.canEdit) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('survey-new-template'),
                      onPressed: () => _create(template: true),
                      icon: const Icon(Icons.record_voice_over_outlined),
                      label: Text(
                        _tdpText(
                          context,
                          'Inför spelarsamtal',
                          'Before player talks',
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('survey-new'),
                      onPressed: () => _create(template: false),
                      icon: const Icon(Icons.add),
                      label: Text(_tdpText(context, 'Tom enkät', 'Empty')),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              if (data.surveys.isEmpty)
                Text(
                  _tdpText(
                    context,
                    'Laget har inga enkäter ännu.',
                    'The team has no surveys yet.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final survey in data.surveys)
                Card(
                  child: ListTile(
                    key: Key('survey-${survey.id}'),
                    leading: Icon(_surveyStateIcon(survey.state)),
                    title: Text(survey.title),
                    subtitle: Text(
                      [
                        _surveyStateLabel(context, survey.state),
                        _tdpText(
                          context,
                          '${survey.answered} svar',
                          '${survey.answered} answers',
                        ),
                        if (survey.invited > 0)
                          _tdpText(
                            context,
                            '${survey.invited} personliga länkar',
                            '${survey.invited} personal links',
                          ),
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(survey),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

IconData _surveyStateIcon(String state) => switch (state) {
  'open' => Icons.mark_email_unread_outlined,
  'closed' => Icons.lock_outline,
  _ => Icons.edit_note,
};

String _surveyStateLabel(BuildContext context, String state) => switch (state) {
  'open' => _tdpText(context, 'Öppen', 'Open'),
  'closed' => _tdpText(context, 'Stängd', 'Closed'),
  _ => _tdpText(context, 'Utkast', 'Draft'),
};

/// A short random id for a new question.
String _surveyQuestionId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(10, (_) => chars[random.nextInt(chars.length)]).join();
}

/// Nine questions before individual player talks, to change as one likes.
_SurveyDraft _playerTalkTemplate(BuildContext context) {
  SurveyQuestion scale(String label, String low, String high) => SurveyQuestion(
    id: _surveyQuestionId(),
    kind: SurveyQuestionKind.scale,
    label: label,
    required: true,
    low: low,
    high: high,
  );
  SurveyQuestion text(String label) => SurveyQuestion(
    id: _surveyQuestionId(),
    kind: SurveyQuestionKind.longText,
    label: label,
  );
  return _SurveyDraft(
    title: 'Inför spelarsamtal',
    intro:
        'Hej! Inför vårt samtal vill vi gärna veta hur du har det i laget. Svara så ärligt du kan, det finns inga rätta eller fel svar. Det tar ungefär fem minuter.',
    questions: [
      scale('Hur trivs du i laget just nu?', 'Inte alls', 'Jättebra'),
      scale(
        'Hur tycker du att träningarna fungerar för dig?',
        'Dåligt',
        'Mycket bra',
      ),
      scale(
        'Hur nöjd är du med din speltid och din roll i matcherna?',
        'Inte nöjd',
        'Mycket nöjd',
      ),
      scale(
        'Hur är stämningen och kamratskapet i gruppen?',
        'Dålig',
        'Mycket bra',
      ),
      text('Vad tycker du att du är bäst på som spelare?'),
      text('Vad vill du bli bättre på den här säsongen?'),
      SurveyQuestion(
        id: _surveyQuestionId(),
        kind: SurveyQuestionKind.multi,
        label: 'Var på planen trivs du bäst?',
        options: const ['Målvakt', 'Försvar', 'Mittfält', 'Anfall', 'Vet inte'],
      ),
      text('Vad kan vi ledare göra bättre för dig och laget?'),
      text('Är det något mer du vill ta upp när vi ses?'),
    ],
  );
}

class _SurveyMessage extends StatelessWidget {
  const _SurveyMessage({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(_tdpText(context, 'Försök igen', 'Try again')),
            ),
          ],
        ],
      ),
    ),
  );
}

/// One survey: its state, the links (Dela) and the answers (Svar).
class _SurveyPage extends StatefulWidget {
  const _SurveyPage({this.initial, required this.surveyId});
  final TeamSurvey? initial;
  final String surveyId;

  static Future<void> open(
    BuildContext context,
    TeamSurvey? survey, {
    String? surveyId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _SurveyPage(initial: survey, surveyId: surveyId ?? survey!.id),
    ),
  );

  @override
  State<_SurveyPage> createState() => _SurveyPageState();
}

class _SurveyPageState extends State<_SurveyPage> {
  TeamSurveyServices get _services => TeamSurveysFeature.services;
  late TeamSurvey? _survey = widget.initial;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_survey == null) unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final survey = await _services.get(widget.surveyId);
      if (mounted) {
        setState(() {
          _survey = survey;
          _error = null;
        });
      }
    } catch (error) {
      AppErrors.caught('team_surveys.get', error);
      if (mounted) setState(() => _error = error);
    }
  }

  /// Runs a change and shows the survey it returns; a refusal is told.
  Future<bool> _change(
    Future<TeamSurvey> Function() run, {
    String? done,
    String Function(TeamSurvey saved)? doneFor,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    setState(() => _busy = true);
    try {
      final survey = await run();
      if (mounted) setState(() => _survey = survey);
      final told = doneFor?.call(survey) ?? done;
      if (told != null) messenger.showSnackBar(SnackBar(content: Text(told)));
      return true;
    } on TeamSurveyException catch (refused) {
      messenger.showSnackBar(SnackBar(content: Text(refused.message(swedish))));
      return false;
    } catch (error) {
      AppErrors.caught('team_surveys.change', error);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            swedish ? 'Det gick inte att spara.' : 'It could not be saved.',
          ),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(TeamSurvey survey) async {
    final saved = await _SurveyEditor.open(
      context,
      teamId: survey.teamId,
      survey: survey,
    );
    if (saved != null && mounted) setState(() => _survey = saved);
  }

  Future<void> _delete(TeamSurvey survey) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tdpText(context, 'Ta bort enkäten?', 'Delete survey?')),
        content: Text(
          _tdpText(
            context,
            'Enkäten, länkarna och alla ${survey.responses.length} svar tas bort för gott.',
            'The survey, its links and all ${survey.responses.length} answers are deleted for good.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tdpText(context, 'Avbryt', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tdpText(context, 'Ta bort', 'Delete')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failed = _tdpText(
      context,
      'Enkäten kunde inte tas bort.',
      'The survey could not be deleted.',
    );
    try {
      await _services.delete(survey.id);
      navigator.pop();
    } catch (error) {
      AppErrors.caught('team_surveys.delete', error);
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final survey = _survey;
    if (survey == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : _SurveyMessage(
                text: _tdpText(
                  context,
                  'Enkäten kunde inte läsas.',
                  'The survey could not be read.',
                ),
                onRetry: _reload,
              ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(survey.title),
          actions: [
            if (survey.canEdit)
              PopupMenuButton<String>(
                key: const Key('survey-menu'),
                onSelected: (value) =>
                    value == 'edit' ? _edit(survey) : _delete(survey),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(
                      _tdpText(context, 'Ändra frågorna', 'Edit questions'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      _tdpText(context, 'Ta bort enkäten', 'Delete survey'),
                    ),
                  ),
                ],
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: _tdpText(context, 'Dela', 'Share')),
              Tab(
                text: _tdpText(
                  context,
                  'Svar (${survey.responses.length})',
                  'Answers (${survey.responses.length})',
                ),
              ),
              Tab(text: _tdpText(context, 'Statistik', 'Statistics')),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: TabBarView(
                children: [
                  _SurveySharing(
                    survey: survey,
                    busy: _busy,
                    onChange: _change,
                    onEdit: () => _edit(survey),
                    onRefresh: _reload,
                  ),
                  _SurveyResults(
                    survey: survey,
                    onChange: _change,
                    onRefresh: _reload,
                  ),
                  _SurveyStatistics(survey: survey, onRefresh: _reload),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
