part of '../../app/teamzone_app.dart';

/// Why a player's injuries cannot be registered, or null when they can.
String? _tdpInjuryBlocked(BuildContext context, InjuryPlayer player) {
  if (player.allowed) return null;
  if (player.turnedOff) {
    return _tdpText(
      context,
      'Skaderegistreringen är avstängd för spelaren.',
      'Injury registration is turned off for the player.',
    );
  }
  final missing = [
    if (!player.clubConsent) _tdpText(context, 'klubben', 'the club'),
    if (!player.playerConsent) _tdpText(context, 'spelaren', 'the player'),
    if (!player.guardianConsent)
      _tdpText(context, 'en vårdnadshavare', 'a guardian'),
  ];
  return _tdpText(
    context,
    'Spelaren är under 15 år. Skador kan registreras när klubben, spelaren och en vårdnadshavare har godkänt det. Saknas: ${missing.join(', ')}.',
    'The player is under 15. Injuries can be registered once the club, the player and a guardian have agreed. Missing: ${missing.join(', ')}.',
  );
}

/// A player's injuries for the leaders (step 9): the one now, with "Tillbaka
/// i träning", the earlier ones, a new one, and the registration (off or
/// on, and the club's consent under 15). Closes with the team's injuries
/// when something changed.
class _TdpInjurySheet extends StatefulWidget {
  const _TdpInjurySheet({
    required this.controller,
    required this.plan,
    required this.player,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final InjuryPlayer player;

  static Future<TeamInjuries?> open(
    BuildContext context, {
    required _TdpController controller,
    required SeasonPlan plan,
    required InjuryPlayer player,
  }) => showDialog<TeamInjuries>(
    context: context,
    builder: (_) =>
        _TdpInjurySheet(controller: controller, plan: plan, player: player),
  );

  @override
  State<_TdpInjurySheet> createState() => _TdpInjurySheetState();
}

class _TdpInjurySheetState extends State<_TdpInjurySheet> {
  late InjuryPlayer _player = widget.player;
  TeamInjuries? _changed;
  bool _saving = false;

  TeamDevelopmentServices get _services => widget.controller.services;

  Future<void> _run(Future<TeamInjuries> Function() action) async {
    setState(() => _saving = true);
    try {
      final result = await action();
      if (!mounted) return;
      setState(() {
        _changed = result;
        _player = result.of(_player.personId) ?? _player;
      });
    } catch (error) {
      AppErrors.caught('tdp_injuries', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tdpText(
                context,
                'Det gick inte att spara.',
                'It could not be saved.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit([PlayerInjury? injury]) async {
    final saved = await showDialog<_TdpInjuryDraft>(
      context: context,
      builder: (_) => _TdpInjuryEditor(injury: injury),
    );
    if (saved == null) return;
    await _run(
      () => _services.saveInjury(
        widget.plan,
        injuryId: injury?.id,
        personId: _player.personId,
        startedOn: saved.startedOn,
        what: saved.what,
        note: saved.note,
        backOn: saved.backOn,
      ),
    );
  }

  Future<void> _back(PlayerInjury injury) => _run(
    () => _services.saveInjury(
      widget.plan,
      injuryId: injury.id,
      personId: _player.personId,
      startedOn: injury.startedOn,
      what: injury.what,
      note: injury.note ?? '',
      backOn: DateUtils.dateOnly(DateTime.now()),
    ),
  );

  Future<void> _turnOff(bool off) async {
    if (off) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _tdpText(
              context,
              'Stäng av skaderegistreringen?',
              'Turn off injury registration?',
            ),
          ),
          content: Text(
            _tdpText(
              context,
              'Spelarens registrerade skador tas bort, och inga nya kan registreras förrän den slås på igen.',
              'The player\'s registered injuries are deleted, and no new ones can be registered until it is turned on again.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppStrings.of(context).cancel),
            ),
            FilledButton(
              key: const Key('tdp-injury-turn-off-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_tdpText(context, 'Stäng av', 'Turn off')),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    await _run(
      () => _services.setInjuryRegistration(
        widget.plan,
        _player.personId,
        turnOff: off,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final current = _player.currentOn(today);
    final blocked = _tdpInjuryBlocked(context, _player);
    final canEdit = widget.controller.canEdit && !_saving;
    return AlertDialog(
      title: Text(_player.name),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            key: const Key('tdp-injury-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (blocked != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(blocked, key: const Key('tdp-injury-blocked')),
                ),
              if (current != null)
                Card(
                  key: const Key('tdp-injury-current'),
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.healing),
                    title: Text(current.what),
                    subtitle: Text(
                      [
                        _tdpText(
                          context,
                          'Sedan ${_tdpDate(context, current.startedOn)}',
                          'Since ${_tdpDate(context, current.startedOn)}',
                        ),
                        if ((current.note ?? '').isNotEmpty)
                          _tdpPlain(current.note!),
                      ].join('\n'),
                    ),
                    onTap: canEdit ? () => _edit(current) : null,
                  ),
                ),
              if (current != null && canEdit)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    key: const Key('tdp-injury-back'),
                    onPressed: () => _back(current),
                    child: Text(
                      _tdpText(
                        context,
                        'Tillbaka i träning i dag',
                        'Back in training today',
                      ),
                    ),
                  ),
                ),
              if (current == null && _player.allowed && canEdit)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const Key('tdp-injury-new'),
                    onPressed: _edit,
                    icon: const Icon(Icons.add),
                    label: Text(
                      _tdpText(context, 'Registrera skada', 'Register injury'),
                    ),
                  ),
                ),
              for (final injury in _player.injuries)
                if (injury != current)
                  ListTile(
                    key: ValueKey('tdp-injury-${injury.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(injury.what),
                    subtitle: Text(
                      '${_tdpDate(context, injury.startedOn)} – ${injury.backOn == null ? '' : _tdpDate(context, injury.backOn!)}',
                    ),
                    onTap: canEdit ? () => _edit(injury) : null,
                    trailing: canEdit
                        ? IconButton(
                            tooltip: _tdpText(context, 'Ta bort', 'Delete'),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _run(
                              () => _services.deleteInjury(
                                widget.plan,
                                injury.id,
                              ),
                            ),
                          )
                        : null,
                  ),
              if (widget.controller.canEdit) ...[
                const Divider(),
                SwitchListTile(
                  key: const Key('tdp-injury-registration'),
                  contentPadding: EdgeInsets.zero,
                  value: !_player.turnedOff,
                  onChanged: _saving ? null : (on) => _turnOff(!on),
                  title: Text(
                    _tdpText(
                      context,
                      'Skaderegistrering',
                      'Injury registration',
                    ),
                  ),
                  subtitle: Text(
                    _tdpText(
                      context,
                      'Spelaren ser sina skador men inte era anteckningar. Vårdnadshavare ser samma sak.',
                      'The player sees their injuries but not your notes. Guardians see the same.',
                    ),
                  ),
                ),
                if (!_player.adult && !_player.turnedOff)
                  CheckboxListTile(
                    key: const Key('tdp-injury-club-consent'),
                    contentPadding: EdgeInsets.zero,
                    value: _player.clubConsent,
                    onChanged: _saving
                        ? null
                        : (give) => _run(
                            () => _services.setInjuryRegistration(
                              widget.plan,
                              _player.personId,
                              clubConsent: give ?? false,
                            ),
                          ),
                    title: Text(
                      _tdpText(
                        context,
                        'Klubben godkänner skaderegistrering',
                        'The club agrees to injury registration',
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('tdp-injury-close'),
          onPressed: () => Navigator.of(context).pop(_changed),
          child: Text(_tdpText(context, 'Stäng', 'Close')),
        ),
      ],
    );
  }
}

typedef _TdpInjuryDraft = ({
  DateTime startedOn,
  String what,
  String note,
  DateTime? backOn,
});

/// What, from when, the leaders' note, and the day back.
class _TdpInjuryEditor extends StatefulWidget {
  const _TdpInjuryEditor({this.injury});
  final PlayerInjury? injury;

  @override
  State<_TdpInjuryEditor> createState() => _TdpInjuryEditorState();
}

class _TdpInjuryEditorState extends State<_TdpInjuryEditor> {
  final _form = GlobalKey<FormState>();
  late final _what = TextEditingController(text: widget.injury?.what ?? '');
  late final _note = TextEditingController(text: widget.injury?.note ?? '');
  late DateTime _startedOn =
      widget.injury?.startedOn ?? DateUtils.dateOnly(DateTime.now());
  late DateTime? _backOn = widget.injury?.backOn;

  @override
  void dispose() {
    _what.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial, DateTime first) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: DateUtils.dateOnly(DateTime.now()),
  );

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    return AlertDialog(
      title: Text(
        widget.injury == null
            ? _tdpText(context, 'Registrera skada', 'Register injury')
            : _tdpText(context, 'Ändra skada', 'Edit injury'),
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('tdp-injury-what'),
                  controller: _what,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: _tdpText(context, 'Vad', 'What'),
                    helperText: _tdpText(
                      context,
                      'Till exempel "Stukad fot". Spelaren ser det.',
                      'For example "Sprained ankle". The player sees it.',
                    ),
                  ),
                  validator: (text) => (text ?? '').trim().length < 2
                      ? _tdpText(
                          context,
                          'Skriv minst två tecken.',
                          'Write at least two characters.',
                        )
                      : null,
                ),
                ListTile(
                  key: const Key('tdp-injury-started'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(_tdpText(context, 'Från', 'From')),
                  subtitle: Text(_tdpDate(context, _startedOn)),
                  onTap: () async {
                    final day = await _pick(
                      _startedOn,
                      DateTime(today.year - 2),
                    );
                    if (day != null) setState(() => _startedOn = day);
                  },
                ),
                ListTile(
                  key: const Key('tdp-injury-back-on'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.directions_run),
                  title: Text(
                    _tdpText(context, 'Tillbaka i träning', 'Back in training'),
                  ),
                  subtitle: Text(
                    _backOn == null
                        ? _tdpText(context, 'Inte än', 'Not yet')
                        : _tdpDate(context, _backOn!),
                  ),
                  onTap: () async {
                    final day = await _pick(_backOn ?? today, _startedOn);
                    if (day != null) setState(() => _backOn = day);
                  },
                  trailing: _backOn == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _backOn = null),
                        ),
                ),
                _TdpFormatBar(controller: _note),
                TextFormField(
                  key: const Key('tdp-injury-note'),
                  controller: _note,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: _tdpText(
                      context,
                      'Ledarnas anteckning',
                      'Leaders\' note',
                    ),
                    helperText: _tdpText(
                      context,
                      'Visas inte för spelaren eller vårdnadshavare.',
                      'Not shown to the player or guardians.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.of(context).cancel),
        ),
        FilledButton(
          key: const Key('tdp-injury-save'),
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            if (_backOn != null && _backOn!.isBefore(_startedOn)) {
              setState(() => _backOn = _startedOn);
            }
            Navigator.of(context).pop((
              startedOn: _startedOn,
              what: _what.text.trim(),
              note: _note.text.trim(),
              backOn: _backOn,
            ));
          },
          child: Text(_tdpText(context, 'Spara', 'Save')),
        ),
      ],
    );
  }
}
