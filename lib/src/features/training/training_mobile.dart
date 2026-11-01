part of '../../app/teamzone_app.dart';

/// The phone's top of a training: its name, when and where, the focus on
/// the overview, and the session's actions.
class _TrainingMobileHeader extends StatelessWidget {
  const _TrainingMobileHeader({
    required this.session,
    required this.event,
    required this.theme,
    required this.overview,
    required this.unsaved,
    required this.busy,
    required this.published,
    required this.onSave,
    required this.onGuide,
    required this.onAdd,
    required this.onPublished,
    required this.onFocus,
    this.onLibrary,
    this.onSavePass,
  });
  final TrainingSession session;
  final Future<(EventDetails, SquadDetails)> event;
  final TextEditingController theme;
  final bool overview, unsaved, busy, published;
  final VoidCallback? onSave, onGuide;
  final VoidCallback onAdd, onFocus;

  /// Taking a pass from the library, and saving the session as a pass;
  /// without them, not offered.
  final VoidCallback? onLibrary, onSavePass;
  final ValueChanged<bool> onPublished;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final muted = text.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    return Material(
      color: colors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (overview)
                        FutureBuilder<(EventDetails, SquadDetails)>(
                          future: event,
                          builder: (context, snapshot) {
                            final parts = _TrainingProgramHeader.detailParts(
                              context,
                              session,
                              snapshot.data?.$1,
                            );
                            return Column(
                              children: [
                                for (final line in [
                                  parts.first,
                                  parts.skip(1).join(' – '),
                                ])
                                  if (line.isNotEmpty)
                                    Text(
                                      line,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: muted,
                                    ),
                              ],
                            );
                          },
                        )
                      else
                        ListenableBuilder(
                          listenable: theme,
                          builder: (context, _) => Text(
                            [
                              '${session.eventMinutes} min',
                              if (theme.text.trim().isNotEmpty)
                                theme.text.trim(),
                            ].join('  •  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                    ],
                  ),
                ),
                FilledButton(
                  key: const Key('training-session-save'),
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(strings.feature(busy ? 'Sparar…' : 'Spara')),
                ),
                PopupMenuButton<int>(
                  key: const Key('training-session-menu'),
                  tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) => switch (value) {
                    0 => onGuide?.call(),
                    1 => onAdd(),
                    3 => onLibrary?.call(),
                    4 => onSavePass?.call(),
                    _ => onPublished(!published),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: const Key('training-guide-open'),
                      value: 0,
                      enabled: onGuide != null,
                      child: Text(strings.feature('Guidad planering')),
                    ),
                    PopupMenuItem(
                      value: 1,
                      child: Text(strings.feature('Lägg till övning')),
                    ),
                    if (onLibrary != null)
                      PopupMenuItem(
                        key: const Key('training-library-open'),
                        value: 3,
                        child: Text(strings.feature('Från biblioteket')),
                      ),
                    if (onSavePass != null)
                      PopupMenuItem(
                        key: const Key('training-pass-save'),
                        value: 4,
                        child: Text(strings.feature('Spara och dela som pass')),
                      ),
                    CheckedPopupMenuItem(
                      value: 2,
                      checked: published,
                      child: Text(strings.feature('Visa passet för spelarna')),
                    ),
                  ],
                ),
              ],
            ),
            if (overview)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Material(
                  color: colors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: const Key('training-session-focus'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: onFocus,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Row(
                        children: [
                          Icon(Icons.track_changes, color: colors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: theme,
                              builder: (context, _) => Text(
                                theme.text.trim().isEmpty
                                    ? strings.feature('Lägg till träningsfokus')
                                    : theme.text.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The phone's planning: each part as a coloured header over its exercises
/// on a time rail. An exercise opens on its own page.
class _TrainingPlanningMobile extends StatelessWidget {
  const _TrainingPlanningMobile({
    required this.blocks,
    required this.header,
    required this.onOpen,
    required this.onAdd,
    required this.onEdit,
    required this.onMove,
    required this.onCopy,
    required this.onRemove,
  });
  final List<TrainingBlock> blocks;
  final List<Widget> header;
  final ValueChanged<int> onOpen, onEdit, onCopy, onRemove;
  final ValueChanged<TrainingPart> onAdd;
  final void Function(int index, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final starts = <int>[];
    var minute = 0;
    for (final block in blocks) {
      starts.add(minute);
      minute += block.minutes;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          key: const Key('training-planning-mobile'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            ...header,
            for (final part in TrainingPart.values)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _section(context, part, starts),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, TrainingPart part, List<int> starts) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = _trainingPartColors(part);
    final indices = [
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].part == part) i,
    ];
    final minutes = indices.fold(0, (sum, i) => sum + blocks[i].minutes);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    Widget rail(Color dot) => SizedBox(
      width: 22,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 2, color: colors.outlineVariant),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ],
      ),
    );
    return _ProgramPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: palette.fill,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: palette.accent,
                  child: Icon(
                    _trainingPartIcon(part),
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: strings.feature(part.label),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: '  ($minutes min)'),
                      ],
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton.filled(
                  key: ValueKey('training-add-${part.name}'),
                  tooltip: strings.feature('Lägg till övning'),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.surfaceContainerLowest,
                    foregroundColor: colors.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => onAdd(part),
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
          ),
          if (indices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Text(strings.feature('Inga övningar än.'), style: muted),
            ),
          for (final (n, i) in indices.indexed) ...[
            if (n > 0) const Divider(height: 1, indent: 34),
            InkWell(
              key: ValueKey('training-block-$i'),
              onTap: () => onOpen(i),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    rail(palette.accent),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 62,
                      child: Text(
                        '${starts[i]}–${starts[i] + blocks[i].minutes}',
                        style: muted,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        blocks[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${blocks[i].minutes} min', style: muted),
                    PopupMenuButton<int>(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).showMenuTooltip,
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (value) => switch (value) {
                        0 => onEdit(i),
                        1 => onMove(i, -1),
                        2 => onMove(i, 1),
                        3 => onCopy(i),
                        _ => onRemove(i),
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 0,
                          child: Text(strings.feature('Redigera')),
                        ),
                        PopupMenuItem(
                          value: 1,
                          enabled: i > 0 && blocks[i - 1].part == part,
                          child: Text(strings.feature('Flytta upp')),
                        ),
                        PopupMenuItem(
                          value: 2,
                          enabled:
                              i < blocks.length - 1 &&
                              blocks[i + 1].part == part,
                          child: Text(strings.feature('Flytta ned')),
                        ),
                        PopupMenuItem(
                          value: 3,
                          child: Text(strings.feature('Kopiera övning')),
                        ),
                        PopupMenuItem(
                          value: 4,
                          child: Text(strings.feature('Ta bort övning')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
