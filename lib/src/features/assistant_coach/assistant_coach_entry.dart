part of '../../app/teamzone_app.dart';

const _assistantHoldingMessage =
    'Min assistent förbereds. Förslag visas först när lagets data och '
    'behörigheter har verifierats.';
const _assistantTransparencyPoints = <String>[
  'Visar alltid vilken källa och tidpunkt ett förslag bygger på.',
  'Öppnar rätt TeamZone-vy; ändringar kräver att du själv bekräftar dem.',
  'Använder inga dolda riskpoäng, medicinska slutsatser eller personjämförelser.',
  'Avfärdade förslag kan visas och återställas utan att Inbox-historik ändras.',
];

class _AssistantCoachMobileFab extends StatelessWidget {
  const _AssistantCoachMobileFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Öppna Min assistent',
    child: FloatingActionButton(
      key: const Key('assistant-coach-mobile-fab'),
      tooltip: assistantBaseName,
      onPressed: onPressed,
      child: const Icon(Icons.assistant_outlined),
    ),
  );
}

class _AssistantCoachSidePanel extends StatelessWidget {
  const _AssistantCoachSidePanel({
    required this.contextValue,
    required this.onOpen,
  });

  final TeamZoneContext contextValue;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('assistant-coach-side-panel'),
    width: 288,
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
              Row(
                children: [
                  const Icon(Icons.assistant_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      assistantBaseName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _assistantHoldingMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
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
                label: const Text('Öppna information'),
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
    required this.contextValue,
  });

  final AssistantIdentityServices assistantIdentity;
  final AssistantPresentationServices assistantPresentation;
  final TeamZoneContext contextValue;

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
      setState(() => _preference = Future.value(saved));
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
        title: const Text(assistantBaseName),
      ),
      body: FutureBuilder<AssistantIdentityPreference>(
        future: _preference,
        builder: (context, snapshot) {
          final preference =
              snapshot.data ?? const AssistantIdentityPreference(revision: 0);
          final presentationContext =
              AssistantPresentationContext.fromTeamZoneContext(
                widget.contextValue,
              );
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
                            const Icon(Icons.assistant_outlined, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              preference.displayName,
                              key: const Key('assistant-display-name'),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (preference.customName != null)
                              const Text(assistantBaseName),
                            const SizedBox(height: 12),
                            AssistantContextBanner(value: presentationContext),
                            const AssistantDigitalFunctionNotice(),
                            const SizedBox(height: 12),
                            const Text(
                              _assistantHoldingMessage,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Ingen analys körs och inga automatiska åtgärder utförs.',
                              textAlign: TextAlign.center,
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
                            const SizedBox(height: 20),
                            const _AssistantTransparencyList(),
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 12),
                            Text(
                              'Min kö',
                              style: Theme.of(context).textTheme.titleMedium,
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
                              onSelectionChanged: (value) =>
                                  setState(() => _showHistory = value.single),
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
                                    onSelected: (selected) => setState(() {
                                      if (selected) {
                                        _selectedAreaKeys.add(area.key);
                                      } else {
                                        _selectedAreaKeys.remove(area.key);
                                      }
                                    }),
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
                                  key: const Key('assistant-area-preferences'),
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
                              key: const Key('assistant-shared-queue-contract'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
