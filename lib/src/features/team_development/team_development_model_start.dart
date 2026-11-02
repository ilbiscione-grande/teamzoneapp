part of '../../app/teamzone_app.dart';

/// The principle of [plan] that [idea] already is, by phase and title.
TeamPrinciple? _tdpPrincipleOf(SeasonPlan plan, _TdpIdea idea) => plan
    .principles
    .where(
      (principle) =>
          principle.area == idea.area &&
          principle.title.trim().toLowerCase() == idea.title.toLowerCase(),
    )
    .firstOrNull;

/// [plan] with [ideas] added as principles, skipping those it has.
Future<SeasonPlan> _tdpAddIdeas(
  TeamDevelopmentServices services,
  SeasonPlan plan,
  Iterable<_TdpIdea> ideas,
) async {
  var saved = plan;
  for (final idea in ideas) {
    if (_tdpPrincipleOf(saved, idea) != null) continue;
    saved = await services.savePrinciple(
      saved,
      area: idea.area,
      title: idea.title,
      description: idea.description,
    );
  }
  return saved;
}

/// The two quick ways to a game model, shown while the team has no
/// principles.
class _TdpModelStart extends StatelessWidget {
  const _TdpModelStart({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('tdp-model-start'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tdpText(
                context,
                'Kom igång med spelidén',
                'Get started with the game model',
              ),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _tdpText(
                context,
                'Utgå från en färdig mall eller svara på några frågor om hur '
                    'ni vill spela. Principerna läggs in här och du kan ändra '
                    'dem som du vill. Spelidén är valfri. Utan den väljer '
                    'blocken bland en grundlista med en princip i varje skede.',
                'Start from a ready template or answer a few questions about '
                    'how you want to play. The principles are added here and '
                    'you can change them as you like. The game model is '
                    'optional. Without it, blocks pick from a base list with '
                    'one principle in each phase.',
              ),
              style: theme.textTheme.bodyMedium,
            ),
            if (controller.canEdit) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('tdp-model-templates'),
                    onPressed: () =>
                        _TdpModelTools.templates(context, controller),
                    icon: const Icon(Icons.view_module_outlined),
                    label: Text(
                      _tdpText(context, 'Utgå från en mall', 'Use a template'),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('tdp-model-guide'),
                    onPressed: () => _TdpModelTools.guide(context, controller),
                    icon: const Icon(Icons.quiz_outlined),
                    label: Text(
                      _tdpText(context, 'Svara på frågor', 'Answer questions'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The menu beside "Ny princip" that reaches the templates and the guide
/// once the team has principles.
class _TdpModelMenu extends StatelessWidget {
  const _TdpModelMenu({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
    key: const Key('tdp-model-menu'),
    tooltip: _tdpText(context, 'Mallar och guide', 'Templates and guide'),
    icon: const Icon(Icons.auto_awesome_outlined),
    onSelected: (template) => template
        ? _TdpModelTools.templates(context, controller)
        : _TdpModelTools.guide(context, controller),
    itemBuilder: (context) => [
      PopupMenuItem(
        key: const Key('tdp-model-menu-templates'),
        value: true,
        child: Text(
          _tdpText(context, 'Lägg till från en mall', 'Add from a template'),
        ),
      ),
      PopupMenuItem(
        key: const Key('tdp-model-menu-guide'),
        value: false,
        child: Text(_tdpText(context, 'Svara på frågor', 'Answer questions')),
      ),
    ],
  );
}

/// The templates, the guide and the list where the leader picks which of
/// their principles to add.
abstract final class _TdpModelTools {
  static Future<void> templates(
    BuildContext context,
    _TdpController controller,
  ) async {
    final template = await showDialog<_TdpTemplate>(
      context: context,
      builder: (context) {
        final sv = AppStrings.of(context).isSwedish;
        return AlertDialog(
          title: Text(_tdpText(context, 'Välj en mall', 'Pick a template')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final template in _tdpTemplates)
                    Card(
                      child: ListTile(
                        key: ValueKey('tdp-template-${template.key}'),
                        title: Text(sv ? template.name : template.nameEn),
                        subtitle: Text(
                          sv ? template.summary : template.summaryEn,
                        ),
                        trailing: Text(
                          sv
                              ? '${template.ideas.length} principer'
                              : '${template.ideas.length} principles',
                        ),
                        onTap: () => Navigator.pop(context, template),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
          ],
        );
      },
    );
    if (template == null || !context.mounted) return;
    final sv = AppStrings.of(context).isSwedish;
    await _pick(
      context,
      controller,
      template.ideas,
      sv ? template.name : template.nameEn,
    );
  }

  static Future<void> guide(
    BuildContext context,
    _TdpController controller,
  ) async {
    final answers = <String, int>{};
    final ideas = await showDialog<List<_TdpIdea>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          final sv = AppStrings.of(context).isSwedish;
          return AlertDialog(
            title: Text(
              _tdpText(
                context,
                'Hur vill ni spela?',
                'How do you want to play?',
              ),
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tdpText(
                        context,
                        'Svara på de frågor som passar. Du ser förslagen och '
                            'väljer vilka som läggs in.',
                        'Answer the questions that fit. You see the '
                            'suggestions and pick which are added.',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    for (final question in _tdpQuestions) ...[
                      const SizedBox(height: 16),
                      Text(
                        sv ? question.question : question.questionEn,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (i, answer) in question.answers.indexed)
                            ChoiceChip(
                              key: ValueKey('tdp-guide-${question.key}-$i'),
                              label: Text(sv ? answer.$1 : answer.$2),
                              selected: answers[question.key] == i,
                              onSelected: (on) => setState(
                                () => on
                                    ? answers[question.key] = i
                                    : answers.remove(question.key),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.of(context).feature('Avbryt')),
              ),
              FilledButton(
                key: const Key('tdp-guide-next'),
                onPressed: answers.isEmpty
                    ? null
                    : () => Navigator.pop(context, [
                        for (final question in _tdpQuestions)
                          if (answers[question.key] case final i?)
                            ...question.answers[i].$3,
                      ]),
                child: Text(
                  _tdpText(context, 'Visa förslag', 'Show suggestions'),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (ideas == null || !context.mounted) return;
    await _pick(
      context,
      controller,
      ideas,
      _tdpText(context, 'Förslag från guiden', 'Suggestions from the guide'),
    );
  }

  /// [ideas] by phase, each picked to start with unless the plan has it.
  static Future<void> _pick(
    BuildContext context,
    _TdpController controller,
    List<_TdpIdea> ideas,
    String title,
  ) async {
    final plan = controller.plan;
    if (plan == null) return;
    final shown = [
      for (final area in PrincipleArea.values)
        for (final idea in ideas)
          if (idea.area == area) idea,
    ];
    final picked = {
      for (final idea in shown)
        if (_tdpPrincipleOf(plan, idea) == null) idea,
    };
    final chosen = await showDialog<List<_TdpIdea>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          final room = 40 - plan.principles.length;
          final tooMany = picked.length > room;
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tdpText(
                        context,
                        'Välj vilka principer som läggs in i spelidén. Du kan '
                            'ändra texten efteråt.',
                        'Pick which principles are added to the game model. '
                            'You can change the text afterwards.',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    for (final (i, idea) in shown.indexed) ...[
                      if (i == 0 || shown[i - 1].area != idea.area)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '${AppStrings.of(context).feature(idea.area.label)}'
                            ' · ${AppStrings.of(context).feature(idea.area.withBall ? 'Med boll' : 'Utan boll')}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      if (_tdpPrincipleOf(plan, idea) != null)
                        ListTile(
                          key: ValueKey('tdp-idea-$i'),
                          dense: true,
                          enabled: false,
                          leading: const Icon(Icons.check),
                          title: Text(idea.title),
                          subtitle: Text(
                            _tdpText(
                              context,
                              'Finns redan i spelidén',
                              'Already in the game model',
                            ),
                          ),
                        )
                      else
                        CheckboxListTile(
                          key: ValueKey('tdp-idea-$i'),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: picked.contains(idea),
                          title: Text(idea.title),
                          subtitle: Text(idea.description),
                          onChanged: (on) => setState(
                            () => on == true
                                ? picked.add(idea)
                                : picked.remove(idea),
                          ),
                        ),
                    ],
                    if (tooMany)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _tdpText(
                            context,
                            'Spelidén rymmer 40 principer. Det finns plats för '
                                '$room till.',
                            'The game model holds 40 principles. There is room '
                                'for $room more.',
                          ),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.of(context).feature('Avbryt')),
              ),
              FilledButton(
                key: const Key('tdp-model-add'),
                onPressed: picked.isEmpty || tooMany
                    ? null
                    : () => Navigator.pop(context, [
                        for (final idea in shown)
                          if (picked.contains(idea)) idea,
                      ]),
                child: Text(
                  _tdpText(
                    context,
                    picked.length == 1
                        ? 'Lägg till 1 princip'
                        : 'Lägg till ${picked.length} principer',
                    picked.length == 1
                        ? 'Add 1 principle'
                        : 'Add ${picked.length} principles',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (chosen == null || !context.mounted) return;
    final current = controller.plan;
    if (current == null) return;
    await controller.change(
      context,
      () => _tdpAddIdeas(controller.services, current, chosen),
      done: _tdpText(
        context,
        'Principerna är tillagda. Du kan ändra dem när du vill.',
        'The principles are added. You can change them whenever you like.',
      ),
    );
  }
}
