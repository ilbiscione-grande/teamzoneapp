part of '../../app/teamzone_app.dart';

/// A survey being written: from the template, empty, or a saved survey.
class _SurveyDraft {
  const _SurveyDraft({
    required this.title,
    required this.intro,
    required this.questions,
  });
  final String title, intro;
  final List<SurveyQuestion> questions;
}

/// The survey's title, intro and questions on a full-screen page. Saving
/// returns the saved survey. Once someone has answered, only the title and
/// the intro can change.
class _SurveyEditor extends StatefulWidget {
  const _SurveyEditor({required this.teamId, this.survey, this.template});
  final String teamId;
  final TeamSurvey? survey;
  final _SurveyDraft? template;

  static Future<TeamSurvey?> open(
    BuildContext context, {
    required String teamId,
    TeamSurvey? survey,
    _SurveyDraft? template,
  }) => Navigator.of(context).push(
    MaterialPageRoute<TeamSurvey>(
      fullscreenDialog: true,
      builder: (_) =>
          _SurveyEditor(teamId: teamId, survey: survey, template: template),
    ),
  );

  @override
  State<_SurveyEditor> createState() => _SurveyEditorState();
}

/// One question's fields while it is written.
class _QuestionFields {
  _QuestionFields(SurveyQuestion question)
    : id = question.id,
      kind = question.kind,
      required = question.required,
      label = TextEditingController(text: question.label),
      options = TextEditingController(text: question.options.join('\n')),
      low = TextEditingController(text: question.low),
      high = TextEditingController(text: question.high);
  final String id;
  SurveyQuestionKind kind;
  bool required;
  final TextEditingController label, options, low, high;

  SurveyQuestion get question => SurveyQuestion(
    id: id,
    kind: kind,
    label: label.text.trim(),
    required: required,
    options: kind.hasOptions
        ? [
            for (final line in options.text.split('\n'))
              if (line.trim().isNotEmpty) line.trim(),
          ]
        : const [],
    low: kind == SurveyQuestionKind.scale ? low.text.trim() : '',
    high: kind == SurveyQuestionKind.scale ? high.text.trim() : '',
  );

  void dispose() {
    label.dispose();
    options.dispose();
    low.dispose();
    high.dispose();
  }
}

class _SurveyEditorState extends State<_SurveyEditor> {
  late final _SurveyDraft _start =
      widget.template ??
      (widget.survey == null
          ? const _SurveyDraft(title: '', intro: '', questions: [])
          : _SurveyDraft(
              title: widget.survey!.title,
              intro: widget.survey!.intro,
              questions: widget.survey!.questions,
            ));
  late final _title = TextEditingController(text: _start.title);
  late final _intro = TextEditingController(text: _start.intro);
  late final List<_QuestionFields> _questions = [
    for (final question in _start.questions) _QuestionFields(question),
  ];
  bool _saving = false;
  String? _problem;

  bool get _locked => widget.survey?.hasAnswers == true;

  @override
  void dispose() {
    _title.dispose();
    _intro.dispose();
    for (final question in _questions) {
      question.dispose();
    }
    super.dispose();
  }

  void _add() => setState(
    () => _questions.add(
      _QuestionFields(
        SurveyQuestion(
          id: _surveyQuestionId(),
          kind: SurveyQuestionKind.longText,
          label: '',
        ),
      ),
    ),
  );

  void _move(int index, int by) => setState(() {
    final question = _questions.removeAt(index);
    _questions.insert(index + by, question);
  });

  /// What keeps the survey from being saved, in words.
  String? _check(List<SurveyQuestion> questions) {
    if (_title.text.trim().isEmpty) {
      return _tdpText(context, 'Skriv en rubrik.', 'Write a title.');
    }
    for (final (index, question) in questions.indexed) {
      if (question.label.isEmpty) {
        return _tdpText(
          context,
          'Fråga ${index + 1} saknar text.',
          'Question ${index + 1} has no text.',
        );
      }
      final distinct = question.options.map((o) => o.toLowerCase()).toSet();
      if (question.kind.hasOptions &&
          (question.options.length < 2 ||
              question.options.length > 12 ||
              distinct.length != question.options.length)) {
        return _tdpText(
          context,
          'Fråga ${index + 1} behöver 2–12 olika alternativ, ett per rad.',
          'Question ${index + 1} needs 2–12 different options, one per line.',
        );
      }
    }
    return null;
  }

  Future<void> _save() async {
    final questions = [for (final fields in _questions) fields.question];
    final problem = _check(questions);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    final navigator = Navigator.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final saved = await TeamSurveysFeature.services.save(
        teamId: widget.teamId,
        surveyId: widget.survey?.id,
        title: _title.text.trim(),
        intro: _intro.text.trim(),
        questions: _locked ? widget.survey!.questions : questions,
      );
      navigator.pop(saved);
    } on TeamSurveyException catch (refused) {
      if (mounted) setState(() => _problem = refused.message(swedish));
    } catch (error) {
      AppErrors.caught('team_surveys.save', error);
      if (mounted) {
        setState(
          () => _problem = swedish
              ? 'Enkäten kunde inte sparas. Försök igen.'
              : 'The survey could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.survey == null
              ? _tdpText(context, 'Ny enkät', 'New survey')
              : _tdpText(context, 'Ändra enkäten', 'Edit survey'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const Key('survey-save'),
              onPressed: _saving ? null : _save,
              child: Text(_tdpText(context, 'Spara', 'Save')),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              if (_saving) const LinearProgressIndicator(),
              TextField(
                key: const Key('survey-title'),
                controller: _title,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: _tdpText(context, 'Rubrik', 'Title'),
                ),
              ),
              TextField(
                controller: _intro,
                maxLength: 2000,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: _tdpText(
                    context,
                    'Inledning till spelarna',
                    'Intro for the players',
                  ),
                ),
              ),
              if (_locked)
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _tdpText(
                        context,
                        'Enkäten har svar, så frågorna kan inte ändras längre. Rubriken och inledningen går att ändra.',
                        'The survey has answers, so the questions cannot change. The title and intro can.',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              for (final (index, fields) in _questions.indexed)
                _QuestionCard(
                  key: ObjectKey(fields),
                  number: index + 1,
                  fields: fields,
                  locked: _locked,
                  onChanged: () => setState(() {}),
                  onUp: index > 0 ? () => _move(index, -1) : null,
                  onDown: index < _questions.length - 1
                      ? () => _move(index, 1)
                      : null,
                  onDelete: () => setState(() {
                    _questions.removeAt(index).dispose();
                  }),
                ),
              if (!_locked && _questions.length < 30)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('survey-add-question'),
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: Text(
                      _tdpText(context, 'Lägg till fråga', 'Add question'),
                    ),
                  ),
                ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _problem!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.number,
    required this.fields,
    required this.locked,
    required this.onChanged,
    required this.onDelete,
    this.onUp,
    this.onDown,
  });
  final int number;
  final _QuestionFields fields;
  final bool locked;
  final VoidCallback onChanged, onDelete;
  final VoidCallback? onUp, onDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  _tdpText(context, 'Fråga $number', 'Question $number'),
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                if (!locked) ...[
                  IconButton(
                    tooltip: _tdpText(context, 'Flytta upp', 'Move up'),
                    onPressed: onUp,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: _tdpText(context, 'Flytta ned', 'Move down'),
                    onPressed: onDown,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: _tdpText(context, 'Ta bort frågan', 'Delete'),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            TextField(
              controller: fields.label,
              enabled: !locked,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _tdpText(context, 'Frågan', 'Question'),
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<SurveyQuestionKind>(
                  value: fields.kind,
                  onChanged: locked
                      ? null
                      : (kind) {
                          if (kind == null) return;
                          fields.kind = kind;
                          onChanged();
                        },
                  items: [
                    for (final kind in SurveyQuestionKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(swedish ? kind.sv : kind.en),
                      ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: fields.required,
                      onChanged: locked
                          ? null
                          : (on) {
                              fields.required = on;
                              onChanged();
                            },
                    ),
                    Text(_tdpText(context, 'Måste besvaras', 'Required')),
                  ],
                ),
              ],
            ),
            if (fields.kind.hasOptions)
              TextField(
                controller: fields.options,
                enabled: !locked,
                minLines: 2,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: _tdpText(
                    context,
                    'Alternativ, ett per rad',
                    'Options, one per line',
                  ),
                ),
              ),
            if (fields.kind == SurveyQuestionKind.scale)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: fields.low,
                      enabled: !locked,
                      maxLength: 40,
                      decoration: InputDecoration(
                        labelText: _tdpText(context, '1 betyder', '1 means'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: fields.high,
                      enabled: !locked,
                      maxLength: 40,
                      decoration: InputDecoration(
                        labelText: _tdpText(context, '5 betyder', '5 means'),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
