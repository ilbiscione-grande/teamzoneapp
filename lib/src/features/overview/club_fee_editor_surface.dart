part of '../../app/teamzone_app.dart';

// A fee round's terms (club-members-and-fees.md, step 2): membership fee per
// category with an optional family rule, or a team fee per player. Saved as
// a draft; returns the round id.

class _ClubFeeRoundEditor extends StatefulWidget {
  const _ClubFeeRoundEditor({
    required this.clubId,
    required this.teams,
    required this.services,
    this.round,
  });
  final String clubId;
  final _FeeTeams teams;
  final ClubFeeServices services;

  /// The draft to change; null for a new round.
  final ClubFeeRound? round;

  @override
  State<_ClubFeeRoundEditor> createState() => _ClubFeeRoundEditorState();
}

class _ClubFeeRoundEditorState extends State<_ClubFeeRoundEditor> {
  late String _kind = widget.round?.kind ?? 'membership';
  late String? _teamId =
      widget.round?.teamId ??
      (widget.teams.isEmpty ? null : widget.teams.first.id);
  late DateTime _dueOn =
      widget.round?.dueOn ??
      DateUtils.dateOnly(DateTime.now().add(const Duration(days: 30)));
  late final _title = TextEditingController(text: widget.round?.title ?? '');
  late final Map<String, TextEditingController> _amounts = {
    for (final key in ['youth', 'adult', 'supporter', 'player'])
      key: TextEditingController(
        text: switch (widget.round?.amounts[key]) {
          final minor? =>
            '${minor ~/ 100}${minor % 100 == 0 ? '' : ',${(minor % 100).toString().padLeft(2, '0')}'}',
          null => '',
        },
      ),
  };
  late final _sibling = TextEditingController(
    text: widget.round?.siblingDiscountPercent?.toString() ?? '',
  );
  late final _cap = TextEditingController(
    text: switch (widget.round?.familyCap) {
      final minor? => '${minor ~/ 100}',
      null => '',
    },
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    _sibling.dispose();
    _cap.dispose();
    super.dispose();
  }

  String _suggestedTitle(AppStrings strings) {
    if (_kind == 'membership') {
      return '${strings.feature('Medlemsavgift')} ${_dueOn.year}';
    }
    final team = widget.teams.where((team) => team.id == _teamId).firstOrNull;
    return '${strings.feature('Lagavgift')} ${team?.name ?? ''}'.trim();
  }

  /// The draft, or null with [_error] set when something is missing.
  ClubFeeRoundDraft? _draft(AppStrings strings) {
    String? fail(String message) {
      _error = strings.feature(message);
      return null;
    }

    final amounts = <String, int>{};
    for (final key
        in _kind == 'membership' ? clubMemberCategories : const ['player']) {
      final text = _amounts[key]!.text.trim();
      if (text.isEmpty) continue;
      final minor = clubFeeMinorFrom(text);
      if (minor == null) {
        fail('Skriv beloppen i kronor, till exempel 300.');
        return null;
      }
      amounts[key] = minor;
    }
    if (amounts.values.every((amount) => amount == 0)) {
      fail(
        _kind == 'membership'
            ? 'Ange ett belopp för minst en kategori.'
            : 'Ange beloppet per spelare.',
      );
      return null;
    }
    if (_kind == 'team' && _teamId == null) {
      fail('Välj lag.');
      return null;
    }
    int? sibling;
    int? cap;
    if (_kind == 'membership') {
      if (_sibling.text.trim().isNotEmpty) {
        sibling = int.tryParse(_sibling.text.trim());
        if (sibling == null || sibling < 1 || sibling > 100) {
          fail('Syskonrabatten anges i procent, 1–100.');
          return null;
        }
      }
      if (_cap.text.trim().isNotEmpty) {
        cap = clubFeeMinorFrom(_cap.text);
        if (cap == null || cap == 0) {
          fail('Skriv taket i kronor, till exempel 800.');
          return null;
        }
      }
    }
    final title = _title.text.trim().isEmpty
        ? _suggestedTitle(strings)
        : _title.text.trim();
    return ClubFeeRoundDraft(
      kind: _kind,
      teamId: _kind == 'team' ? _teamId : null,
      title: title.length > 120 ? title.substring(0, 120) : title,
      dueOn: _dueOn,
      amounts: amounts,
      familyCap: cap,
      siblingDiscountPercent: sibling,
    );
  }

  Future<void> _save() async {
    final strings = AppStrings.of(context);
    final draft = _draft(strings);
    if (draft == null) {
      setState(() {});
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final roundId = await widget.services.saveClubFeeRound(
        clubId: widget.clubId,
        roundId: widget.round?.roundId,
        draft: draft,
        expectedRevision: widget.round?.revision ?? 0,
        idempotencyKey: _newUuid(),
      );
      if (mounted) Navigator.of(context).pop(roundId);
    } catch (error) {
      AppErrors.caught('club_fees._save', error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = strings.feature(
          error is ClubRegisterConflict
              ? 'Någon annan har ändrat omgången. Öppna den igen.'
              : 'Omgången kunde inte sparas. Försök igen.',
        );
      });
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueOn,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null && mounted) setState(() => _dueOn = picked);
  }

  Widget _amountField(String key, String label, {String suffix = 'kr'}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          key: ValueKey('club-fee-amount-$key'),
          controller: _amounts[key],
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final membership = _kind == 'membership';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.feature(
            widget.round == null ? 'Ny avgiftsomgång' : 'Ändra avgiftsomgång',
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            key: const ValueKey('club-fee-editor'),
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'membership',
                    label: Text(
                      key: const ValueKey('club-fee-kind-membership'),
                      strings.feature('Medlemsavgift'),
                    ),
                  ),
                  ButtonSegment(
                    value: 'team',
                    enabled: widget.teams.isNotEmpty,
                    label: Text(
                      key: const ValueKey('club-fee-kind-team'),
                      strings.feature('Lagavgift'),
                    ),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _saving
                    ? null
                    : (value) => setState(() => _kind = value.single),
              ),
              const SizedBox(height: 8),
              Text(
                strings.feature(
                  membership
                      ? 'För alla som är medlemmar, med belopp per kategori.'
                      : 'För spelarna i ett lag, med samma belopp per spelare.',
                ),
                style: theme.textTheme.bodySmall,
              ),
              if (!membership) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('club-fee-team'),
                  initialValue: _teamId,
                  decoration: InputDecoration(
                    labelText: strings.feature('Lag'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final team in widget.teams)
                      DropdownMenuItem(value: team.id, child: Text(team.name)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _teamId = value),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('club-fee-title'),
                controller: _title,
                enabled: !_saving,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: strings.feature('Namn'),
                  hintText: _suggestedTitle(strings),
                  border: const OutlineInputBorder(),
                ),
              ),
              ListTile(
                key: const ValueKey('club-fee-due'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(strings.feature('Sista betalningsdag')),
                subtitle: Text(_feeDay(_dueOn)),
                onTap: _saving ? null : _pickDue,
              ),
              if (membership) ...[
                Text(
                  strings.feature('Belopp per kategori'),
                  style: theme.textTheme.titleSmall,
                ),
                for (final category in clubMemberCategories)
                  _amountField(
                    category,
                    _memberCategoryLabel(strings, category),
                  ),
                const SizedBox(height: 20),
                Text(
                  strings.feature('Familjerabatt'),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  strings.feature(
                    'Valfritt. Den dyraste avgiften i en familj betalas hel, rabatten gäller syskonen. Taket begränsar familjens summa.',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    key: const ValueKey('club-fee-sibling'),
                    controller: _sibling,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: strings.feature('Rabatt från andra syskonet'),
                      suffixText: '%',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    key: const ValueKey('club-fee-cap'),
                    controller: _cap,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: strings.feature('Högst per familj'),
                      suffixText: 'kr',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ] else
                _amountField('player', strings.feature('Belopp per spelare')),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  key: const ValueKey('club-fee-error'),
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('club-fee-save'),
                onPressed: _saving ? null : _save,
                child: Text(strings.feature('Spara utkast')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
