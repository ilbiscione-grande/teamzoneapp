part of '../../app/teamzone_app.dart';

/// One exercise on a phone, over the session page: the drill, its players,
/// the coaching notes and its settings as tabs. Edits go to the session's
/// draft, which is saved from the session.
class _TrainingExerciseMobile extends StatelessWidget {
  const _TrainingExerciseMobile({
    required this.block,
    required this.editorKey,
    required this.tab,
    required this.roster,
    required this.settings,
    required this.onTab,
    required this.onClose,
    required this.onChanged,
    required this.onEdit,
    required this.onCopy,
    required this.onRemove,
    required this.onManageRoster,
    required this.onAddUnnamed,
    this.onLinkBoard,
  });
  final TrainingBlock block;
  final String editorKey;
  final int tab;
  final List<TrainingBlockPlayer> roster;

  /// The exercise's properties, as the desktop's properties panel.
  final Widget settings;
  final ValueChanged<int> onTab;
  final VoidCallback onClose, onEdit, onCopy, onRemove, onManageRoster;
  final VoidCallback? onAddUnnamed;

  /// Links a board from the library; null without the library.
  final VoidCallback? onLinkBoard;
  final ValueChanged<TrainingBlock> onChanged;

  Widget _menu(BuildContext context, {Widget? icon, ButtonStyle? style}) {
    final strings = AppStrings.of(context);
    return PopupMenuButton<int>(
      key: const Key('training-exercise-menu'),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      icon: icon ?? const Icon(Icons.more_vert),
      style: style,
      onSelected: (value) => switch (value) {
        0 => onEdit(),
        1 => onCopy(),
        _ => onRemove(),
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 0, child: Text(strings.feature('Byt övning'))),
        PopupMenuItem(value: 1, child: Text(strings.feature('Kopiera övning'))),
        PopupMenuItem(value: 2, child: Text(strings.feature('Ta bort övning'))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const Key('training-exercise-mobile'),
      children: [
        Material(
          color: colors.surfaceContainerLowest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                IconButton(
                  key: const Key('training-exercise-close'),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: onClose,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                ),
                Expanded(
                  child: Text(
                    block.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _menu(context),
              ],
            ),
          ),
        ),
        _TrainingProgramTabs(
          view: tab,
          onChanged: onTab,
          expand: true,
          labels: const ['Övning', 'Spelare', 'Coachning', 'Inställningar'],
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: switch (tab) {
                0 => _drill(context),
                1 => Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ProgramPanel(
                    child: _TrainingPlayerPanel(
                      key: ValueKey('training-player-panel-$editorKey'),
                      grouped: true,
                      roster: roster,
                      players: block.players,
                      onManageRoster: onManageRoster,
                      onAddUnnamed: onAddUnnamed,
                      onChanged: (players) =>
                          onChanged(block.copyWith(players: players)),
                    ),
                  ),
                ),
                2 => _coaching(context),
                _ => Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ProgramPanel(
                    padding: EdgeInsets.zero,
                    child: settings,
                  ),
                ),
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _drill(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lines = block.organisation
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^(• |- |\d+\. )'), '').trim())
        .where((line) => line.isNotEmpty);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              AspectRatio(
                aspectRatio: 1.15,
                child: _ExerciseIllustration(
                  board: block.board,
                  onLink: onLinkBoard,
                  onUnlink: () => onChanged(block.copyWith(clearBoard: true)),
                ),
              ),
              const SizedBox(height: 12),
              _ProgramPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.feature('Beskrivning'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (lines.isEmpty)
                      Text(
                        strings.feature('Ingen beskrivning än.'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  '),
                            Expanded(child: Text(line)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Placeholder until exercises carry a purpose of their own.
              _ProgramPanel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.feature('Syfte'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            strings.feature(
                              'Övningens syfte kan beskrivas här i en kommande version.',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: strings.feature('Övningsläget kommer snart'),
                  child: FilledButton.icon(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(strings.feature('Starta övning')),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _menu(
                context,
                icon: const Icon(Icons.more_horiz),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  side: BorderSide(color: colors.outlineVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coaching(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ProgramPanel(
          child: Column(
            children: [
              _TrainingNotesField(
                key: ValueKey('notes-organisation-$editorKey'),
                fieldKey: ValueKey('workspace-organisation-$editorKey'),
                label: strings.feature('Organisation'),
                hint: strings.feature('Yta, antal spelare, regler'),
                initialValue: block.organisation,
                onChanged: (value) =>
                    onChanged(block.copyWith(organisation: value)),
              ),
              const SizedBox(height: 16),
              _TrainingNotesField(
                key: ValueKey('notes-coaching-$editorKey'),
                fieldKey: ValueKey('workspace-coaching-$editorKey'),
                label: strings.feature('Coachpunkter'),
                hint: strings.feature('Vad ledarna lyfter under övningen'),
                initialValue: block.coachingPoints,
                onChanged: (value) =>
                    onChanged(block.copyWith(coachingPoints: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Placeholder until leaders keep notes of their own on an exercise.
        _ProgramPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.feature('Egna noter (valfritt)'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                enabled: false,
                minLines: 3,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: strings.feature('Kommer snart'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
