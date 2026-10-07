part of '../../app/teamzone_app.dart';

// KPI goals (Förberedelser) and the follow-up tab (Uppföljning). Goals are set
// before an event and followed up after it; attendance, answers and the match
// result are counted by TeamZone, other values are entered afterwards.

String _kpiValueText(String valueType, double? value) {
  if (value == null) return '–';
  String number(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  return switch (valueType) {
    'percent' => '${number(value)} %',
    'boolean' => value >= 1 ? 'Ja' : 'Nej',
    'scale' => '${number(value)}/5',
    'minutes' => '${number(value)} min',
    _ => number(value),
  };
}

String _kpiGoalText(EventKpi kpi) {
  if (kpi.valueType == 'boolean') return kpi.target >= 1 ? 'Ja' : 'Nej';
  final value = _kpiValueText(kpi.valueType, kpi.target);
  return switch (kpi.comparator) {
    'gte' => 'minst $value',
    'lte' => 'högst $value',
    _ => value,
  };
}

String _kpiSourceText(EventKpi kpi) =>
    kpi.isManual ? 'Fylls i efteråt' : 'Räknas automatiskt';

String _declineReasonLabel(String code) => switch (code) {
  'illness' => 'Sjukdom',
  'injury' => 'Skada',
  'unavailable' => 'Inte tillgänglig',
  'transport' => 'Transport',
  _ => 'Annat',
};

/// The "Mål" section at the top of Förberedelser.
class _KpiGoalsSection extends StatefulWidget {
  const _KpiGoalsSection({
    super.key,
    required this.event,
    required this.services,
    required this.allowEdit,
    this.onChanged,
  });
  final EventDetails event;
  final EventPreparationServices services;
  final bool allowEdit;
  final VoidCallback? onChanged;

  @override
  State<_KpiGoalsSection> createState() => _KpiGoalsSectionState();
}

class _KpiGoalsSectionState extends State<_KpiGoalsSection> {
  EventFollowup? _data;
  bool _failed = false;

  bool get _canEdit => widget.allowEdit && (_data?.canEditTargets ?? false);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final data = await widget.services.getFollowup(widget.event.id);
      if (mounted) {
        setState(() {
          _data = data;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _edit([EventKpi? kpi]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _KpiGoalSheet(
        event: widget.event,
        services: widget.services,
        existing: kpi,
      ),
    );
    if (saved == true) {
      await _reload();
      widget.onChanged?.call();
    }
  }

  Future<void> _delete(EventKpi kpi) async {
    try {
      await widget.services.deleteKpiTarget(widget.event.id, kpi.id);
      await _reload();
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Målet kunde inte tas bort.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_failed) return const SizedBox.shrink();
    if (data == null) return const SizedBox(height: 40);
    if (data.kpis.isEmpty && !_canEdit) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final title = switch (widget.event.type) {
      'training' => 'Mål för träningen',
      'match' => 'Mål för matchen',
      _ => 'Mål',
    };
    return DecoratedBox(
      key: const ValueKey('kpi-goals-section'),
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
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .3,
                        ),
                      ),
                    ),
                  ),
                  if (_canEdit)
                    TextButton.icon(
                      key: const ValueKey('kpi-add-goal'),
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Lägg till mål'),
                    ),
                ],
              ),
            ),
            if (data.kpis.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Sätt mål som ni följer upp efteråt, till exempel närvaro eller skott på mål.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            for (final kpi in data.kpis)
              ListTile(
                dense: true,
                title: Text(kpi.label),
                subtitle: Text(
                  '${_kpiSourceText(kpi)}${kpi.visibleToPlayers ? ' · Syns för spelarna' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _kpiGoalText(kpi),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_canEdit)
                      PopupMenuButton<String>(
                        tooltip: 'Åtgärder för målet',
                        onSelected: (value) =>
                            value == 'edit' ? _edit(kpi) : _delete(kpi),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Ändra')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Ta bort'),
                          ),
                        ],
                      ),
                  ],
                ),
                onTap: _canEdit ? () => _edit(kpi) : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// Picks a KPI and sets its goal.
class _KpiGoalSheet extends StatefulWidget {
  const _KpiGoalSheet({
    required this.event,
    required this.services,
    this.existing,
  });
  final EventDetails event;
  final EventPreparationServices services;
  final EventKpi? existing;

  @override
  State<_KpiGoalSheet> createState() => _KpiGoalSheetState();
}

class _KpiGoalSheetState extends State<_KpiGoalSheet> {
  List<KpiCatalogEntry>? _catalog;
  late String _key = widget.existing?.kpiKey ?? '';
  late final TextEditingController _label = TextEditingController(
    text: widget.existing?.kpiKey == 'custom' ? widget.existing!.label : '',
  );
  late String _customType = widget.existing?.kpiKey == 'custom'
      ? widget.existing!.valueType
      : 'count';
  late String _comparator = widget.existing?.comparator ?? 'gte';
  late final TextEditingController _target = TextEditingController(
    text: widget.existing == null
        ? ''
        : _kpiValueText(
            widget.existing!.valueType,
            widget.existing!.target,
          ).replaceAll(RegExp(r'[^0-9.,]'), ''),
  );
  late bool _boolTarget = (widget.existing?.target ?? 1) >= 1;
  late bool _visible = widget.existing?.visibleToPlayers ?? false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCatalog());
  }

  @override
  void dispose() {
    _label.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await widget.services.getKpiCatalog(widget.event.id);
      if (mounted) setState(() => _catalog = catalog);
    } catch (_) {
      if (mounted) setState(() => _catalog = const []);
    }
  }

  KpiCatalogEntry? get _entry =>
      _catalog?.where((entry) => entry.key == _key).firstOrNull;

  String get _valueType => _key == 'custom'
      ? _customType
      : (_entry?.valueType ?? widget.existing?.valueType ?? 'count');

  void _select(String key) {
    setState(() {
      _key = key;
      _error = null;
      final entry = _entry;
      if (entry != null) {
        _comparator = entry.direction == 'lower' ? 'lte' : 'gte';
      }
    });
  }

  Future<void> _save() async {
    if (_key.isEmpty) {
      setState(() => _error = 'Välj ett nyckeltal.');
      return;
    }
    if (_key == 'custom' && _label.text.trim().isEmpty) {
      setState(() => _error = 'Ge nyckeltalet ett namn.');
      return;
    }
    final type = _valueType;
    double? target;
    if (type == 'boolean') {
      target = _boolTarget ? 1 : 0;
    } else {
      target = double.tryParse(_target.text.trim().replaceAll(',', '.'));
      final invalid =
          target == null ||
          target < 0 ||
          (type == 'percent' && target > 100) ||
          (type == 'scale' && (target < 1 || target > 5));
      if (invalid) {
        setState(
          () => _error = switch (type) {
            'percent' => 'Ange ett mål mellan 0 och 100.',
            'scale' => 'Ange ett mål mellan 1 och 5.',
            _ => 'Ange ett mål som ett tal.',
          },
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.services.saveKpiTarget(
        eventId: widget.event.id,
        targetId: widget.existing?.id,
        kpiKey: _key,
        label: _key == 'custom' ? _label.text.trim() : null,
        valueType: _key == 'custom' ? _customType : null,
        comparator: type == 'boolean' ? 'eq' : _comparator,
        target: target,
        visibleToPlayers: _visible,
        expectedRevision: widget.existing?.revision ?? 0,
      );
      if (mounted) Navigator.pop(context, true);
    } on PreparationConflict {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Någon annan ändrade målet. Stäng och försök igen.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Målet kunde inte sparas. Finns det redan?';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final type = _valueType;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Nytt mål' : 'Ändra mål',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (catalog == null)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                key: const ValueKey('kpi-catalog'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in catalog)
                    ChoiceChip(
                      label: Text(entry.label),
                      selected: _key == entry.key,
                      onSelected: (_) => _select(entry.key),
                    ),
                  ChoiceChip(
                    key: const ValueKey('kpi-custom'),
                    label: const Text('Eget nyckeltal'),
                    selected: _key == 'custom',
                    onSelected: (_) => _select('custom'),
                  ),
                ],
              ),
            if (_key == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Namn'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _customType,
                decoration: const InputDecoration(labelText: 'Typ'),
                items: const [
                  DropdownMenuItem(value: 'count', child: Text('Antal')),
                  DropdownMenuItem(value: 'percent', child: Text('Procent')),
                  DropdownMenuItem(value: 'boolean', child: Text('Ja/nej')),
                  DropdownMenuItem(value: 'scale', child: Text('Skala 1–5')),
                  DropdownMenuItem(value: 'minutes', child: Text('Minuter')),
                ],
                onChanged: (value) =>
                    setState(() => _customType = value ?? 'count'),
              ),
            ],
            if (_key.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (_entry?.isAutomatic ?? false)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Räknas automatiskt av TeamZone.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              if (type == 'boolean')
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Mål: ja')),
                    ButtonSegment(value: false, label: Text('Mål: nej')),
                  ],
                  selected: {_boolTarget},
                  onSelectionChanged: (value) =>
                      setState(() => _boolTarget = value.first),
                )
              else
                Row(
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'gte', label: Text('Minst')),
                        ButtonSegment(value: 'lte', label: Text('Högst')),
                      ],
                      selected: {_comparator == 'lte' ? 'lte' : 'gte'},
                      onSelectionChanged: (value) =>
                          setState(() => _comparator = value.first),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('kpi-target'),
                        controller: _target,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Mål',
                          suffixText: switch (type) {
                            'percent' => '%',
                            'minutes' => 'min',
                            'scale' => 'av 5',
                            _ => null,
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _visible,
                onChanged: (value) => setState(() => _visible = value),
                title: const Text('Visa målet för spelarna'),
                subtitle: const Text('Blir ett gemensamt lagmål på eventet.'),
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('kpi-save-goal'),
              onPressed: _saving ? null : _save,
              child: const Text('Spara mål'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Uppföljning tab.
class _FollowupTab extends StatefulWidget {
  const _FollowupTab({
    super.key,
    required this.event,
    required this.services,
    required this.allowRecord,
    required this.onOpenParticipants,
    this.onOpenMatchMode,
  });
  final EventDetails event;
  final EventPreparationServices services;
  final bool allowRecord;
  final VoidCallback onOpenParticipants;
  final VoidCallback? onOpenMatchMode;

  @override
  State<_FollowupTab> createState() => _FollowupTabState();
}

class _FollowupTabState extends State<_FollowupTab> {
  EventFollowup? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final data = await widget.services.getFollowup(widget.event.id);
      if (mounted) {
        setState(() {
          _data = data;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && _data == null) setState(() => _failed = true);
    }
  }

  Future<void> _recordValue(EventKpi kpi) async {
    final result = await showDialog<(bool, double?)>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _KpiValueDialog(kpi: kpi),
    );
    if (result == null || !result.$1 || !mounted) return;
    try {
      await widget.services.recordKpiValue(kpi.id, result.$2, kpi.revision);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Värdet kunde inte sparas.')),
        );
      }
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (!_failed) return const Center(child: CircularProgressIndicator());
      return Center(
        child: _StateCard(
          icon: Icons.sync_problem,
          title: 'Uppföljningen kunde inte laddas',
          message: AppStrings.of(context).safeError,
          action: FilledButton(
            onPressed: () {
              setState(() => _failed = false);
              unawaited(_reload());
            },
            child: Text(AppStrings.of(context).retry),
          ),
        ),
      );
    }
    final summary = data.summary;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        key: const ValueKey('event-followup'),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          _assistantUsesFab(context) ? 96 : 24,
        ),
        children: [
          if (data.isLeader && data.ended) ...[
            _todos(context, data),
            const SizedBox(height: 16),
          ],
          _metrics(context, data),
          if (summary.registered > 0 || summary.called > 0) ...[
            const SizedBox(height: 20),
            _attendance(context, data),
          ],
          if (data.attendanceTrend.length > 1) ...[
            const SizedBox(height: 20),
            _heading(context, 'Närvaro senaste gångerna'),
            _TrendBars(
              key: const ValueKey('attendance-trend'),
              points: data.attendanceTrend,
              maxValue: 100,
            ),
          ],
          if (data.kpis.isNotEmpty || data.canEditTargets) ...[
            const SizedBox(height: 20),
            _goals(context, data),
          ],
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String text, {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleMedium),
            ),
            ?trailing,
          ],
        ),
      );

  Widget _todos(BuildContext context, EventFollowup data) {
    final colors = Theme.of(context).colorScheme;
    if (data.todos.isEmpty) {
      return Card(
        key: const ValueKey('followup-done'),
        color: colors.secondaryContainer,
        child: const ListTile(
          leading: Icon(Icons.task_alt),
          title: Text('Uppföljningen är klar'),
        ),
      );
    }
    return Card(
      key: const ValueKey('followup-todos'),
      color: colors.tertiaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            leading: Icon(Icons.checklist),
            title: Text('Att göra'),
          ),
          for (final todo in data.todos)
            ListTile(
              dense: true,
              title: Text(switch (todo.kind) {
                'attendance' => 'Registrera närvaro för ${todo.count} personer',
                'kpi_values' => 'Fyll i ${todo.count} nyckeltal',
                'match_result' => 'Rapportera matchens resultat',
                'match_report' => 'Skriv matchrapport',
                _ => todo.kind,
              }),
              trailing: switch (todo.kind) {
                'attendance' => TextButton(
                  onPressed: widget.onOpenParticipants,
                  child: const Text('Registrera'),
                ),
                'match_result' when widget.onOpenMatchMode != null =>
                  TextButton(
                    onPressed: widget.onOpenMatchMode,
                    child: const Text('Öppna matchläget'),
                  ),
                _ => null,
              },
            ),
        ],
      ),
    );
  }

  Widget _metrics(BuildContext context, EventFollowup data) {
    final summary = data.summary;
    final average = data.teamAverageAttendance;
    final rate = summary.attendanceRate;
    final delta = rate == null || average == null
        ? null
        : (rate - average).round();
    final cards = <(String, String, String?, Color?)>[
      (
        'Närvaro',
        _kpiValueText('percent', rate),
        delta == null ? null : '${delta >= 0 ? '+' : ''}$delta mot snitt',
        delta == null
            ? null
            : delta >= 0
            ? Colors.green.shade700
            : Theme.of(context).colorScheme.error,
      ),
      if (summary.called > 0)
        (
          'Svar',
          '${summary.accepted + summary.declined}/${summary.called}',
          summary.pending > 0
              ? '${summary.pending} utan svar'
              : 'Alla har svarat',
          null,
        ),
      if (summary.called > 0 || summary.late > 0)
        (
          'Sena',
          '${summary.late}',
          summary.lateMinutesAverage == null
              ? null
              : 'snitt ${summary.lateMinutesAverage!.round()} min',
          null,
        ),
    ];
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('followup-metrics'),
      children: [
        for (final card in cards)
          Expanded(
            child: Card(
              color: colors.surfaceContainerHighest,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.$1,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      card.$2,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (card.$3 != null)
                      Text(
                        card.$3!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: card.$4),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _attendance(BuildContext context, EventFollowup data) {
    final summary = data.summary;
    final colors = Theme.of(context).colorScheme;
    final parts = <(int, Color, String)>[
      (summary.present, Colors.green.shade600, 'närvarande'),
      (summary.late, Colors.orange.shade600, 'sena'),
      (summary.partial, Colors.amber.shade400, 'delvis'),
      (summary.absent, colors.error, 'frånvarande'),
      (summary.unregistered, colors.outlineVariant, 'ej registrerade'),
    ].where((part) => part.$1 > 0).toList();
    final total = parts.fold<int>(0, (sum, part) => sum + part.$1);
    final reasons = data.declineReasons.entries
        .map(
          (entry) =>
              '${_declineReasonLabel(entry.key).toLowerCase()} ${entry.value}',
        )
        .join(', ');
    return Column(
      key: const ValueKey('followup-attendance'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          'Närvaro',
          trailing: TextButton(
            onPressed: widget.onOpenParticipants,
            child: const Text('Visa deltagare'),
          ),
        ),
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final part in parts)
                    Expanded(
                      flex: part.$1,
                      child: ColoredBox(color: part.$2),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          parts.map((part) => '${part.$1} ${part.$3}').join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (reasons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Avböjt: $reasons',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _goals(BuildContext context, EventFollowup data) {
    final achieved = data.kpis.where((kpi) => kpi.status == 'achieved').length;
    final decided = data.kpis
        .where((kpi) => kpi.status == 'achieved' || kpi.status == 'missed')
        .length;
    return Column(
      key: const ValueKey('followup-goals'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          'Mål mot utfall',
          trailing: decided == 0
              ? null
              : Text(
                  '$achieved av ${data.kpis.length} uppnådda',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
        ),
        if (data.kpis.isEmpty)
          const Text(
            'Inga mål är satta. Lägg till mål under Förberedelser.',
            style: TextStyle(fontSize: 13),
          ),
        for (final kpi in data.kpis) _goalRow(context, data, kpi),
      ],
    );
  }

  Widget _goalRow(BuildContext context, EventFollowup data, EventKpi kpi) {
    final colors = Theme.of(context).colorScheme;
    final canRecord =
        kpi.isManual && widget.allowRecord && data.canRecordValues;
    final (icon, color, label) = switch (kpi.status) {
      'achieved' => (Icons.check_circle, Colors.green.shade700, 'Uppnått'),
      'missed' => (Icons.cancel, colors.error, 'Inte uppnått'),
      'missing' => (Icons.edit_note, colors.tertiary, 'Saknar värde'),
      _ => (Icons.schedule, colors.outline, 'Inte klart än'),
    };
    return Card(
      key: ValueKey('followup-kpi-${kpi.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: canRecord ? () => _recordValue(kpi) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kpi.label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          'Mål: ${_kpiGoalText(kpi)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _kpiValueText(kpi.valueType, kpi.actual),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: label,
                    child: Icon(icon, color: color, semanticLabel: label),
                  ),
                ],
              ),
              if (canRecord)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _recordValue(kpi),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(
                      kpi.actual == null ? 'Fyll i värde' : 'Ändra värde',
                    ),
                  ),
                ),
              if (kpi.trend.length > 1 && kpi.valueType != 'boolean')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _TrendBars(
                    points: kpi.trend,
                    maxValue: kpi.valueType == 'percent'
                        ? 100
                        : kpi.valueType == 'scale'
                        ? 5
                        : null,
                    goal: kpi.target,
                    height: 36,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small bar chart of recent values; the current event is highlighted and
/// an optional goal is drawn as a line.
class _TrendBars extends StatelessWidget {
  const _TrendBars({
    super.key,
    required this.points,
    this.maxValue,
    this.goal,
    this.height = 48,
  });
  final List<KpiTrendPoint> points;
  final double? maxValue, goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = points.map((point) => point.actual ?? 0).toList();
    final top =
        maxValue ??
        [...values, goal ?? 0].fold<double>(1, (a, b) => b > a ? b : a);
    final localizations = MaterialLocalizations.of(context);
    return Semantics(
      label:
          'Trend: ${points.map((point) => point.actual == null ? 'saknas' : point.actual!.round().toString()).join(', ')}',
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Tooltip(
                        message:
                            '${localizations.formatShortDate(point.startsAt.toLocal())}: ${point.actual == null ? '–' : point.actual!.round()}',
                        child: FractionallySizedBox(
                          heightFactor: point.actual == null
                              ? 0.04
                              : (point.actual! / top).clamp(0.04, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: point.current
                                  ? colors.primary
                                  : colors.primaryContainer,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (goal != null && top > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: height * (goal! / top).clamp(0.0, 1.0),
                child: Container(height: 1, color: colors.outline),
              ),
          ],
        ),
      ),
    );
  }
}

/// Enters the value of a manual KPI; returns (save, value) where a null
/// value clears it.
class _KpiValueDialog extends StatefulWidget {
  const _KpiValueDialog({required this.kpi});
  final EventKpi kpi;

  @override
  State<_KpiValueDialog> createState() => _KpiValueDialogState();
}

class _KpiValueDialogState extends State<_KpiValueDialog> {
  late final TextEditingController _value = TextEditingController(
    text: widget.kpi.actual == null || widget.kpi.valueType == 'boolean'
        ? ''
        : _kpiValueText(
            widget.kpi.valueType,
            widget.kpi.actual,
          ).replaceAll(RegExp(r'[^0-9.,]'), ''),
  );
  late bool? _bool = widget.kpi.actual == null ? null : widget.kpi.actual! >= 1;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final type = widget.kpi.valueType;
    if (type == 'boolean') {
      Navigator.pop(context, (
        true,
        _bool == null ? null : (_bool! ? 1.0 : 0.0),
      ));
      return;
    }
    final text = _value.text.trim().replaceAll(',', '.');
    if (text.isEmpty) {
      Navigator.pop(context, (true, null));
      return;
    }
    final value = double.tryParse(text);
    if (value == null ||
        value < 0 ||
        (type == 'percent' && value > 100) ||
        (type == 'scale' && (value < 1 || value > 5))) {
      setState(() => _error = 'Ange ett giltigt värde.');
      return;
    }
    Navigator.pop(context, (true, value));
  }

  @override
  Widget build(BuildContext context) {
    final kpi = widget.kpi;
    return AlertDialog(
      title: Text(kpi.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mål: ${_kpiGoalText(kpi)}'),
          const SizedBox(height: 12),
          if (kpi.valueType == 'boolean')
            SegmentedButton<bool>(
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(value: true, label: Text('Ja')),
                ButtonSegment(value: false, label: Text('Nej')),
              ],
              selected: {?_bool},
              onSelectionChanged: (value) =>
                  setState(() => _bool = value.firstOrNull),
            )
          else
            TextField(
              key: const ValueKey('kpi-value'),
              controller: _value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Utfall',
                errorText: _error,
                suffixText: switch (kpi.valueType) {
                  'percent' => '%',
                  'minutes' => 'min',
                  'scale' => 'av 5',
                  _ => null,
                },
              ),
              onSubmitted: (_) => _save(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          key: const ValueKey('kpi-save-value'),
          onPressed: _save,
          child: const Text('Spara'),
        ),
      ],
    );
  }
}
