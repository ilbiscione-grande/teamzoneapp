part of '../../app/teamzone_app.dart';

/// The Förberedelser tab: a small per-event workspace in the same compact
/// visual language as the Deltagare tab (thin separators, 12–13 px section
/// headers, 28 px avatars, ~40 px rows). Sections depend on the event type;
/// empty sections collapse to their header. There is intentionally no
/// overall progress or "färdigförberedd" state — only individual items can
/// be ticked.
class _PreparationTab extends StatefulWidget {
  const _PreparationTab({
    super.key,
    required this.event,
    required this.people,
    required this.services,
    required this.allowEdit,
    this.onOpenMatchMode,
    this.onChanged,
  });

  final EventDetails event;

  /// Everyone relevant to the event (roster, guests, called-up people):
  /// candidates for task owners and "valda personer" file visibility.
  final List<EventRosterPerson> people;
  final EventPreparationServices services;

  /// The active team context may edit (the server decides per actor too).
  final bool allowEdit;
  final VoidCallback? onOpenMatchMode;
  final VoidCallback? onChanged;

  @override
  State<_PreparationTab> createState() => _PreparationTabState();
}

class _PendingUpload {
  _PendingUpload({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.visibility,
    required this.personIds,
  });
  final String id, name, mimeType, visibility;
  final Uint8List bytes;
  final List<String> personIds;
  bool failed = false;
}

class _PreparationTabState extends State<_PreparationTab> {
  EventPreparation? _data;
  bool _loadFailed = false;
  StreamSubscription<void>? _live;
  Timer? _liveDebounce;
  final List<_PendingUpload> _uploads = [];

  // Checkbox state shown before the server confirms; reverted on failure.
  final Map<String, bool> _optimisticDone = {};

  EventPreparationServices get _services => widget.services;
  // Each area follows its own capability (logistics, training, match);
  // the active team context must also allow editing.
  PreparationPermissions get _permissions =>
      _data?.permissions ?? const PreparationPermissions();
  bool get _canLogistics => widget.allowEdit && _permissions.logistics;
  bool get _canTraining => widget.allowEdit && _permissions.training;
  bool get _canNote => switch (widget.event.type) {
    'training' => widget.allowEdit && _permissions.training,
    'match' => widget.allowEdit && _permissions.match,
    _ => _canLogistics,
  };
  bool get _canAny => _canLogistics || _canTraining || _canNote;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _live = _services.watchEventLive(widget.event.id).listen((_) {
      _liveDebounce?.cancel();
      _liveDebounce = Timer(
        const Duration(milliseconds: 350),
        () => unawaited(_reload()),
      );
    });
  }

  @override
  void dispose() {
    _liveDebounce?.cancel();
    unawaited(_live?.cancel());
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final data = await _services.getPreparation(widget.event.id);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted && _data == null) setState(() => _loadFailed = true);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a write, then refreshes. Conflicts (another leader changed the
  /// same thing first) reload the latest state instead of overwriting it.
  Future<bool> _write(
    Future<void> Function() action, {
    String failure = 'Ändringen kunde inte sparas. Försök igen.',
  }) async {
    try {
      await action();
      await _reload();
      if (mounted) widget.onChanged?.call();
      return true;
    } on PreparationConflict {
      await _reload();
      if (mounted) {
        _snack('Någon annan ändrade samtidigt. Visar senaste versionen.');
      }
    } catch (_) {
      if (mounted) _snack(failure);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (!_loadFailed) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: _StateCard(
          icon: Icons.sync_problem,
          title: 'Förberedelser kunde inte laddas',
          message: AppStrings.of(context).safeError,
          action: FilledButton(
            onPressed: () {
              setState(() => _loadFailed = false);
              unawaited(_reload());
            },
            child: Text(AppStrings.of(context).retry),
          ),
        ),
      );
    }
    final type = widget.event.type;
    final sections = <Widget?>[
      if (type == 'match' && widget.onOpenMatchMode != null) _matchModeCard(),
      _KpiGoalsSection(
        key: ValueKey('kpi-goals-${widget.event.id}'),
        event: widget.event,
        services: widget.services,
        allowEdit: widget.allowEdit,
        onChanged: widget.onChanged,
      ),
      ...switch (type) {
        'training' => [
          _focusSection(data),
          _noteSection(data, 'Anteckningar'),
          _materialSection(data),
          _taskSection(data),
          _fileSection(data),
        ],
        'match' => [
          _noteSection(data, 'Matchförberedelse'),
          _materialSection(data),
          _taskSection(data),
          _fileSection(data),
        ],
        'meeting' => [
          _agendaSection(data),
          _taskSection(data),
          _noteSection(data, 'Anteckningar'),
          _fileSection(data),
        ],
        _ => [
          _noteSection(data, 'Anteckningar'),
          _taskSection(data),
          _fileSection(data),
        ],
      },
    ].whereType<Widget>().toList();
    final empty =
        !_canAny &&
        data.items.isEmpty &&
        data.note.body.trim().isEmpty &&
        data.files.isEmpty;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: EdgeInsets.only(bottom: _assistantUsesFab(context) ? 88 : 24),
        children: [
          ...sections,
          if (empty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Inga förberedelser ännu.'),
            ),
        ],
      ),
    );
  }

  // --- Building blocks -----------------------------------------------------

  Widget _section({
    required String title,
    int? count,
    required bool isEmpty,
    VoidCallback? onAdd,
    List<Widget> children = const [],
    String? addLabel,
  }) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant, width: .5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8, top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .3,
                          ),
                        ),
                      ),
                      if (count != null && count > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '$count',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      if (isEmpty && onAdd != null)
                        _compactTextButton(
                          icon: Icons.add,
                          label: 'Lägg till',
                          onPressed: onAdd,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (!isEmpty) ...children,
            if (!isEmpty && onAdd != null && addLabel != null)
              _addRow(addLabel, onAdd),
          ],
        ),
      ),
    );
  }

  Widget _compactTextButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => TextButton.icon(
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 13),
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );

  Widget _addRow(String label, VoidCallback onPressed) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Material(
        color: colors.primary.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.add, size: 18, color: colors.primary),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 14, color: colors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get _rowHeight =>
      40 + (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 40);

  bool _done(PreparationItem item) => _optimisticDone[item.id] ?? item.done;

  Future<void> _toggleDone(PreparationItem item) async {
    final target = !_done(item);
    setState(() => _optimisticDone[item.id] = target);
    try {
      await _services.setItemDone(item.id, target);
      await _reload();
      if (mounted) widget.onChanged?.call();
    } catch (_) {
      if (mounted) _snack('Kunde inte spara markeringen. Försök igen.');
    } finally {
      if (mounted) setState(() => _optimisticDone.remove(item.id));
    }
  }

  Widget _checkbox(PreparationItem item, {required String semanticLabel}) {
    final checked = _done(item);
    return SizedBox(
      width: 44,
      height: 40,
      child: Center(
        child: Checkbox(
          value: checked,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          semanticLabel: semanticLabel,
          onChanged: _canLogistics ? (_) => _toggleDone(item) : null,
        ),
      ),
    );
  }

  Widget _moreMenu(List<(String, IconData, VoidCallback)> actions) =>
      PopupMenuButton<VoidCallback>(
        tooltip: 'Fler val',
        padding: EdgeInsets.zero,
        iconSize: 20,
        constraints: const BoxConstraints(minWidth: 160),
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          for (final (label, icon, action) in actions)
            PopupMenuItem(
              value: action,
              height: 40,
              child: Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 12),
                  Text(label),
                ],
              ),
            ),
        ],
      );

  // --- Öppna matchläge -------------------------------------------------------

  Widget _matchModeCard() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Semantics(
        button: true,
        child: Material(
          color: colors.primary.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const ValueKey('open-match-mode'),
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onOpenMatchMode,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.sports_soccer, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Öppna matchläge',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                        const Text(
                          'Resultat, tidtagning och målhändelser',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Träningsfokus ---------------------------------------------------------

  Widget? _focusSection(EventPreparation data) {
    final items = data.itemsOf(PreparationKind.focus);
    if (items.isEmpty && !_canTraining) return null;
    return _section(
      title: 'Träningsfokus',
      count: items.length,
      isEmpty: items.isEmpty,
      onAdd: _canTraining ? () => _addLabels(PreparationKind.focus) : null,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final item in items)
                InputChip(
                  label: Text(item.label),
                  visualDensity: VisualDensity.compact,
                  onDeleted: _canTraining
                      ? () => _write(
                          () => _services.deleteItem(data.eventId, item.id),
                        )
                      : null,
                  deleteButtonTooltipMessage: 'Ta bort ${item.label}',
                ),
              if (_canTraining)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Lägg till'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _addLabels(PreparationKind.focus),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addLabels(String kind) async {
    final data = _data;
    if (data == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _AddLabelsSheet(
        title: switch (kind) {
          PreparationKind.focus => 'Lägg till träningsfokus',
          PreparationKind.material => 'Lägg till material',
          _ => 'Lägg till punkt',
        },
        customHint: switch (kind) {
          PreparationKind.focus => 'Skapa eget fokus',
          PreparationKind.material => 'Skapa eget',
          _ => 'Ny agendapunkt',
        },
        existing: data
            .itemsOf(kind)
            .map((item) => item.label.toLowerCase())
            .toSet(),
        suggestions:
            kind == PreparationKind.focus || kind == PreparationKind.material
            ? _services
                  .listSuggestions(data.eventId, kind)
                  .catchError((_) => <String>[])
            : Future.value(const <String>[]),
        onAdd: (label) => _write(
          () => _services.saveItem(
            eventId: data.eventId,
            itemId: _newUuid(),
            kind: kind,
            label: label,
            expectedRevision: 0,
          ),
        ),
      ),
    );
  }

  // --- Anteckningar ----------------------------------------------------------

  Widget? _noteSection(EventPreparation data, String title) {
    final body = data.note.body.trim();
    if (body.isEmpty && !_canNote) return null;
    final colors = Theme.of(context).colorScheme;
    return _section(
      title: title,
      isEmpty: body.isEmpty,
      onAdd: _canNote ? () => _editNote(title) : null,
      children: [
        InkWell(
          onTap: _canNote ? () => _editNote(title) : () => _readNote(title),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_canNote)
                  IconButton(
                    tooltip: 'Redigera ${title.toLowerCase()}',
                    style: IconButton.styleFrom(
                      backgroundColor: colors.primary.withValues(alpha: .08),
                      minimumSize: const Size(40, 40),
                    ),
                    onPressed: () => _editNote(title),
                    icon: Icon(
                      Icons.edit_note,
                      size: 22,
                      color: colors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _readNote(String title) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(_data?.note.body ?? ''),
          ],
        ),
      ),
    ),
  );

  Future<void> _editNote(String title, {String? draft}) async {
    final data = _data;
    if (data == null) return;
    final revision = data.note.revision;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoteEditorSheet(
        title: title,
        initial: draft ?? data.note.body,
        conflictNotice: draft != null,
      ),
    );
    if (text == null || !mounted) return;
    try {
      await _services.saveNote(data.eventId, text, revision);
      await _reload();
    } on PreparationConflict {
      await _reload();
      if (!mounted) return;
      _snack('Anteckningen ändrades av någon annan. Granska och spara igen.');
      await _editNote(title, draft: text);
    } catch (_) {
      if (!mounted) return;
      _snack('Anteckningen kunde inte sparas. Försök igen.');
      await _editNote(title, draft: text);
    }
  }

  // --- Material --------------------------------------------------------------

  Widget? _materialSection(EventPreparation data) {
    final items = data.itemsOf(PreparationKind.material);
    if (items.isEmpty && !_canLogistics) return null;
    return _section(
      title: 'Material',
      count: items.length,
      isEmpty: items.isEmpty,
      onAdd: _canLogistics ? () => _addLabels(PreparationKind.material) : null,
      addLabel: 'Lägg till material',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720
                ? 4
                : constraints.maxWidth >= 480
                ? 3
                : 2;
            final width = (constraints.maxWidth - 8) / columns;
            return Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Wrap(
                children: [
                  for (final item in items)
                    SizedBox(width: width, child: _materialCell(data, item)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _materialCell(EventPreparation data, PreparationItem item) =>
      Semantics(
        onLongPressHint: _canLogistics ? 'Byt namn eller ta bort' : null,
        child: InkWell(
          onTap: _canLogistics ? () => _toggleDone(item) : null,
          onLongPress: _canLogistics
              ? () => _itemOptions(data, item, allowRename: true)
              : null,
          child: SizedBox(
            height: _rowHeight,
            child: Row(
              children: [
                _checkbox(item, semanticLabel: item.label),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _itemOptions(
    EventPreparation data,
    PreparationItem item, {
    required bool allowRename,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              title: Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (allowRename)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Byt namn'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Ta bort'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') {
      await _write(() => _services.deleteItem(data.eventId, item.id));
    } else if (action == 'rename') {
      final label = await _promptText(
        title: 'Byt namn',
        initial: item.label,
        maxLength: 200,
      );
      if (label == null || label == item.label) return;
      await _write(
        () => _services.saveItem(
          eventId: data.eventId,
          itemId: item.id,
          kind: item.kind,
          label: label,
          assigneePersonId: item.assigneePersonId,
          expectedRevision: item.revision,
        ),
      );
    }
  }

  Future<String?> _promptText({
    required String title,
    String initial = '',
    int maxLength = 200,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (text) => Navigator.pop(context, text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Spara'),
          ),
        ],
      ),
    );
    disposeAfterDialog([controller]);
    return value == null || value.isEmpty ? null : value;
  }

  // --- Uppgifter -------------------------------------------------------------

  Widget? _taskSection(EventPreparation data) {
    final items = data.itemsOf(PreparationKind.task);
    if (items.isEmpty && !_canLogistics) return null;
    return _section(
      title: 'Uppgifter',
      count: items.length,
      isEmpty: items.isEmpty,
      onAdd: _canLogistics ? () => _editTask(data, null) : null,
      addLabel: 'Lägg till uppgift',
      children: [for (final item in items) _taskRow(data, item)],
    );
  }

  Widget _taskRow(EventPreparation data, PreparationItem item) {
    final colors = Theme.of(context).colorScheme;
    final owner = item.assigneeName;
    return InkWell(
      onTap: _canLogistics ? () => _editTask(data, item) : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _rowHeight),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              _personAvatar(owner),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Text(
                  owner ?? 'Ingen ansvarig',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: owner == null ? colors.onSurfaceVariant : null,
                    fontStyle: owner == null ? FontStyle.italic : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              _checkbox(
                item,
                semanticLabel:
                    '${item.label}${owner == null ? '' : ', $owner'}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _personAvatar(String? name, {double radius = 14}) {
    final colors = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.primary.withValues(alpha: .14),
      child: name == null
          ? Icon(Icons.person_outline, size: radius, color: colors.primary)
          : Text(
              _initialsOf(name),
              style: TextStyle(fontSize: radius * .78, color: colors.primary),
            ),
    );
  }

  List<EventRosterPerson> get _peopleSorted {
    final unique = <String, EventRosterPerson>{
      for (final person in widget.people) person.personId: person,
    };
    int rank(EventRosterPerson p) =>
        p.rolePackage == 'leader' || p.rolePackage == 'club_functionary'
        ? 0
        : 1;
    return unique.values.toList()..sort((a, b) {
      final byRole = rank(a).compareTo(rank(b));
      return byRole != 0 ? byRole : a.name.compareTo(b.name);
    });
  }

  Future<void> _editTask(EventPreparation data, PreparationItem? item) async {
    final result = await showModalBottomSheet<_TaskEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TaskEditorSheet(
        item: item,
        people: _peopleSorted,
        initials: _initialsOf,
      ),
    );
    if (result == null || !mounted) return;
    if (result.delete && item != null) {
      await _write(() => _services.deleteItem(data.eventId, item.id));
      return;
    }
    await _write(
      () => _services.saveItem(
        eventId: data.eventId,
        itemId: item?.id ?? _newUuid(),
        kind: PreparationKind.task,
        label: result.label,
        assigneePersonId: result.assigneeId,
        expectedRevision: item?.revision ?? 0,
      ),
    );
  }

  // --- Agenda ----------------------------------------------------------------

  Widget? _agendaSection(EventPreparation data) {
    final items = data.itemsOf(PreparationKind.agenda);
    if (items.isEmpty && !_canLogistics) return null;
    return _section(
      title: 'Agenda',
      count: items.length,
      isEmpty: items.isEmpty,
      onAdd: _canLogistics ? () => _addLabels(PreparationKind.agenda) : null,
      addLabel: 'Lägg till punkt',
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => _reorderAgenda(data, items, from, to),
          children: [
            for (var index = 0; index < items.length; index++)
              _agendaRow(data, items[index], index),
          ],
        ),
      ],
    );
  }

  Widget _agendaRow(
    EventPreparation data,
    PreparationItem item,
    int index,
  ) => Material(
    key: ValueKey('agenda-${item.id}'),
    color: Theme.of(context).colorScheme.surface,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: _rowHeight),
      child: Row(
        children: [
          if (_canLogistics)
            ReorderableDragStartListener(
              index: index,
              child: const Tooltip(
                message: 'Dra för att ändra ordning',
                child: SizedBox(
                  width: 36,
                  height: 40,
                  child: Icon(Icons.drag_indicator, size: 20),
                ),
              ),
            )
          else
            const SizedBox(width: 8),
          _checkbox(item, semanticLabel: item.label),
          Expanded(
            child: Text(
              item.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                decoration: _done(item) ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (_canLogistics)
            _moreMenu([
              ('Redigera', Icons.edit_outlined, () => _renameItem(data, item)),
              (
                'Ta bort',
                Icons.delete_outline,
                () => _write(() => _services.deleteItem(data.eventId, item.id)),
              ),
            ])
          else
            const SizedBox(width: 12),
        ],
      ),
    ),
  );

  Future<void> _renameItem(EventPreparation data, PreparationItem item) async {
    final label = await _promptText(title: 'Redigera', initial: item.label);
    if (label == null || label == item.label) return;
    await _write(
      () => _services.saveItem(
        eventId: data.eventId,
        itemId: item.id,
        kind: item.kind,
        label: label,
        expectedRevision: item.revision,
      ),
    );
  }

  Future<void> _reorderAgenda(
    EventPreparation data,
    List<PreparationItem> items,
    int from,
    int to,
  ) async {
    final ordered = [...items];
    final moved = ordered.removeAt(from);
    ordered.insert(to, moved);
    // Show the new order immediately; the server confirms or we reload.
    setState(() {
      _data = data.copyWith(
        items: [
          ...data.items.where((item) => item.kind != PreparationKind.agenda),
          for (var i = 0; i < ordered.length; i++)
            PreparationItem(
              id: ordered[i].id,
              kind: ordered[i].kind,
              label: ordered[i].label,
              done: ordered[i].done,
              position: i,
              revision: ordered[i].revision,
            ),
        ],
      );
    });
    await _write(
      () => _services.reorderItems(
        data.eventId,
        PreparationKind.agenda,
        ordered.map((item) => item.id).toList(),
      ),
      failure: 'Ordningen kunde inte sparas.',
    );
  }

  // --- Filer -----------------------------------------------------------------

  Widget _fileSection(EventPreparation data) {
    final isEmpty = data.files.isEmpty && _uploads.isEmpty;
    return _section(
      title: 'Filer',
      count: data.files.length,
      isEmpty: isEmpty,
      onAdd: _canLogistics ? _pickFile : null,
      addLabel: 'Lägg till fil',
      children: [
        for (final file in data.files) _fileRow(file),
        for (final upload in _uploads) _uploadRow(upload),
      ],
    );
  }

  (IconData, Color) _fileIcon(String mimeType) => switch (mimeType) {
    'application/pdf' => (Icons.picture_as_pdf_outlined, Colors.red.shade600),
    final String type when type.startsWith('image/') => (
      Icons.image_outlined,
      Colors.blue.shade600,
    ),
    final String type when type.contains('spreadsheet') || type == 'text/csv' =>
      (Icons.table_chart_outlined, Colors.green.shade700),
    final String type when type.contains('presentation') => (
      Icons.slideshow_outlined,
      Colors.orange.shade700,
    ),
    _ => (Icons.description_outlined, Colors.blueGrey),
  };

  (IconData, String, String) _visibilityLabel(EventFile file) =>
      switch (file.visibility) {
        FileVisibility.leaders => (
          Icons.lock_outline,
          'Ledare',
          'Endast ledare',
        ),
        FileVisibility.selected => (
          Icons.person_outline,
          '${file.viewerCount} pers.',
          'Synlig för ${file.viewerCount} valda personer',
        ),
        _ => (Icons.groups_outlined, 'Alla', 'Synlig för alla deltagare'),
      };

  String _sizeLabel(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} kB';
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
    return '$mb MB';
  }

  Widget _fileRow(EventFile file) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = _fileIcon(file.mimeType);
    final (visibilityIcon, visibilityText, visibilityTooltip) =
        _visibilityLabel(file);
    return Semantics(
      button: true,
      label: '${file.name}, ${_sizeLabel(file.sizeBytes)}, $visibilityTooltip',
      excludeSemantics: !_canLogistics,
      child: InkWell(
        onTap: () => _openFile(file),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _rowHeight),
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: _canLogistics ? 0 : 16),
            child: Row(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Tooltip(
                  message: '$visibilityTooltip · ${_sizeLabel(file.sizeBytes)}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        visibilityIcon,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        visibilityText,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_canLogistics)
                  _moreMenu([
                    ('Öppna', Icons.open_in_new, () => _openFile(file)),
                    (
                      'Ändra synlighet',
                      Icons.visibility_outlined,
                      () => _changeVisibility(file),
                    ),
                    ('Ta bort', Icons.delete_outline, () => _deleteFile(file)),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _uploadRow(_PendingUpload upload) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            upload.failed
                ? Icon(Icons.error_outline, size: 22, color: colors.error)
                : const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                upload.failed
                    ? '${upload.name} – uppladdningen misslyckades'
                    : '${upload.name} – laddar upp…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (upload.failed) ...[
              IconButton(
                tooltip: 'Försök igen',
                onPressed: () => _upload(upload),
                icon: const Icon(Icons.refresh, size: 20),
              ),
              IconButton(
                tooltip: 'Avbryt',
                onPressed: () => setState(() => _uploads.remove(upload)),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _mimeByExtension = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };

  Future<void> _pickFile() async {
    final FilePickerResult? pick;
    try {
      pick = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: _mimeByExtension.keys.toList(),
      );
    } catch (_) {
      if (mounted) _snack('Filväljaren kunde inte öppnas.');
      return;
    }
    final file = pick?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    final mime = _mimeByExtension[file.extension?.toLowerCase()];
    if (mime == null) {
      _snack('Filtypen stöds inte. Använd PDF, bild, text eller Office-fil.');
      return;
    }
    if (bytes.length > 20 * 1024 * 1024) {
      _snack('Filen är större än 20 MB.');
      return;
    }
    final visibility = await _chooseVisibility(
      title: 'Vem ska se ${file.name}?',
      initial: FileVisibility.participants,
      initialIds: const [],
    );
    if (visibility == null || !mounted) return;
    final upload = _PendingUpload(
      id: _newUuid(),
      name: file.name,
      mimeType: mime,
      bytes: bytes,
      visibility: visibility.$1,
      personIds: visibility.$2,
    );
    setState(() => _uploads.add(upload));
    await _upload(upload);
  }

  Future<void> _upload(_PendingUpload upload) async {
    setState(() => upload.failed = false);
    try {
      await _services.uploadFile(
        eventId: widget.event.id,
        fileId: upload.id,
        name: upload.name,
        mimeType: upload.mimeType,
        bytes: upload.bytes,
        visibility: upload.visibility,
        personIds: upload.personIds,
      );
      await _reload();
      if (mounted) setState(() => _uploads.remove(upload));
    } catch (_) {
      if (mounted) setState(() => upload.failed = true);
    }
  }

  Future<(String, List<String>)?> _chooseVisibility({
    required String title,
    required String initial,
    required List<String> initialIds,
  }) => showModalBottomSheet<(String, List<String>)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FileVisibilitySheet(
      title: title,
      initial: initial,
      initialIds: initialIds,
      people: _peopleSorted,
      initials: _initialsOf,
    ),
  );

  Future<void> _changeVisibility(EventFile file) async {
    final choice = await _chooseVisibility(
      title: 'Vem ska se ${file.name}?',
      initial: file.visibility,
      initialIds: file.viewerIds,
    );
    if (choice == null || !mounted) return;
    await _write(
      () => _services.setFileVisibility(
        fileId: file.id,
        visibility: choice.$1,
        personIds: choice.$2,
        expectedRevision: file.revision,
      ),
    );
  }

  Future<void> _deleteFile(EventFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ta bort fil?'),
        content: Text('${file.name} tas bort för alla.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _write(() => _services.deleteFile(file.id));
  }

  Future<void> _openFile(EventFile file) async {
    try {
      final url = await _services.signedFileUrl(file.id);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _snack('Filen kunde inte öppnas.');
    }
  }
}

String _initialsOf(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part.characters.first)
    .join()
    .toUpperCase();

/// Adds focus/material/agenda entries. Stays open so several entries can be
/// added in a row; "Tidigare använda" come from this team's earlier events.
class _AddLabelsSheet extends StatefulWidget {
  const _AddLabelsSheet({
    required this.title,
    required this.customHint,
    required this.existing,
    required this.suggestions,
    required this.onAdd,
  });
  final String title, customHint;
  final Set<String> existing;
  final Future<List<String>> suggestions;
  final Future<bool> Function(String label) onAdd;

  @override
  State<_AddLabelsSheet> createState() => _AddLabelsSheetState();
}

class _AddLabelsSheetState extends State<_AddLabelsSheet> {
  final _controller = TextEditingController();
  late final Set<String> _added = {...widget.existing};
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(String raw) async {
    final label = raw.trim();
    if (label.isEmpty || _saving) return;
    if (_added.contains(label.toLowerCase())) {
      _controller.clear();
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onAdd(label);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _added.add(label.toLowerCase());
        _controller.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Klar'),
                ),
              ],
            ),
            FutureBuilder<List<String>>(
              future: widget.suggestions,
              builder: (context, snapshot) {
                final options = (snapshot.data ?? const <String>[])
                    .where((label) => !_added.contains(label.toLowerCase()))
                    .toList();
                if (options.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tidigare använda',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final label in options)
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 16),
                              label: Text(label),
                              visualDensity: VisualDensity.compact,
                              onPressed: _saving ? null : () => _add(label),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: _add,
              decoration: InputDecoration(
                hintText: widget.customHint,
                isDense: true,
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: 'Lägg till',
                  onPressed: _saving ? null : () => _add(_controller.text),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_circle_outline),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet({
    required this.title,
    required this.initial,
    required this.conflictNotice,
  });
  final String title, initial;
  final bool conflictNotice;

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            if (widget.conflictNotice)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Din text finns kvar. Den sparade versionen har ändrats.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 5,
              maxLines: 12,
              maxLength: 10000,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _controller.text),
                  child: const Text('Spara'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _TaskEdit {
  const _TaskEdit({required this.label, this.assigneeId, this.delete = false});
  final String label;
  final String? assigneeId;
  final bool delete;
}

class _TaskEditorSheet extends StatefulWidget {
  const _TaskEditorSheet({
    required this.item,
    required this.people,
    required this.initials,
  });
  final PreparationItem? item;
  final List<EventRosterPerson> people;
  final String Function(String) initials;

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late final _controller = TextEditingController(text: widget.item?.label);
  late String? _assigneeId = widget.item?.assigneePersonId;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final label = _controller.text.trim();
    if (label.isEmpty) return;
    Navigator.pop(context, _TaskEdit(label: label, assigneeId: _assigneeId));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = _query.toLowerCase();
    final matches = widget.people
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList();
    Widget option(String? id, String name, String? role) =>
        RadioListTile<String>(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          // '' stands for "Ingen ansvarig" inside the radio group.
          value: id ?? '',
          controlAffinity: ListTileControlAffinity.trailing,
          secondary: id == null
              ? CircleAvatar(
                  radius: 14,
                  backgroundColor: colors.surfaceContainerHighest,
                  child: const Icon(Icons.person_off_outlined, size: 16),
                )
              : CircleAvatar(
                  radius: 14,
                  backgroundColor: colors.primary.withValues(alpha: .14),
                  child: Text(
                    widget.initials(name),
                    style: TextStyle(fontSize: 11, color: colors.primary),
                  ),
                ),
          title: Text(name, style: const TextStyle(fontSize: 14)),
          subtitle: role == null ? null : Text(role),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.item == null ? 'Ny uppgift' : 'Redigera uppgift',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  autofocus: widget.item == null,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Uppgift',
                    isDense: true,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                Text('Ansvarig', style: Theme.of(context).textTheme.labelLarge),
                if (widget.people.length > 8)
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Sök person',
                      isDense: true,
                    ),
                  ),
                Flexible(
                  child: RadioGroup<String>(
                    groupValue: _assigneeId ?? '',
                    onChanged: (value) => setState(
                      () => _assigneeId = value == null || value.isEmpty
                          ? null
                          : value,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        option(null, 'Ingen ansvarig', null),
                        for (final person in matches)
                          option(
                            person.personId,
                            person.name,
                            person.rolePackage == 'leader' ||
                                    person.rolePackage == 'club_functionary'
                                ? 'Ledare'
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  children: [
                    if (widget.item != null)
                      TextButton.icon(
                        onPressed: () => Navigator.pop(
                          context,
                          const _TaskEdit(label: '', delete: true),
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Ta bort'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Avbryt'),
                    ),
                    FilledButton(onPressed: _save, child: const Text('Spara')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileVisibilitySheet extends StatefulWidget {
  const _FileVisibilitySheet({
    required this.title,
    required this.initial,
    required this.initialIds,
    required this.people,
    required this.initials,
  });
  final String title, initial;
  final List<String> initialIds;
  final List<EventRosterPerson> people;
  final String Function(String) initials;

  @override
  State<_FileVisibilitySheet> createState() => _FileVisibilitySheetState();
}

class _FileVisibilitySheetState extends State<_FileVisibilitySheet> {
  late String _visibility = widget.initial;
  late final Set<String> _selected = {...widget.initialIds};

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSave =
        _visibility != FileVisibility.selected || _selected.isNotEmpty;
    Widget option(String value, IconData icon, String title, String subtitle) =>
        RadioListTile<String>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: value,
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: RadioGroup<String>(
            groupValue: _visibility,
            onChanged: (value) =>
                setState(() => _visibility = value ?? _visibility),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                option(
                  FileVisibility.participants,
                  Icons.groups_outlined,
                  'Alla deltagare',
                  'Alla som kan se eventet',
                ),
                option(
                  FileVisibility.leaders,
                  Icons.lock_outline,
                  'Endast ledare',
                  'Ledare för eventets lag',
                ),
                option(
                  FileVisibility.selected,
                  Icons.person_outline,
                  'Valda personer',
                  _selected.isEmpty
                      ? 'Välj vilka som får se filen'
                      : '${_selected.length} valda · ledare ser alltid filen',
                ),
                if (_visibility == FileVisibility.selected)
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final person in widget.people)
                          CheckboxListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.only(left: 8),
                            value: _selected.contains(person.personId),
                            onChanged: (checked) => setState(
                              () => checked == true
                                  ? _selected.add(person.personId)
                                  : _selected.remove(person.personId),
                            ),
                            secondary: CircleAvatar(
                              radius: 14,
                              backgroundColor: colors.primary.withValues(
                                alpha: .14,
                              ),
                              child: Text(
                                widget.initials(person.name),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                            title: Text(person.name),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Avbryt'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: canSave
                          ? () => Navigator.pop(context, (
                              _visibility,
                              _visibility == FileVisibility.selected
                                  ? _selected.toList()
                                  : <String>[],
                            ))
                          : null,
                      child: const Text('Spara'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
