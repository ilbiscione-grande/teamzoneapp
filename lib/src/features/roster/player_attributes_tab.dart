part of '../../app/teamzone_app.dart';

String _attrText(BuildContext context, String swedish, String english) =>
    AppStrings.of(context).isSwedish ? swedish : english;

/// The Egenskaper tab on a player's profile, for the team's leaders: each
/// attribute can be ticked as a strength or an area to develop. A tick is
/// saved at once; the players and guardians never see this.
class _PlayerAttributesView extends StatefulWidget {
  const _PlayerAttributesView({
    super.key,
    required this.clubId,
    required this.teamId,
    required this.personId,
    this.header,
  });
  final String clubId, teamId, personId;
  final Widget? header;

  @override
  State<_PlayerAttributesView> createState() => _PlayerAttributesViewState();
}

class _PlayerAttributesViewState extends State<_PlayerAttributesView> {
  PlayerAttributesServices get _services => PlayerAttributesFeature.services;
  TeamPlayerAttributes? _data;
  PlayerAttributeEntry? _entry;
  Object? _error;
  // Saves run one after another; only the last answer replaces the ticks.
  Future<void> _queue = Future.value();
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      _apply(await _services.get(clubId: widget.clubId, teamId: widget.teamId));
    } catch (error) {
      AppErrors.caught('player_attributes.load', error);
      if (mounted) setState(() => _error = error);
    }
  }

  void _apply(TeamPlayerAttributes data) {
    if (!mounted) return;
    setState(() {
      _data = data;
      _entry =
          data.player(widget.personId) ??
          PlayerAttributeEntry(personId: widget.personId, name: '');
    });
  }

  void _tick(String key, AttributeAssessment? assessment) {
    final entry = _entry!.withAssessment(key, assessment);
    setState(() {
      _entry = entry;
      _pending++;
    });
    _queue = _queue.then((_) async {
      try {
        final data = await _services.set(
          clubId: widget.clubId,
          teamId: widget.teamId,
          personId: widget.personId,
          strengths: entry.strengths,
          development: entry.development,
        );
        if (_pending == 1) _apply(data);
      } catch (error) {
        AppErrors.caught('player_attributes.set', error);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _attrText(
                context,
                'Egenskapen kunde inte sparas.',
                'The attribute could not be saved.',
              ),
            ),
          ),
        );
        if (_pending == 1) unawaited(_load());
      } finally {
        if (mounted) setState(() => _pending--);
      }
    });
  }

  Future<void> _editCustom([PlayerAttributeOption? option]) async {
    final controller = TextEditingController(text: option?.customLabel ?? '');
    final label = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(
          option == null
              ? _attrText(context, 'Ny egen egenskap', 'New attribute')
              : _attrText(context, 'Byt namn', 'Rename'),
        ),
        content: TextField(
          key: const ValueKey('custom-attribute-label'),
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            hintText: _attrText(
              context,
              't.ex. Långa inkast',
              'e.g. Long throw-ins',
            ),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_attrText(context, 'Avbryt', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(_attrText(context, 'Spara', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.trim().isEmpty || !mounted) return;
    await _change(
      () => _services.saveCustom(
        clubId: widget.clubId,
        teamId: widget.teamId,
        attributeId: option?.key,
        label: label.trim(),
      ),
      (error) => '$error'.contains('attribute_label_taken')
          ? _attrText(
              context,
              'Laget har redan en egenskap med det namnet.',
              'The team already has an attribute with that name.',
            )
          : '$error'.contains('too_many_attributes')
          ? _attrText(
              context,
              'Laget kan ha högst 15 egna egenskaper.',
              'A team can have at most 15 attributes of its own.',
            )
          : _attrText(
              context,
              'Egenskapen kunde inte sparas.',
              'The attribute could not be saved.',
            ),
    );
  }

  Future<void> _deleteCustom(PlayerAttributeOption option) async {
    final sure = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(
          _attrText(
            context,
            'Ta bort ${option.customLabel}?',
            'Remove ${option.customLabel}?',
          ),
        ),
        content: Text(
          _attrText(
            context,
            'Egenskapen tas bort för hela laget, och bockarna på den försvinner för alla spelare.',
            'The attribute is removed for the whole team, along with every tick on it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_attrText(context, 'Avbryt', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_attrText(context, 'Ta bort', 'Remove')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _change(
      () => _services.deleteCustom(
        clubId: widget.clubId,
        teamId: widget.teamId,
        attributeId: option.key,
      ),
      (_) => _attrText(
        context,
        'Egenskapen kunde inte tas bort.',
        'The attribute could not be removed.',
      ),
    );
  }

  Future<void> _change(
    Future<TeamPlayerAttributes> Function() action,
    String Function(Object error) message,
  ) async {
    await _queue;
    try {
      _apply(await action());
    } catch (error) {
      AppErrors.caught('player_attributes.custom', error);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data, entry = _entry;
    final swedish = AppStrings.of(context).isSwedish;
    return ListView(
      key: const ValueKey('player-attributes'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (widget.header != null) ...[
          widget.header!,
          const SizedBox(height: 12),
        ],
        if (_error != null && data == null)
          _AttributeNotice(
            icon: Icons.error_outline,
            text: _attrText(
              context,
              'Egenskaperna kunde inte hämtas.',
              'The attributes could not be loaded.',
            ),
            action: TextButton(
              onPressed: _load,
              child: Text(_attrText(context, 'Försök igen', 'Try again')),
            ),
          )
        else if (data == null || entry == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _AttributeSummary(data: data, entry: entry, swedish: swedish),
          const SizedBox(height: 8),
          _AttributeNotice(
            icon: Icons.lock_outline,
            text: _attrText(
              context,
              'Bara lagets ledare ser egenskaperna. Bocka för det spelaren är bra på och det spelaren ska utveckla.',
              'Only the team\'s leaders see the attributes. Tick what the player is good at and what to develop.',
            ),
          ),
          for (final area in playerAttributeAreas.entries)
            if (data.options.any((o) => o.area == area.key))
              _AttributeArea(
                title: swedish ? area.value.$1 : area.value.$2,
                options: data.options.where((o) => o.area == area.key),
                entry: entry,
                swedish: swedish,
                onTick: _tick,
              ),
          _AttributeArea(
            title: _attrText(context, 'Lagets egna', 'The team\'s own'),
            options: data.customOptions,
            entry: entry,
            swedish: swedish,
            onTick: _tick,
            onEdit: _editCustom,
            onDelete: _deleteCustom,
            footer: data.customOptions.length < 15
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('add-custom-attribute'),
                      onPressed: () => _editCustom(),
                      icon: const Icon(Icons.add),
                      label: Text(
                        _attrText(
                          context,
                          'Lägg till egen egenskap',
                          'Add an attribute',
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ],
    );
  }
}

/// What is ticked, at the top: the strengths and the areas to develop.
class _AttributeSummary extends StatelessWidget {
  const _AttributeSummary({
    required this.data,
    required this.entry,
    required this.swedish,
  });
  final TeamPlayerAttributes data;
  final PlayerAttributeEntry entry;
  final bool swedish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    Widget group(
      String title,
      List<String> keys,
      IconData icon,
      Color color,
      String empty,
    ) {
      final options = [for (final k in keys) ?data.option(k)];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (options.isEmpty)
            Text(
              empty,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in options)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      playerAttributeLabel(option, swedish),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      );
    }

    final strengths = group(
      swedish ? 'Styrkor' : 'Strengths',
      entry.strengths,
      Icons.star_rounded,
      palette.accent,
      swedish ? 'Inga ibockade ännu' : 'None ticked yet',
    );
    final development = group(
      swedish ? 'Utvecklingsområden' : 'Areas to develop',
      entry.development,
      Icons.trending_up_rounded,
      palette.warning,
      swedish ? 'Inga ibockade ännu' : 'None ticked yet',
    );
    return Card(
      key: const ValueKey('player-attributes-summary'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 560
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: strengths),
                    const SizedBox(width: 16),
                    Expanded(child: development),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    strengths,
                    const SizedBox(height: 14),
                    development,
                  ],
                ),
        ),
      ),
    );
  }
}

class _AttributeNotice extends StatelessWidget {
  const _AttributeNotice({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// One area's attributes, each with the two ticks.
class _AttributeArea extends StatelessWidget {
  const _AttributeArea({
    required this.title,
    required this.options,
    required this.entry,
    required this.swedish,
    required this.onTick,
    this.onEdit,
    this.onDelete,
    this.footer,
  });
  final String title;
  final Iterable<PlayerAttributeOption> options;
  final PlayerAttributeEntry entry;
  final bool swedish;
  final void Function(String key, AttributeAssessment? assessment) onTick;
  final void Function(PlayerAttributeOption option)? onEdit, onDelete;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (index, option) in options.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  _AttributeRow(
                    option: option,
                    assessment: entry.assessmentOf(option.key),
                    swedish: swedish,
                    onTick: onTick,
                    onEdit: onEdit,
                    onDelete: onDelete,
                  ),
                ],
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: footer,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttributeRow extends StatelessWidget {
  const _AttributeRow({
    required this.option,
    required this.assessment,
    required this.swedish,
    required this.onTick,
    this.onEdit,
    this.onDelete,
  });
  final PlayerAttributeOption option;
  final AttributeAssessment? assessment;
  final bool swedish;
  final void Function(String key, AttributeAssessment? assessment) onTick;
  final void Function(PlayerAttributeOption option)? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Widget tick(AttributeAssessment value, String label, Color color) {
      final selected = assessment == value;
      return FilterChip(
        key: ValueKey('attribute-${option.key}-${value.name}'),
        label: Text(label),
        selected: selected,
        // No checkmark, so the chips keep their width when ticked.
        showCheckmark: false,
        selectedColor: color.withValues(alpha: .2),
        labelStyle: selected ? TextStyle(color: color) : null,
        side: BorderSide(
          color: selected ? color : palette.muted.withValues(alpha: .4),
        ),
        visualDensity: VisualDensity.compact,
        onSelected: (on) => onTick(option.key, on ? value : null),
      );
    }

    final label = Text(
      playerAttributeLabel(option, swedish),
      style: Theme.of(context).textTheme.bodyMedium,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            // The team's own attributes are renamed or removed from the name.
            child: option.custom && onEdit != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<bool>(
                      key: ValueKey('custom-attribute-menu-${option.key}'),
                      tooltip: swedish
                          ? 'Byt namn eller ta bort'
                          : 'Rename or remove',
                      onSelected: (rename) =>
                          rename ? onEdit!(option) : onDelete?.call(option),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: true,
                          child: Text(swedish ? 'Byt namn' : 'Rename'),
                        ),
                        PopupMenuItem(
                          value: false,
                          child: Text(swedish ? 'Ta bort' : 'Remove'),
                        ),
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: label),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: palette.muted,
                          ),
                        ],
                      ),
                    ),
                  )
                : label,
          ),
          Wrap(
            spacing: 6,
            children: [
              tick(
                AttributeAssessment.strength,
                swedish ? 'Styrka' : 'Strength',
                palette.accent,
              ),
              tick(
                AttributeAssessment.development,
                swedish ? 'Utveckla' : 'Develop',
                palette.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
