part of '../../app/teamzone_app.dart';

/// Enkät → Svar: each answer by person, and all of them as a table to keep
/// in a spreadsheet. What they say together is under Statistik.
class _SurveyResults extends StatelessWidget {
  const _SurveyResults({
    required this.survey,
    required this.onChange,
    required this.onRefresh,
  });
  final TeamSurvey survey;
  final _SurveyChange onChange;
  final Future<void> Function() onRefresh;

  Future<void> _copyTable(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    await Clipboard.setData(ClipboardData(text: survey.toTable(swedish: swedish)));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          swedish
              ? 'Svaren är kopierade. Klistra in dem i ett kalkylark.'
              : 'The answers are copied. Paste them into a spreadsheet.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final responses = [...survey.responses]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (responses.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _tdpText(
                context,
                'Inga svar ännu. Dra nedåt för att läsa in nya svar.',
                'No answers yet. Pull down to check for new ones.',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            _tdpText(context, 'Per person', 'By person'),
            style: theme.textTheme.titleMedium,
          ),
          for (final response in responses)
            ListTile(
              key: Key('survey-response-${response.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                response.open && response.personId == null
                    ? Icons.link
                    : Icons.person_outline,
              ),
              title: Text(response.name),
              subtitle: Text(
                [
                  _surveyDate(response.updatedAt),
                  if (response.open && response.personId == null)
                    _tdpText(
                      context,
                      'öppen länk, inte kopplad',
                      'open link, not linked',
                    )
                  else if (response.open)
                    _tdpText(
                      context,
                      'öppen länk: ${response.respondentName}',
                      'open link: ${response.respondentName}',
                    ),
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _SurveyResponseDialog.open(
                context,
                survey: survey,
                response: response,
                onChange: onChange,
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('survey-copy-table'),
              onPressed: () => _copyTable(context),
              icon: const Icon(Icons.table_view_outlined),
              label: Text(
                _tdpText(
                  context,
                  'Kopiera svaren som tabell',
                  'Copy the answers as a table',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _tdpText(
                context,
                'Klistra in i Excel, Numbers eller Google Kalkylark. Statistiken per fråga finns under fliken Statistik.',
                'Paste into Excel, Numbers or Google Sheets. The statistics per question are under Statistics.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One person's answers, question by question.
class _SurveyAnswerList extends StatelessWidget {
  const _SurveyAnswerList({
    required this.questions,
    required this.answers,
    this.averages = const {},
  });
  final List<SurveyQuestion> questions;
  final Map<String, dynamic> answers;

  /// The team's average per scale question, shown beside the answer.
  final Map<String, double> averages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, question) in questions.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}. ${question.label}',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  answers[question.id] == null
                      ? (swedish ? 'Inget svar' : 'No answer')
                      : [
                          question.describe(
                            answers[question.id],
                            swedish: swedish,
                          ),
                          if (averages[question.id] case final double average)
                            swedish
                                ? 'laget i snitt ${_surveyNumber(average, true)}'
                                : 'team average ${_surveyNumber(average, false)}',
                        ].join(' · '),
                  style: answers[question.id] == null
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SurveyResponseDialog extends StatelessWidget {
  const _SurveyResponseDialog({
    required this.survey,
    required this.response,
    required this.onChange,
  });
  final TeamSurvey survey;
  final SurveyResponse response;
  final _SurveyChange onChange;

  static Future<void> open(
    BuildContext context, {
    required TeamSurvey survey,
    required SurveyResponse response,
    required _SurveyChange onChange,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _SurveyResponseDialog(
      survey: survey,
      response: response,
      onChange: onChange,
    ),
  );

  TeamSurveyServices get _services => TeamSurveysFeature.services;

  Future<void> _link(BuildContext context) async {
    final navigator = Navigator.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_tdpText(context, 'Koppla till spelare', 'Link to player')),
        children: [
          for (final player in survey.players)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, player.personId),
              child: Text(player.name),
            ),
          if (response.personId != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(_tdpText(context, 'Ingen spelare', 'No player')),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final saved = await onChange(
      () => _services.linkResponse(response.id, picked.isEmpty ? null : picked),
    );
    if (saved) navigator.pop();
  }

  Future<void> _delete(BuildContext context) async {
    final navigator = Navigator.of(context);
    final sure = await confirmSurveyAnswersDeletion(
      context,
      title: _tdpText(context, 'Ta bort svaret?', 'Delete answer?'),
      message: _tdpText(
        context,
        '${response.name}s svar tas bort.',
        '${response.name}\'s answer is deleted.',
      ),
    );
    if (!sure) return;
    if (await onChange(() => _services.deleteResponse(response.id))) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(response.name),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (response.open)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _tdpText(
                    context,
                    'Via den öppna länken, med namnet "${response.respondentName}".',
                    'Through the open link, as "${response.respondentName}".',
                  ),
                ),
              ),
            _SurveyAnswerList(
              questions: survey.questions,
              answers: response.answers,
              averages: survey.responses.length > 1
                  ? {
                      for (final question in survey.questions)
                        if (survey.average(question) case final double average)
                          question.id: average,
                    }
                  : const {},
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (response.personId case final personId?)
        TextButton.icon(
          key: const Key('survey-response-talk'),
          onPressed: () => PlayerTalkPage.open(
            context,
            teamId: survey.teamId,
            personId: personId,
            answerView: _surveyTalkAnswers,
            responseId: response.id,
          ),
          icon: const Icon(Icons.forum_outlined),
          label: Text(_tdpText(context, 'Spelarsamtal', 'Player talk')),
        ),
      if (survey.canEdit) ...[
        TextButton(
          onPressed: () => _delete(context),
          child: Text(_tdpText(context, 'Ta bort', 'Delete')),
        ),
        if (response.open)
          TextButton(
            onPressed: () => _link(context),
            child: Text(
              _tdpText(context, 'Koppla till spelare', 'Link to player'),
            ),
          ),
      ],
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_tdpText(context, 'Stäng', 'Close')),
      ),
    ],
  );
}
