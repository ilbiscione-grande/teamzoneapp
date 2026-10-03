part of '../../app/teamzone_app.dart';

const _assistantHoldingMessage =
    'Fler typer av förslag förbereds. Kallelser och närvarouppgifter '
    'visas redan från lagets översikt.';
const _assistantTransparencyPoints = <String>[
  'Visar alltid vilken källa och tidpunkt ett förslag bygger på.',
  'Öppnar rätt TeamZone-vy; ändringar kräver att du själv bekräftar dem.',
  'Använder inga dolda riskpoäng, medicinska slutsatser eller personjämförelser.',
  'Avfärdade förslag kan visas och återställas utan att Inbox-historik ändras.',
];

class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar({required this.avatarKey, required this.size});

  final String? avatarKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = assistantAvatarAsset(avatarKey);
    return CircleAvatar(
      key: const Key('assistant-avatar'),
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: asset == null ? null : AssetImage(asset),
      child: asset == null
          ? Icon(Icons.assistant_outlined, size: size * 0.55)
          : null,
    );
  }
}

class _AssistantCoachMobileFab extends StatelessWidget {
  const _AssistantCoachMobileFab({
    required this.onPressed,
    required this.preference,
  });

  final VoidCallback onPressed;
  final Future<AssistantIdentityPreference> preference;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Öppna Min assistent',
    child: FloatingActionButton(
      key: const Key('assistant-coach-mobile-fab'),
      tooltip: assistantBaseName,
      onPressed: onPressed,
      child: FutureBuilder<AssistantIdentityPreference>(
        future: preference,
        builder: (context, snapshot) =>
            _AssistantAvatar(avatarKey: snapshot.data?.avatarKey, size: 48),
      ),
    ),
  );
}

class _AssistantCoachSidePanel extends StatelessWidget {
  const _AssistantCoachSidePanel({
    required this.contextValue,
    required this.onOpen,
    required this.tasks,
    required this.onSettings,
    required this.preference,
    required this.onRefresh,
  });

  final TeamZoneContext contextValue;
  final VoidCallback onOpen;
  final Widget tasks;
  final VoidCallback onSettings;
  final Future<AssistantIdentityPreference> preference;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('assistant-coach-side-panel'),
    width: (MediaQuery.sizeOf(context).width * 0.25).clamp(360.0, 480.0),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<AssistantIdentityPreference>(
                future: preference,
                builder: (context, snapshot) => Row(
                  children: [
                    _AssistantAvatar(
                      avatarKey: snapshot.data?.avatarKey,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        snapshot.data?.displayName ?? assistantBaseName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      key: const Key('assistant-panel-refresh'),
                      tooltip: 'Uppdatera uppgifter',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      key: const Key('assistant-panel-settings'),
                      tooltip: 'Assistentinställningar',
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              tasks,
              const SizedBox(height: 8),
              Text(
                '${contextValue.teamName ?? contextValue.clubName} • '
                '${AssistantPresentationContext.fromTeamZoneContext(contextValue).roleLabel}',
                key: const Key('assistant-side-panel-context'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('assistant-coach-panel-open'),
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Öppna mina uppgifter'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AssistantCoachHoldingSurface extends StatefulWidget {
  const _AssistantCoachHoldingSurface({
    required this.assistantIdentity,
    required this.assistantPresentation,
    required this.overview,
    required this.contextValue,
    required this.onNavigate,
    required this.contexts,
    required this.page,
    required this.calendar,
    required this.onOpenTask,
    required this.onOpenSettings,
    this.settingsOnly = false,
  });

  final AssistantIdentityServices assistantIdentity;
  final AssistantPresentationServices assistantPresentation;
  final OverviewServices overview;
  final TeamZoneContext contextValue;
  final ValueChanged<String> onNavigate;
  final List<TeamZoneContext> contexts;
  final AssistantPageContext page;
  final CalendarServices calendar;
  final Future<void> Function(AssistantTask) onOpenTask;
  final Future<void> Function() onOpenSettings;
  final bool settingsOnly;

  @override
  State<_AssistantCoachHoldingSurface> createState() =>
      _AssistantCoachHoldingSurfaceState();
}

class _AssistantCoachHoldingSurfaceState
    extends State<_AssistantCoachHoldingSurface> {
  late Future<AssistantIdentityPreference> _preference;
  late Future<List<AssistantAreaPreference>> _areaPreferences;
  late Set<String> _selectedAreaKeys;
  bool _showHistory = false;
  bool _savingAvatar = false;
  int _taskRevision = 0;

  Future<void> _openSettings() async {
    await widget.onOpenSettings();
    if (!mounted) return;
    setState(() {
      _taskRevision++;
      _preference = widget.assistantIdentity.getPreference();
      _areaPreferences = widget.assistantPresentation.getAreaPreferences();
    });
  }

  @override
  void initState() {
    super.initState();
    _preference = widget.assistantIdentity.getPreference();
    _areaPreferences = widget.assistantPresentation.getAreaPreferences();
    _selectedAreaKeys = relevantAssistantAreas(
      widget.contextValue,
    ).map((area) => area.key).toSet();
  }

  Future<void> _editAreaPreferences(
    List<AssistantSpecialistArea> areas,
    List<AssistantAreaPreference> preferences,
  ) async {
    final changed = await showDialog<List<AssistantAreaPreference>>(
      context: context,
      builder: (_) => _AssistantAreaPreferencesDialog(
        areas: areas,
        preferences: preferences,
      ),
    );
    if (changed == null || !mounted) return;
    try {
      final saved = <AssistantAreaPreference>[];
      for (final preference in changed) {
        saved.add(
          await widget.assistantPresentation.saveAreaPreference(
            areaKey: preference.areaKey,
            visible: preference.visible,
            deliveryMode: preference.deliveryMode,
            expectedRevision: preference.revision,
            idempotencyKey: _newUuid(),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _areaPreferences = Future.value(saved));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Områdesinställningarna har sparats.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inställningarna kunde inte sparas. Försök igen.'),
        ),
      );
    }
  }

  Future<void> _editName(AssistantIdentityPreference preference) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _AssistantNameDialog(initialName: preference.customName),
    );
    if (result == null || !mounted) return;
    try {
      final saved = await widget.assistantIdentity.savePreference(
        customName: result.isEmpty ? null : result,
        expectedRevision: preference.revision,
        idempotencyKey: _newUuid(),
      );
      if (!mounted) return;
      setState(() {
        _preference = Future.value(saved);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assistentens namn har sparats.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Namnet kunde inte sparas. Försök igen.')),
      );
    }
  }

  Future<void> _setAvatar(
    AssistantIdentityPreference preference,
    String? avatarKey,
  ) async {
    if (_savingAvatar || preference.avatarKey == avatarKey) return;
    setState(() => _savingAvatar = true);
    try {
      final saved = await widget.assistantIdentity.saveAvatarPreference(
        avatarKey: avatarKey,
        expectedRevision: preference.revision,
        idempotencyKey: _newUuid(),
      );
      if (!mounted) return;
      setState(() => _preference = Future.value(saved));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assistentens profilbild har sparats.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preference = widget.assistantIdentity.getPreference();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profilbilden kunde inte sparas. Försök igen.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Scaffold(
      key: const Key('assistant-coach-holding-surface'),
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(ProductRouteContract.home);
            }
          },
        ),
        title: FutureBuilder<AssistantIdentityPreference>(
          future: _preference,
          builder: (context, snapshot) => Row(
            children: [
              if (!widget.settingsOnly) ...[
                _AssistantAvatar(avatarKey: snapshot.data?.avatarKey, size: 36),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  widget.settingsOnly
                      ? 'Assistentinställningar'
                      : snapshot.data?.displayName ?? assistantBaseName,
                  key: const Key('assistant-display-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!widget.settingsOnly) ...[
            IconButton(
              key: const Key('assistant-refresh-button'),
              tooltip: 'Uppdatera uppgifter',
              onPressed: () => setState(() => _taskRevision++),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              key: const Key('assistant-settings-button'),
              tooltip: 'Assistentinställningar',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
      body: FutureBuilder<AssistantIdentityPreference>(
        future: _preference,
        builder: (context, snapshot) {
          final preference =
              snapshot.data ?? const AssistantIdentityPreference(revision: 0);
          final areas = relevantAssistantAreas(widget.contextValue);
          return FutureBuilder<List<AssistantAreaPreference>>(
            future: _areaPreferences,
            builder: (context, areaSnapshot) {
              final areaPreferences = areaSnapshot.data ?? const [];
              final preferencesByArea = {
                for (final item in areaPreferences) item.areaKey: item,
              };
              final visibleAreas = areas
                  .where((area) => preferencesByArea[area.key]?.visible ?? true)
                  .toList(growable: false);
              return SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!widget.settingsOnly)
                              AssistantTaskSections(
                                key: ValueKey(_taskRevision),
                                contexts: widget.contexts,
                                activeContext: widget.contextValue,
                                page: widget.page,
                                overview: widget.overview,
                                loadEvent: widget.calendar.getEventDetails,
                                preparation: widget.calendar.preparation,
                                onOpen: widget.onOpenTask,
                              ),
                            if (widget.settingsOnly)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (widget.overview
                                      is AssistantTaskPreferencesServices)
                                    AssistantTaskVisibilitySettings(
                                      services:
                                          widget.overview
                                              as AssistantTaskPreferencesServices,
                                    )
                                  else
                                    const Text(
                                      'Visningsinställningar är inte tillgängliga just nu.',
                                    ),
                                  const SizedBox(height: 24),
                                  const Divider(),
                                  Text(
                                    'Utseende och namn',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Välj profilbild för din assistent. Valet följer ditt konto mellan enheter.',
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    key: const Key('assistant-avatar-options'),
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      for (final option
                                          in const <(String?, String)>[
                                            (null, 'Standard'),
                                            ('woman', 'Kvinna 1'),
                                            ('woman_2', 'Kvinna 2'),
                                            ('woman_3', 'Kvinna 3'),
                                            ('man', 'Man 1'),
                                            ('man_2', 'Man 2'),
                                            ('man_3', 'Man 3'),
                                          ])
                                        ChoiceChip(
                                          key: ValueKey(
                                            'assistant-avatar-${option.$1 ?? 'default'}',
                                          ),
                                          avatar: _AssistantAvatar(
                                            avatarKey: option.$1,
                                            size: 40,
                                          ),
                                          label: Text(option.$2),
                                          selected:
                                              preference.avatarKey == option.$1,
                                          onSelected:
                                              _savingAvatar ||
                                                  snapshot.connectionState ==
                                                      ConnectionState.waiting
                                              ? null
                                              : (_) => _setAvatar(
                                                  preference,
                                                  option.$1,
                                                ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    key: const Key('assistant-name-settings'),
                                    onPressed:
                                        snapshot.connectionState ==
                                            ConnectionState.waiting
                                        ? null
                                        : () => _editName(preference),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Namnge min assistent'),
                                  ),
                                  const SizedBox(height: 24),
                                  const Divider(),
                                  Text(
                                    'Om assistenten',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const AssistantDigitalFunctionNotice(),
                                  const Text(
                                    _assistantHoldingMessage,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Ingen analys körs med AI och inga automatiska åtgärder utförs.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  const _AssistantTransparencyList(),
                                  const SizedBox(height: 20),
                                  const Divider(),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Min kö',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  SegmentedButton<bool>(
                                    key: const Key('assistant-history-switch'),
                                    segments: const [
                                      ButtonSegment(
                                        value: false,
                                        label: Text('Aktuellt'),
                                      ),
                                      ButtonSegment(
                                        value: true,
                                        label: Text('Historik'),
                                      ),
                                    ],
                                    selected: {_showHistory},
                                    onSelectionChanged: (value) => setState(
                                      () => _showHistory = value.single,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    key: const Key('assistant-area-filters'),
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      for (final area in visibleAreas)
                                        FilterChip(
                                          avatar: const Icon(
                                            Icons.filter_alt_outlined,
                                            size: 16,
                                          ),
                                          label: Text(area.label),
                                          selected: _selectedAreaKeys.contains(
                                            area.key,
                                          ),
                                          onSelected: (selected) => setState(
                                            () {
                                              if (selected) {
                                                _selectedAreaKeys.add(area.key);
                                              } else {
                                                _selectedAreaKeys.remove(
                                                  area.key,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.lock_outline, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _showHistory
                                              ? 'Ingen verifierad historik ännu'
                                              : 'Inga områden är aktiverade ännu',
                                        ),
                                      ),
                                      IconButton(
                                        key: const Key(
                                          'assistant-area-preferences',
                                        ),
                                        tooltip: 'Områdesinställningar',
                                        onPressed:
                                            areaSnapshot.connectionState ==
                                                ConnectionState.waiting
                                            ? null
                                            : () => _editAreaPreferences(
                                                areas,
                                                areaPreferences,
                                              ),
                                        icon: const Icon(Icons.tune_outlined),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    key: const Key(
                                      'assistant-shared-queue-contract',
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.notifications_none_outlined),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Alla områden delar en kö och notifieringsbudget '
                                            '($assistantDirectLimitPer24Hours direkta och '
                                            '$assistantDigestLimitPer24Hours sammanfattning per dygn). '
                                            'Systemmeddelanden påverkas inte.',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class _AssistantAreaPreferencesDialog extends StatefulWidget {
  const _AssistantAreaPreferencesDialog({
    required this.areas,
    required this.preferences,
  });

  final List<AssistantSpecialistArea> areas;
  final List<AssistantAreaPreference> preferences;

  @override
  State<_AssistantAreaPreferencesDialog> createState() =>
      _AssistantAreaPreferencesDialogState();
}

class _AssistantAreaPreferencesDialogState
    extends State<_AssistantAreaPreferencesDialog> {
  late final Map<String, AssistantAreaPreference> _values = {
    for (final area in widget.areas)
      area.key:
          widget.preferences
              .where((item) => item.areaKey == area.key)
              .firstOrNull ??
          AssistantAreaPreference(
            areaKey: area.key,
            visible: true,
            deliveryMode: AssistantDeliveryMode.off,
            revision: 0,
          ),
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Områdesinställningar'),
    content: SizedBox(
      width: 520,
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'Inställningarna styr presentation och önskat leveransläge. '
            'De kan aldrig aktivera ett blockerat område.',
          ),
          const SizedBox(height: 12),
          for (final area in widget.areas)
            _AssistantAreaPreferenceRow(
              area: area,
              value: _values[area.key]!,
              onChanged: (value) => setState(() => _values[area.key] = value),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Avbryt'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(
          context,
        ).pop<List<AssistantAreaPreference>>(_values.values.toList()),
        child: const Text('Spara'),
      ),
    ],
  );
}

class _AssistantAreaPreferenceRow extends StatelessWidget {
  const _AssistantAreaPreferenceRow({
    required this.area,
    required this.value,
    required this.onChanged,
  });

  final AssistantSpecialistArea area;
  final AssistantAreaPreference value;
  final ValueChanged<AssistantAreaPreference> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: AssistantAreaBadge(area: area),
        subtitle: const Text('Visa i filter och historik'),
        value: value.visible,
        onChanged: (visible) => onChanged(
          AssistantAreaPreference(
            areaKey: value.areaKey,
            visible: visible,
            deliveryMode: value.deliveryMode,
            revision: value.revision,
          ),
        ),
      ),
      DropdownButtonFormField<AssistantDeliveryMode>(
        initialValue: value.deliveryMode,
        decoration: const InputDecoration(labelText: 'Önskat leveransläge'),
        items: const [
          DropdownMenuItem(
            value: AssistantDeliveryMode.direct,
            child: Text('Direkt'),
          ),
          DropdownMenuItem(
            value: AssistantDeliveryMode.digest,
            child: Text('Sammanfattning'),
          ),
          DropdownMenuItem(
            value: AssistantDeliveryMode.inAssistant,
            child: Text('Endast i Min assistent'),
          ),
          DropdownMenuItem(value: AssistantDeliveryMode.off, child: Text('Av')),
        ],
        onChanged: (mode) {
          if (mode == null) return;
          onChanged(
            AssistantAreaPreference(
              areaKey: value.areaKey,
              visible: value.visible,
              deliveryMode: mode,
              revision: value.revision,
            ),
          );
        },
      ),
      const Divider(height: 24),
    ],
  );
}

class _AssistantNameDialog extends StatefulWidget {
  const _AssistantNameDialog({this.initialName});

  final String? initialName;

  @override
  State<_AssistantNameDialog> createState() => _AssistantNameDialogState();
}

class _AssistantNameDialogState extends State<_AssistantNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    final error = validateAssistantName(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop<String>(name);
  }

  @override
  Widget build(BuildContext context) {
    final warning = assistantNameNeedsIdentityWarning(_controller.text);
    return AlertDialog(
      title: const Text('Namnge min assistent'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Namnet är personligt, synkas med ditt konto och visas bara för dig.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('assistant-name-field'),
              controller: _controller,
              autofocus: true,
              maxLength: assistantNameMaxLength,
              decoration: InputDecoration(
                labelText: 'Personligt namn',
                hintText: assistantBaseName,
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
            if (warning)
              Text(
                'Undvik namn som kan förväxlas med TeamZone, support eller legitimerad vårdpersonal.',
                key: const Key('assistant-name-warning'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            const Text(
              'Lämna fältet tomt för att återställa till Min assistent.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Spara')),
      ],
    );
  }
}

class _AssistantTransparencyList extends StatelessWidget {
  const _AssistantTransparencyList();

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('assistant-coach-transparency-contract'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final point in _assistantTransparencyPoints)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle_outline, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(point)),
            ],
          ),
        ),
    ],
  );
}
