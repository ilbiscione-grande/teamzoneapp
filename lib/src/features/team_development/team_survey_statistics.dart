part of '../../app/teamzone_app.dart';

/// Enkät → Statistik: what the answers say together. Key figures, the
/// scale questions side by side (strongest and weakest), and per question
/// the spread, the choices and the written answers. One player can be
/// picked to see their answers against the team's, before a player talk.
class _SurveyStatistics extends StatefulWidget {
  const _SurveyStatistics({required this.survey, required this.onRefresh});
  final TeamSurvey survey;
  final Future<void> Function() onRefresh;

  @override
  State<_SurveyStatistics> createState() => _SurveyStatisticsState();
}

class _SurveyStatisticsState extends State<_SurveyStatistics> {
  String? _compareId;

  @override
  Widget build(BuildContext context) {
    final survey = widget.survey;
    final theme = Theme.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (survey.responses.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _tdpText(
                context,
                'Statistiken visas när de första svaren har kommit.',
                'The statistics show once the first answers are in.',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final responses = [...survey.responses]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final compare = responses.where((r) => r.id == _compareId).firstOrNull;
    final rate = survey.responseRate;
    final scaleAverage = survey.scaleAverage;
    final scales = [
      for (final question in survey.questions)
        if (question.kind == SurveyQuestionKind.scale)
          if (survey.average(question) case final double average)
            (question, average),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SurveyFigure(
                value: '${survey.responses.length}',
                label: _tdpText(context, 'svar', 'answers'),
              ),
              if (rate != null)
                _SurveyFigure(
                  value: '${(rate * 100).round()} %',
                  label: _tdpText(
                    context,
                    'av de personliga länkarna',
                    'of the personal links',
                  ),
                ),
              if (scaleAverage != null)
                _SurveyFigure(
                  value: _surveyNumber(scaleAverage, swedish),
                  label: _tdpText(
                    context,
                    'snitt på skalfrågorna',
                    'average on the scales',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            key: const Key('survey-compare'),
            initialValue: _compareId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _tdpText(
                context,
                'Jämför en spelare med laget',
                'Compare a player with the team',
              ),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(_tdpText(context, 'Ingen', 'None')),
              ),
              for (final response in responses)
                DropdownMenuItem<String?>(
                  value: response.id,
                  child: Text(response.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) => setState(() => _compareId = id),
          ),
          if (scales.length > 1) ...[
            const SizedBox(height: 24),
            Text(
              _tdpText(context, 'Skalfrågorna', 'The scale questions'),
              style: theme.textTheme.titleMedium,
            ),
            Text(
              _tdpText(
                context,
                'Lagets snitt, högst först.',
                'The team\'s average, highest first.',
              ),
              style: muted,
            ),
            const SizedBox(height: 8),
            for (final (index, (question, average)) in scales.indexed)
              _SurveyAverageRow(
                label: question.label,
                average: average,
                mark: switch (compare?.answers[question.id]) {
                  final num value => value.toDouble(),
                  _ => null,
                },
                tag: index == 0
                    ? _tdpText(context, 'Högst', 'Highest')
                    : index == scales.length - 1
                    ? _tdpText(context, 'Lägst', 'Lowest')
                    : null,
              ),
            if (compare != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _tdpText(
                    context,
                    'Strecket visar ${compare.name}s svar.',
                    'The line shows ${compare.name}\'s answer.',
                  ),
                  style: muted,
                ),
              ),
          ],
          const Divider(height: 40),
          Text(
            _tdpText(context, 'Per fråga', 'By question'),
            style: theme.textTheme.titleMedium,
          ),
          for (final (index, question) in survey.questions.indexed)
            _SurveyQuestionSummary(
              number: index + 1,
              survey: survey,
              question: question,
              compare: compare,
            ),
        ],
      ),
    );
  }
}

String _surveyNumber(double value, bool swedish) {
  final text = value.toStringAsFixed(1);
  return swedish ? text.replaceAll('.', ',') : text;
}

class _SurveyFigure extends StatelessWidget {
  const _SurveyFigure({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: theme.textTheme.headlineSmall),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A scale question's average on a 1–5 bar, with a player's answer as a
/// line when one is compared.
class _SurveyAverageRow extends StatelessWidget {
  const _SurveyAverageRow({
    required this.label,
    required this.average,
    this.mark,
    this.tag,
  });
  final String label;
  final double average;
  final double? mark;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              if (tag != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    tag!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                _surveyNumber(average, swedish),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          _SurveyScaleBar(value: average, mark: mark),
        ],
      ),
    );
  }
}

/// A bar from 1 to 5 filled to [value], with [mark] as a line.
class _SurveyScaleBar extends StatelessWidget {
  const _SurveyScaleBar({required this.value, this.mark});
  final double value;
  final double? mark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double share(double v) => ((v - 1) / 4).clamp(0, 1).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 14,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: width * share(value),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (mark != null)
                Positioned(
                  left: (width * share(mark!) - 2).clamp(0, width - 4),
                  top: -2,
                  bottom: -2,
                  width: 4,
                  child: ColoredBox(color: theme.colorScheme.tertiary),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SurveyQuestionSummary extends StatelessWidget {
  const _SurveyQuestionSummary({
    required this.number,
    required this.survey,
    required this.question,
    this.compare,
  });
  final int number;
  final TeamSurvey survey;
  final SurveyQuestion question;
  final SurveyResponse? compare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    final answered = survey.answersTo(question)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final mine = compare?.answers[question.id];
    final body = <Widget>[];
    switch (question.kind) {
      case SurveyQuestionKind.scale:
        final values = survey.scaleValues(question);
        final average = survey.average(question);
        if (average != null) {
          body.add(
            Text(
              [
                _tdpText(
                  context,
                  'Snitt ${_surveyNumber(average, swedish)} av 5',
                  'Average ${_surveyNumber(average, swedish)} of 5',
                ),
                if (mine is num)
                  _tdpText(
                    context,
                    '${compare!.name}: $mine',
                    '${compare!.name}: $mine',
                  ),
              ].join(' · '),
              style: theme.textTheme.titleSmall,
            ),
          );
          for (var step = 5; step >= 1; step--) {
            body.add(
              _SurveyBar(
                label: '$step',
                count: values.where((v) => v == step).length,
                total: values.length,
                chosen: mine is num && mine.toInt() == step,
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
        final counts = survey.optionCounts(question).entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final MapEntry(key: option, value: count) in counts) {
          body.add(
            _SurveyBar(
              label: option,
              count: count,
              total: answered.length,
              chosen: mine == option || (mine is List && mine.contains(option)),
            ),
          );
        }
        if (question.kind == SurveyQuestionKind.multi) {
          body.add(
            Text(
              _tdpText(
                context,
                'Man kunde välja flera.',
                'Several could be chosen.',
              ),
              style: muted,
            ),
          );
        }
      case SurveyQuestionKind.text || SurveyQuestionKind.longText:
        for (final response in answered) {
          final chosen = response.id == compare?.id;
          body.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${response.name}: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: chosen ? theme.colorScheme.tertiary : null,
                      ),
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
              '${answered.length} av ${survey.responses.length} har svarat',
              '${answered.length} of ${survey.responses.length} answered',
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

/// How many gave an answer, as a bar with the count and the share.
class _SurveyBar extends StatelessWidget {
  const _SurveyBar({
    required this.label,
    required this.count,
    required this.total,
    this.chosen = false,
  });
  final String label;
  final int count, total;

  /// The compared player's answer.
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              chosen ? '$label ◂' : label,
              overflow: TextOverflow.ellipsis,
              style: chosen
                  ? TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.tertiary,
                    )
                  : null,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 10,
                color: chosen ? theme.colorScheme.tertiary : null,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              '$count · ${(share * 100).round()} %',
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
