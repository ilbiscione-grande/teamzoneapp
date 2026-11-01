part of '../../app/teamzone_app.dart';

/// A part's shared colours on the desktop programme: the timeline's blocks
/// and the structure's headers. Light fills keep dark text readable.
({Color fill, Color accent}) _trainingPartColors(TrainingPart part) =>
    switch (part) {
      TrainingPart.warmup => (
        fill: const Color(0xFFDCEBD2),
        accent: const Color(0xFF4F8A3C),
      ),
      TrainingPart.main => (
        fill: const Color(0xFFF7DCCF),
        accent: const Color(0xFFC4573A),
      ),
      TrainingPart.finish => (
        fill: const Color(0xFFEFE5D7),
        accent: const Color(0xFF9B7A55),
      ),
    };

IconData _trainingPartIcon(TrainingPart part) => switch (part) {
  TrainingPart.warmup => Icons.directions_run,
  TrainingPart.main => Icons.sports_soccer,
  TrainingPart.finish => Icons.self_improvement,
};

/// One white work area of the desktop programme.
class _ProgramPanel extends StatelessWidget {
  const _ProgramPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // A Material, so list tiles and ink inside paint on the panel.
    return Material(
      color: colors.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A small square outlined icon button, as the programme's toolbars use.
class _ProgramIconButton extends StatelessWidget {
  const _ProgramIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
    tooltip: tooltip,
    onPressed: onPressed,
    color: color,
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    icon: Icon(icon, size: 20),
  );
}

/// The programme's top row: the training, its focus, whether it is saved,
/// and the session's actions.
class _TrainingProgramHeader extends StatelessWidget {
  const _TrainingProgramHeader({
    required this.session,
    required this.event,
    required this.theme,
    required this.unsaved,
    required this.busy,
    required this.savedAt,
    required this.published,
    required this.onSave,
    required this.onGuide,
    required this.onAdd,
    required this.onPublished,
    this.onLibrary,
    this.onSavePass,
  });
  final TrainingSession session;
  final Future<(EventDetails, SquadDetails)> event;
  final TextEditingController theme;
  final bool unsaved, busy, published;
  final DateTime? savedAt;

  /// Taking a pass from the library, and saving the session as a pass;
  /// without them, not offered.
  final VoidCallback? onSave, onGuide, onLibrary, onSavePass;
  final VoidCallback onAdd;
  final ValueChanged<bool> onPublished;

  String _details(BuildContext context, EventDetails? event) =>
      detailParts(context, session, event).join('  •  ');

  /// The training's time, its place and its primary team, as known.
  static List<String> detailParts(
    BuildContext context,
    TrainingSession session,
    EventDetails? event,
  ) {
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime value) =>
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value));
    final place = [
      event?.locationName,
      event?.locationPitch,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' – ');
    final team = event?.teams.cast<Map<String, dynamic>?>().firstWhere(
      (team) => team?['relation'] == 'primary',
      orElse: () => null,
    )?['name'];
    return [
      '${localizations.formatMediumDate(session.startsAt)}  '
          '${time(session.startsAt)}–${time(session.endsAt)} '
          '(${session.eventMinutes} min)',
      if (place.isNotEmpty) place,
      if (team is String && team.isNotEmpty) team,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final divider = Container(
      width: 1,
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: colors.outlineVariant,
    );
    return Material(
      color: colors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 16, 14),
        child: Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Icon(Icons.sports, color: colors.primary, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FutureBuilder<(EventDetails, SquadDetails)>(
                    future: event,
                    builder: (context, snapshot) => Text(
                      _details(context, snapshot.data?.$1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            divider,
            Icon(Icons.track_changes, color: colors.primary, size: 30),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.feature('Träningsfokus'),
                    style: text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    key: const Key('training-program-theme'),
                    controller: theme,
                    maxLength: 200,
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: strings.feature(
                        'Till exempel press och återerövring',
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            divider,
            Icon(
              unsaved ? Icons.edit_note : Icons.check_circle,
              color: unsaved ? colors.onSurfaceVariant : Colors.green.shade700,
              size: 30,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.feature(unsaved ? 'Osparade ändringar' : 'Sparad'),
                    style: text.titleSmall,
                  ),
                  if (!unsaved && savedAt != null)
                    Text(
                      strings.formatFeature('Senast {time}', {
                        'time': MaterialLocalizations.of(
                          context,
                        ).formatTimeOfDay(TimeOfDay.fromDateTime(savedAt!)),
                      }),
                      style: text.bodySmall,
                    )
                  else if (!unsaved && session.updatedBy != null)
                    Text(
                      '${strings.feature('Senast ändrat av')} ${session.updatedBy}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            FilledButton.icon(
              key: const Key('training-session-save'),
              onPressed: onSave,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.save_outlined),
              label: Text(strings.feature(busy ? 'Sparar…' : 'Spara')),
            ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              key: const Key('training-guide-open'),
              onPressed: onGuide,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(strings.feature('Guidad planering')),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<int>(
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(color: colors.outlineVariant),
              ),
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => switch (value) {
                0 => onAdd(),
                2 => onLibrary?.call(),
                3 => onSavePass?.call(),
                _ => onPublished(!published),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 0,
                  child: Text(strings.feature('Lägg till övning')),
                ),
                if (onLibrary != null)
                  PopupMenuItem(
                    key: const Key('training-library-open'),
                    value: 2,
                    child: Text(strings.feature('Från biblioteket')),
                  ),
                if (onSavePass != null)
                  PopupMenuItem(
                    key: const Key('training-pass-save'),
                    value: 3,
                    child: Text(strings.feature('Spara och dela som pass')),
                  ),
                CheckedPopupMenuItem(
                  value: 1,
                  checked: published,
                  child: Text(strings.feature('Visa passet för spelarna')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Overview, planning and preparation as underlined tabs; on a phone they
/// share the width.
class _TrainingProgramTabs extends StatelessWidget {
  const _TrainingProgramTabs({
    required this.view,
    required this.onChanged,
    this.labels = const ['Översikt', 'Planering', 'Förberedelser'],
    this.expand = false,
  });
  final int view;
  final ValueChanged<int> onChanged;
  final List<String> labels;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: expand ? 8 : 16),
        child: Row(
          children: [
            for (final (i, label) in labels.indexed)
              _expanded(
                Semantics(
                  selected: view == i,
                  button: true,
                  child: InkWell(
                    onTap: () => onChanged(i),
                    child: Container(
                      alignment: expand ? Alignment.center : null,
                      padding: expand
                          ? const EdgeInsets.fromLTRB(4, 12, 4, 9)
                          : const EdgeInsets.fromLTRB(20, 12, 20, 9),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 3,
                            color: view == i
                                ? colors.primary
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      // Shared tabs shrink their label rather than cut it.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          strings.feature(label),
                          maxLines: 1,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: view == i
                                    ? colors.primary
                                    : colors.onSurface,
                                fontWeight: view == i
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
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

  Widget _expanded(Widget child) => expand ? Expanded(child: child) : child;
}

/// The session's exercises on a minute axis across the whole programme.
/// Blocks are dragged to change their order within their part.
class _TrainingTimeline extends StatefulWidget {
  const _TrainingTimeline({
    required this.blocks,
    required this.eventMinutes,
    required this.selected,
    required this.onSelect,
    required this.onReorder,
  });
  final List<TrainingBlock> blocks;
  final int eventMinutes;
  final int? selected;
  final ValueChanged<int> onSelect;
  final void Function(int from, int to) onReorder;

  @override
  State<_TrainingTimeline> createState() => _TrainingTimelineState();
}

class _TrainingTimelineState extends State<_TrainingTimeline> {
  int _step = 15;
  double _zoom = 1;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final blocks = widget.blocks;
    final minutes = blocks.fold(0, (sum, b) => sum + b.minutes);
    final over = widget.eventMinutes > 0 && minutes > widget.eventMinutes;
    final length = max(minutes, widget.eventMinutes).clamp(1, 1440);
    final outline = BorderSide(color: colors.outlineVariant);
    return _ProgramPanel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                strings.formatFeature('Tidslinje – {minutes} minuter', {
                  'minutes': widget.eventMinutes,
                }),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  strings.trainingMinutes(
                    minutes,
                    widget.eventMinutes,
                    planned: true,
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              PopupMenuButton<int>(
                tooltip: strings.feature('Tidsintervall'),
                initialValue: _step,
                onSelected: (value) => setState(() => _step = value),
                itemBuilder: (context) => [
                  for (final value in const [5, 10, 15, 30])
                    PopupMenuItem(value: value, child: Text('$value min')),
                ],
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  decoration: BoxDecoration(
                    border: Border.fromBorderSide(outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 18),
                      const SizedBox(width: 6),
                      Text('$_step min'),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ProgramIconButton(
                icon: Icons.zoom_out,
                tooltip: strings.feature('Zooma ut'),
                onPressed: _zoom > 1
                    ? () => setState(() => _zoom = max(1.0, _zoom / 1.5))
                    : null,
              ),
              _ProgramIconButton(
                icon: Icons.zoom_in,
                tooltip: strings.feature('Zooma in'),
                onPressed: _zoom < 4
                    ? () => setState(() => _zoom *= 1.5)
                    : null,
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _zoom == 1 ? null : () => setState(() => _zoom = 1),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(strings.feature('Anpassa')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = (constraints.maxWidth / length * _zoom).clamp(
                8.0,
                double.infinity,
              );
              final width = length * scale;
              // Labels thin out rather than overlap at short intervals.
              final every = (64 / (_step * scale)).ceil().clamp(1, 1000);
              final label = theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: 112,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 83,
                        width: width,
                        child: Container(
                          height: 2,
                          color: over ? colors.error : colors.outline,
                        ),
                      ),
                      for (var tick = 0; tick * _step <= length; tick++) ...[
                        Positioned(
                          left: (tick * _step * scale - 4).clamp(
                            0.0,
                            width - 8,
                          ),
                          top: 80,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (tick % every == 0)
                          Positioned(
                            left: (tick * _step * scale - 30).clamp(
                              0.0,
                              width - 60,
                            ),
                            top: 94,
                            child: SizedBox(
                              width: 60,
                              child: Text(
                                '${tick * _step} min',
                                style: label,
                                textAlign: tick == 0
                                    ? TextAlign.left
                                    : (tick + 1) * _step > length
                                    ? TextAlign.right
                                    : TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                      Positioned(
                        left: 0,
                        top: 0,
                        width: width,
                        height: 72,
                        child: ReorderableListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: blocks.length,
                          onReorderItem: widget.onReorder,
                          itemBuilder: (context, i) =>
                              _block(context, i, scale),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, int i, double scale) {
    final theme = Theme.of(context);
    final item = widget.blocks[i];
    final start = widget.blocks.take(i).fold(0, (sum, b) => sum + b.minutes);
    final part = _trainingPartColors(item.part);
    final selected = widget.selected == i;
    const ink = Color(0xFF2B2622);
    final phase = item.phase;
    return SizedBox(
      key: ObjectKey(item),
      width: item.minutes * scale,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ReorderableDragStartListener(
          index: i,
          child: Tooltip(
            message: '${item.title} · $start–${start + item.minutes} min',
            child: Material(
              color: selected
                  ? Color.alphaBlend(
                      part.accent.withValues(alpha: .4),
                      part.fill,
                    )
                  : part.fill,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: selected
                    ? BorderSide(color: part.accent, width: 2)
                    : BorderSide(color: part.accent.withValues(alpha: .25)),
              ),
              child: InkWell(
                onTap: () => widget.onSelect(i),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      if (phase != null)
                        Text(
                          AppStrings.of(context).feature(phase.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ink,
                          ),
                        ),
                      Text(
                        '$start–${start + item.minutes} min',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The session's parts with their exercises in order: select, add, edit,
/// move and remove. Exercises are dragged within their part.
class _TrainingStructure extends StatelessWidget {
  const _TrainingStructure({
    required this.blocks,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });
  final List<TrainingBlock> blocks;
  final int? selected;
  final ValueChanged<int> onSelect, onEdit, onRemove;
  final ValueChanged<TrainingPart?> onAdd;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.feature('Passets delar'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => onAdd(null),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(strings.feature('Lägg till')),
            ),
          ],
        ),
        for (final part in TrainingPart.values) ..._part(context, part),
      ],
    );
  }

  List<Widget> _part(BuildContext context, TrainingPart part) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = _trainingPartColors(part);
    const ink = Color(0xFF2B2622);
    final indices = [
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].part == part) i,
    ];
    final minutes = indices.fold(0, (sum, i) => sum + blocks[i].minutes);
    return [
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(
          color: palette.fill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: palette.accent,
              child: Icon(
                _trainingPartIcon(part),
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.feature(part.label),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            Text(
              '$minutes min',
              style: theme.textTheme.bodySmall?.copyWith(color: ink),
            ),
            PopupMenuButton<int>(
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              icon: const Icon(Icons.more_horiz, color: ink),
              onSelected: (_) => onAdd(part),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 0,
                  child: Text(strings.feature('Lägg till övning')),
                ),
              ],
            ),
          ],
        ),
      ),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: indices.length,
        onReorderItem: (from, to) =>
            onReorder(indices[from], indices.first + to),
        itemBuilder: (context, local) {
          final i = indices[local];
          final block = blocks[i];
          return Material(
            key: ObjectKey(block),
            color: selected == i
                ? Color.alphaBlend(palette.fill, colors.surfaceContainerLowest)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onSelect(i),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: local,
                      child: Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        block.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected == i ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${block.minutes} min',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    PopupMenuButton<int>(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).showMenuTooltip,
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (value) =>
                          value == 0 ? onEdit(i) : onRemove(i),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 0,
                          child: Text(strings.feature('Redigera')),
                        ),
                        PopupMenuItem(
                          value: 1,
                          child: Text(strings.feature('Ta bort')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        key: ValueKey('training-program-add-${part.name}'),
        onPressed: () => onAdd(part),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.add, size: 18),
        label: Text(strings.feature('Lägg till övning')),
      ),
    ];
  }
}
