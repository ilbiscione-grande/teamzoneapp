part of '../../app/teamzone_app.dart';

/// Enkät → Svar: each answer by person, and per question what the answers
/// say together (a scale's average and spread, how many chose each
/// option, the written answers with names).
class _SurveyResults extends StatelessWidget {
  const _SurveyResults({
    required this.survey,
    required this.onChange,
    required this.onRefresh,
  });
  final TeamSurvey survey;
  final _SurveyChange onChange;
  final Future<void> Function() onRefresh;

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
          const Divider(height: 32),
          Text(
            _tdpText(context, 'Per fråga', 'By question'),
            style: theme.textTheme.titleMedium,
          ),
          for (final (index, question) in survey.questions.indexed)
            _SurveyQuestionSummary(
              number: index + 1,
              question: question,
              responses: responses,
            ),
        ],
      ),
    );
  }
}

class _SurveyQuestionSummary extends StatelessWidget {
  const _SurveyQuestionSummary({
    required this.number,
    required this.question,
    required this.responses,
  });
  final int number;
  final SurveyQuestion question;
  final List<SurveyResponse> responses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = [
      for (final response in responses)
        if (response.answers[question.id] != null) response,
    ];
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final body = <Widget>[];
    switch (question.kind) {
      case SurveyQuestionKind.scale:
        final values = [
          for (final response in answered)
            (response.answers[question.id] as num).toInt(),
        ];
        if (values.isNotEmpty) {
          final average = values.reduce((a, b) => a + b) / values.length;
          body.add(
            Text(
              _tdpText(
                context,
                'Snitt ${average.toStringAsFixed(1).replaceAll('.', ',')} av 5',
                'Average ${average.toStringAsFixed(1)} of 5',
              ),
              style: theme.textTheme.titleSmall,
            ),
          );
          for (var step = 5; step >= 1; step--) {
            body.add(
              _SurveyBar(
                label: '$step',
                count: values.where((v) => v == step).length,
                total: values.length,
              ),
            );
          }
          if (question.low.isNotEmpty || question.high.isNotEmpty) {
            body.add(
              Text(
                [
                  if (question.low.isNotEmpty) '1 = ${question.low}',
                  if (question.high.isNotEmpty) '5 = ${question.high}',
                ].join(' · '),
                style: muted,
              ),
            );
          }
        }
      case SurveyQuestionKind.single || SurveyQuestionKind.multi:
        for (final option in question.options) {
          body.add(
            _SurveyBar(
              label: option,
              count: answered.where((response) {
                final answer = response.answers[question.id];
                return answer == option ||
                    (answer is List && answer.contains(option));
              }).length,
              total: answered.length,
            ),
          );
        }
      case SurveyQuestionKind.text || SurveyQuestionKind.longText:
        for (final response in answered) {
          body.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${response.name}: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: '${response.answers[question.id]}'),
                  ],
                ),
              ),
            ),
          );
        }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$number. ${question.label}', style: theme.textTheme.titleSmall),
          Text(
            _tdpText(
              context,
              '${answered.length} av ${responses.length} har svarat',
              '${answered.length} of ${responses.length} answered',
            ),
            style: muted,
          ),
          const SizedBox(height: 6),
          ...body,
        ],
      ),
    );
  }
}

class _SurveyBar extends StatelessWidget {
  const _SurveyBar({
    required this.label,
    required this.count,
    required this.total,
  });
  final String label;
  final int count, total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : count / total,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(width: 36, child: Text('$count', textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

/// One person's answers, question by question.
class _SurveyAnswerList extends StatelessWidget {
  const _SurveyAnswerList({required this.questions, required this.answers});
  final List<SurveyQuestion> questions;
  final Map<String, dynamic> answers;

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
                      : question.describe(
                          answers[question.id],
                          swedish: swedish,
                        ),
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
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tdpText(context, 'Ta bort svaret?', 'Delete answer?')),
        content: Text(
          _tdpText(
            context,
            '${response.name}s svar tas bort för gott.',
            '${response.name}\'s answer is deleted for good.',
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
    if (sure != true) return;
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
            ),
          ],
        ),
      ),
    ),
    actions: [
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
