part of '../../app/teamzone_app.dart';

/// The selected exercise in the middle of the programme: its name, a
/// diagram, organisation and coaching points.
class _TrainingExercisePanel extends StatelessWidget {
  const _TrainingExercisePanel({
    required this.block,
    required this.editorKey,
    required this.onChanged,
    required this.onSwap,
    required this.onCopy,
    required this.onRemove,
    required this.onGuide,
    this.onLinkBoard,
  });
  final TrainingBlock? block;

  /// Links a board from the library; null without the library.
  final VoidCallback? onLinkBoard;

  /// Changes when another exercise or a new draft is shown.
  final String editorKey;
  final ValueChanged<TrainingBlock> onChanged;
  final VoidCallback onSwap, onCopy, onRemove, onGuide;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final block = this.block;
    if (block == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(strings.feature('Inga övningar än.')),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onGuide,
              child: Text(strings.feature('Guidad planering')),
            ),
          ),
        ],
      );
    }
    final organisation = _TrainingNotesField(
      key: ValueKey('notes-organisation-$editorKey'),
      fieldKey: ValueKey('workspace-organisation-$editorKey'),
      label: strings.feature('Organisation'),
      hint: strings.feature('Yta, antal spelare, regler'),
      initialValue: block.organisation,
      onChanged: (value) => onChanged(block.copyWith(organisation: value)),
    );
    final coaching = _TrainingNotesField(
      key: ValueKey('notes-coaching-$editorKey'),
      fieldKey: ValueKey('workspace-coaching-$editorKey'),
      label: strings.feature('Coachpunkter'),
      hint: strings.feature('Vad ledarna lyfter under övningen'),
      initialValue: block.coachingPoints,
      onChanged: (value) => onChanged(block.copyWith(coachingPoints: value)),
    );
    final illustration = _ExerciseIllustration(
      board: block.board,
      onLink: onLinkBoard,
      onUnlink: () => onChanged(block.copyWith(clearBoard: true)),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('workspace-title-$editorKey'),
                initialValue: block.title,
                maxLength: 120,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: strings.feature('Övningens namn'),
                  border: InputBorder.none,
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.primary),
                  ),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? strings.feature('Ange ett namn på övningen.')
                    : null,
                onChanged: (value) => onChanged(block.copyWith(title: value)),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onSwap,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text(strings.feature('Byt övning')),
            ),
            const SizedBox(width: 8),
            _ProgramIconButton(
              icon: Icons.content_copy_outlined,
              tooltip: strings.feature('Kopiera övning'),
              onPressed: onCopy,
            ),
            const SizedBox(width: 4),
            _ProgramIconButton(
              icon: Icons.delete_outline,
              tooltip: strings.feature('Ta bort övning'),
              color: colors.error,
              onPressed: onRemove,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 2, color: colors.primary.withValues(alpha: .35)),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 640
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: SizedBox(height: 440, child: illustration)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          organisation,
                          const SizedBox(height: 16),
                          coaching,
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(height: 280, child: illustration),
                    const SizedBox(height: 16),
                    organisation,
                    const SizedBox(height: 16),
                    coaching,
                  ],
                ),
        ),
        const SizedBox(height: 16),
        // Placeholder until exercises carry a purpose of their own.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E0),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF2D7A6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${strings.feature('Syfte')}: ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: strings.feature(
                          'Övningens syfte kan beskrivas här i en kommande version.',
                        ),
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4A3B22),
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

/// A plain-text note with a formatting row. Lists are written as text;
/// bold, italic and links wait for formatted notes.
class _TrainingNotesField extends StatefulWidget {
  const _TrainingNotesField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onChanged,
  });
  final Key fieldKey;
  final String label, hint, initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_TrainingNotesField> createState() => _TrainingNotesFieldState();
}

class _TrainingNotesFieldState extends State<_TrainingNotesField> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Starts each selected line with a bullet, or with its number.
  void _list({required bool numbered}) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: text.length);
    final start = text.lastIndexOf('\n', max(0, selection.start - 1)) + 1;
    final found = text.indexOf('\n', selection.end);
    final end = found < 0 ? text.length : found;
    final bullet = RegExp(r'^(• |\d+\. )');
    final lines = text.substring(start, end).split('\n');
    final changed = [
      for (final (i, line) in lines.indexed)
        '${numbered ? '${i + 1}. ' : '• '}${line.replaceFirst(bullet, '')}',
    ].join('\n');
    final next = text.replaceRange(start, end, changed);
    if (next.length > 2000) return;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + changed.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final later = strings.feature('Formatering kommer snart');
    Widget tool(IconData icon, String tooltip, VoidCallback? onPressed) =>
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          icon: Icon(icon),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  border: Border(
                    bottom: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    tool(Icons.format_bold, later, null),
                    tool(Icons.format_italic, later, null),
                    tool(
                      Icons.format_list_bulleted,
                      strings.feature('Punktlista'),
                      () => _list(numbered: false),
                    ),
                    tool(
                      Icons.format_list_numbered,
                      strings.feature('Numrerad lista'),
                      () => _list(numbered: true),
                    ),
                    tool(Icons.link, later, null),
                  ],
                ),
              ),
              TextFormField(
                key: widget.fieldKey,
                controller: _controller,
                minLines: 6,
                maxLines: 12,
                maxLength: 2000,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  counterStyle: theme.textTheme.labelSmall,
                ),
                onChanged: widget.onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A placeholder diagram until the app shows boards, with the board linked
/// from Tacticsboard's library and the buttons to link or unlink one.
class _ExerciseIllustration extends StatelessWidget {
  const _ExerciseIllustration({this.board, this.onLink, this.onUnlink});
  final TrainingBoardLink? board;
  final VoidCallback? onLink, onUnlink;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final board = this.board;
    const white = TextStyle(color: Colors.white, fontSize: 13);
    final label = board == null
        ? strings.feature('Tom tavla')
        : strings.formatFeature('Tavla: {name}', {'name': board.name});
    return Semantics(
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _ExercisePitchPainter()),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      board == null ? Icons.draw_outlined : Icons.link,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        key: const Key('training-board-name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: white,
                      ),
                    ),
                    if (onLink != null)
                      TextButton(
                        key: const Key('training-board-link'),
                        onPressed: onLink,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          strings.feature(
                            board == null ? 'Länka tavla' : 'Byt tavla',
                          ),
                        ),
                      ),
                    if (board != null && onUnlink != null)
                      IconButton(
                        key: const Key('training-board-unlink'),
                        tooltip: strings.feature('Ta bort länken'),
                        onPressed: onUnlink,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.link_off,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExercisePitchPainter extends CustomPainter {
  const _ExercisePitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stripe = size.height / 10;
    for (var i = 0; i < 10; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * stripe, size.width, stripe + 1),
        Paint()
          ..color = i.isEven
              ? const Color(0xFF4E8F3A)
              : const Color(0xFF468434),
      );
    }
    final area = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * .64,
      height: size.height * .64,
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..strokeWidth = 2.5;
    // A dashed square: the exercise's area.
    for (final (from, to) in [
      (area.topLeft, area.topRight),
      (area.topRight, area.bottomRight),
      (area.bottomRight, area.bottomLeft),
      (area.bottomLeft, area.topLeft),
    ]) {
      final length = (to - from).distance;
      final step = (to - from) / length;
      for (var d = 0.0; d < length; d += 14) {
        canvas.drawLine(
          from + step * d,
          from + step * min(d + 8, length),
          line,
        );
      }
    }
    final cone = Paint()..color = const Color(0xFFF28C38);
    for (final corner in [
      area.topLeft,
      area.topRight,
      area.bottomLeft,
      area.bottomRight,
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy - 9)
          ..lineTo(corner.dx - 7, corner.dy + 6)
          ..lineTo(corner.dx + 7, corner.dy + 6)
          ..close(),
        cone,
      );
    }
    void player(Offset at, Color color) {
      canvas.drawCircle(at, 9, Paint()..color = color);
      canvas.drawCircle(
        at,
        9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final blue = const Color(0xFF1E5BB8);
    for (final at in [
      Offset(area.center.dx, area.top),
      Offset(area.right, area.center.dy),
      Offset(area.center.dx + area.width * .2, area.bottom),
      Offset(area.left, area.center.dy + area.height * .1),
      Offset(area.center.dx + area.width * .15, area.center.dy - 40),
    ]) {
      player(at, blue);
    }
    player(area.center + const Offset(-20, 10), const Color(0xFFD03A2F));
    player(area.center + const Offset(28, 30), const Color(0xFFD03A2F));
  }

  @override
  bool shouldRepaint(_ExercisePitchPainter oldDelegate) => false;
}

/// The selected exercise's properties, and the session's visibility.
/// Fields without data yet are shown disabled as placeholders.
class _TrainingProperties extends StatefulWidget {
  const _TrainingProperties({
    required this.block,
    required this.editorKey,
    required this.published,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onChanged,
    required this.onPart,
    required this.onMove,
    required this.onPublished,
  });
  final TrainingBlock? block;
  final String editorKey;
  final bool published, canMoveUp, canMoveDown;
  final ValueChanged<TrainingBlock> onChanged;
  final ValueChanged<TrainingPart> onPart;
  final ValueChanged<int> onMove;
  final ValueChanged<bool> onPublished;

  @override
  State<_TrainingProperties> createState() => _TrainingPropertiesState();
}

class _TrainingPropertiesState extends State<_TrainingProperties> {
  bool _more = false;

  InputDecoration _decoration(
    BuildContext context, {
    IconData? icon,
    String? hint,
  }) => InputDecoration(
    isDense: true,
    counterText: '',
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(
      AppStrings.of(context).feature(text),
      style: Theme.of(context).textTheme.labelLarge,
    ),
  );

  /// A disabled field standing in for a property exercises do not have yet.
  Widget _later(BuildContext context, IconData icon) => TextField(
    enabled: false,
    decoration: _decoration(
      context,
      icon: icon,
      hint: AppStrings.of(context).feature('Kommer snart'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final block = widget.block;
    final key = widget.editorKey;
    final published = SwitchListTile(
      key: const Key('training-program-published'),
      contentPadding: EdgeInsets.zero,
      title: Text(strings.feature('Visa passet för spelarna')),
      value: widget.published,
      onChanged: widget.onPublished,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          strings.feature('Egenskaper'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (block == null) ...[
          const SizedBox(height: 12),
          Text(strings.feature('Välj en övning i tidslinjen.')),
          published,
        ] else ...[
          _label(context, 'Längd'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('workspace-minutes-$key'),
                  initialValue: '${block.minutes}',
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  decoration: _decoration(context, icon: Icons.timer_outlined),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 0 || number > 240
                        ? strings.feature('Ange 0–240 minuter.')
                        : null;
                  },
                  onChanged: (value) {
                    final number = int.tryParse(value);
                    if (number != null && number >= 0 && number <= 240) {
                      widget.onChanged(block.copyWith(minutes: number));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 56,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: const Text('min'),
              ),
            ],
          ),
          _label(context, 'Passets del'),
          DropdownButtonFormField<TrainingPart>(
            key: ValueKey('workspace-part-$key'),
            initialValue: block.part,
            isExpanded: true,
            decoration: _decoration(context),
            items: [
              for (final part in TrainingPart.values)
                DropdownMenuItem(
                  value: part,
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: _trainingPartColors(part).accent,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          strings.feature(part.label),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (part) {
              if (part != null) widget.onPart(part);
            },
          ),
          _label(context, 'Spelfas'),
          DropdownButtonFormField<PrincipleArea?>(
            key: ValueKey('workspace-phase-$key'),
            initialValue: block.phase,
            isExpanded: true,
            decoration: _decoration(context, icon: Icons.sports_soccer),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(strings.feature('Inget skede')),
              ),
              for (final area in PrincipleArea.values)
                DropdownMenuItem(
                  value: area,
                  child: Text(
                    strings.feature(area.label),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => widget.onChanged(
              block.copyWith(phase: value, clearPhase: value == null),
            ),
          ),
          _label(context, 'Syfte'),
          _later(context, Icons.flag_outlined),
          _label(context, 'Yta (meter)'),
          _later(context, Icons.crop_free),
          _label(context, 'Antal spelare'),
          _PlayerCounts(players: block.players),
          _label(context, 'Material'),
          _later(context, Icons.inventory_2_outlined),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _more = !_more),
              icon: Icon(_more ? Icons.expand_less : Icons.expand_more),
              label: Text(strings.feature('Fler alternativ')),
            ),
          ),
          if (_more) ...[
            published,
            Row(
              children: [
                IconButton(
                  tooltip: strings.feature('Flytta upp'),
                  onPressed: widget.canMoveUp ? () => widget.onMove(-1) : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: strings.feature('Flytta ned'),
                  onPressed: widget.canMoveDown ? () => widget.onMove(1) : null,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// How many players each team colour has in the exercise, "7 vs 2".
class _PlayerCounts extends StatelessWidget {
  const _PlayerCounts({required this.players});
  final List<TrainingBlockPlayer> players;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final counts = [
      for (final team in TrainingPlayerTeam.values)
        if (players.any((player) => player.team == team))
          (team, players.where((player) => player.team == team).length),
    ];
    Widget box(Color? color, int count) => Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 18, color: color),
          const SizedBox(width: 6),
          Text('$count'),
        ],
      ),
    );
    return Tooltip(
      message: AppStrings.of(
        context,
      ).feature('Räknas från spelarnas lagfärger.'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: counts.length < 2
            ? [box(null, players.length)]
            : [
                for (final (i, (team, count)) in counts.indexed) ...[
                  if (i > 0) const Text('vs'),
                  box(_trainingPlayerColor(team), count),
                ],
              ],
      ),
    );
  }
}
