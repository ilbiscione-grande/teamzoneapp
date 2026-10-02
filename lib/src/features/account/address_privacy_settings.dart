part of '../../app/teamzone_app.dart';

class _AddressPrivacySettings extends StatefulWidget {
  const _AddressPrivacySettings({required this.profile, this.onChanged});
  final ProfileServices profile;
  final VoidCallback? onChanged;
  @override
  State<_AddressPrivacySettings> createState() =>
      _AddressPrivacySettingsState();
}

class _AddressPrivacySettingsState extends State<_AddressPrivacySettings> {
  List<Map<String, dynamic>> _subjects = [];
  Map<String, dynamic>? _data;
  String? _target, _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
    });
    try {
      final subjects = await widget.profile.listPrivacySubjects();
      if (!mounted) return;
      _subjects = subjects;
      _target = subjects.isEmpty ? null : subjects.first['id'] as String;
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Uppgifterna kunde inte hämtas.';
          _data = null;
          _busy = false;
        });
      }
    }
  }

  Future<void> _load() async {
    final data = _target == null
        ? null
        : await widget.profile.getAddressPrivacy(_target!);
    if (mounted) {
      setState(() {
        _data = data;
        if (data != null) {
          _subjects = [
            for (final subject in _subjects)
              if (subject['id'] == data['profile_id'])
                {...subject, 'name': data['name']}
              else
                subject,
          ];
        }
        _busy = false;
      });
    }
  }

  Future<void> _command(String command, Map<String, dynamic> values) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.profile.saveAddressPrivacyCommand(command, {
        'target': _target,
        ...values,
      });
      await _load();
      if (mounted) widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Ändringen kunde inte sparas. Uppdatera innan du försöker igen.';
          _busy = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _rows(String key) => ((_data?[key] as List?) ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  Future<void> _editAddress([Map<String, dynamic>? address]) async {
    final result = await _editFields(
      title: 'Adress',
      fields: {
        'address_label': 'Namn på adressen',
        'new_street': 'Gatuadress',
        'new_postal': 'Postnummer',
        'new_city': 'Ort',
      },
      initial: {
        'address_label': address?['label'],
        'new_street': address?['street'],
        'new_postal': address?['postal'],
        'new_city': address?['city'],
      },
    );
    if (result != null) {
      await _command('save_profile_address', {
        ...result,
        'address_id': address?['id'] ?? _newUuid(),
        'expected_revision': address?['revision'] ?? 0,
      });
    }
  }

  Future<Map<String, dynamic>?> _editFields({
    required String title,
    required Map<String, String> fields,
    required Map<String, dynamic> initial,
    String? notice,
  }) async {
    final controllers = {
      for (final key in fields.keys)
        key: TextEditingController(text: initial[key] as String? ?? ''),
    };
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).feature(title)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (notice != null)
                  Text(AppStrings.of(context).feature(notice)),
                for (final field in fields.entries)
                  TextField(
                    key: ValueKey('privacy-${field.key}'),
                    controller: controllers[field.key],
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).feature(field.value),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            key: const ValueKey('privacy-save-fields'),
            onPressed: () => Navigator.pop(context, {
              for (final entry in controllers.entries)
                entry.key: entry.value.text.trim(),
            }),
            child: Text(AppStrings.of(context).feature('Spara')),
          ),
        ],
      ),
    );
    // Dialog fields can still be mounted during the closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return result;
  }

  Future<void> _protection(bool enabled) async {
    final result = await _editFields(
      title: enabled ? 'Begränsa personuppgifter' : 'Stäng av begränsningen',
      fields: {
        'new_alias': 'Visningsnamn i laget',
        'new_private_name': 'Privat namn',
        'new_safe_email': 'Säker kontakt-e-post',
        'new_safe_phone': 'Säkert telefonnummer',
      },
      initial: {
        'new_alias': (_data?['protected'] == true) ? _data!['alias'] : '',
        'new_private_name': _data?['private_name'] ?? _data?['name'],
        'new_safe_email': _data?['safe_email'],
        'new_safe_phone': _data?['safe_phone'],
      },
      notice: enabled
          ? 'Använd ett visningsnamn som inte avslöjar identiteten. Namn, kontaktuppgifter, födelsedata och profilbild tas bort från vanliga vyer. Granska även tidigare fritext, foton och exporter. Vanliga aviseringar stängs av.'
          : 'Namnet från före skyddat läge återställs. Kontaktuppgifter, bilder och publiceringssamtycken återställs inte automatiskt.',
    );
    if (result != null) {
      await _command('save_profile_privacy', {
        ...result,
        'enable_protection': enabled,
        'expected_revision': _data?['revision'] ?? 0,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final addresses = _rows('addresses');
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.feature('Adresser och integritet')),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              tooltip: strings.feature('Uppdatera'),
              onPressed: _busy ? null : _init,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            key: const ValueKey('privacy-settings-list'),
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  strings.feature(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_subjects.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _target,
                  key: ValueKey('privacy-subject-$_target'),
                  decoration: InputDecoration(
                    labelText: strings.feature('Person'),
                  ),
                  items: [
                    for (final s in _subjects)
                      DropdownMenuItem(
                        value: s['id'] as String,
                        child: Text(s['name'] as String),
                      ),
                  ],
                  onChanged: (value) async {
                    setState(() {
                      _target = value;
                      _data = null;
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await _load();
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          _busy = false;
                          _error = 'Uppgifterna kunde inte hämtas.';
                        });
                      }
                    }
                  },
                ),
              if (_data != null) ...[
                const SizedBox(height: 20),
                Text(
                  strings.feature('Dina adresser'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  strings.feature(
                    'Adresser delas bara med de klubbar du väljer. Ingen huvudadress krävs.',
                  ),
                ),
                for (final address in addresses)
                  Card(
                    child: ListTile(
                      title: Text(address['label'] as String),
                      subtitle: Text(
                        [
                          address['street'],
                          address['postal'],
                          address['city'],
                        ].whereType<String>().join(', '),
                      ),
                      onTap: () => _editAddress(address),
                      trailing: IconButton(
                        tooltip: strings.feature('Ta bort'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(strings.feature('Ta bort adressen?')),
                              content: Text(
                                strings.feature(
                                  'Klubbar som använder adressen får ingen vald adress.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(strings.feature('Avbryt')),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(strings.feature('Ta bort')),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await _command('delete_profile_address', {
                              'address_id': address['id'],
                              'expected_revision': address['revision'],
                            });
                          }
                        },
                      ),
                    ),
                  ),
                TextButton.icon(
                  key: const ValueKey('privacy-add-address'),
                  onPressed: () => _editAddress(),
                  icon: const Icon(Icons.add),
                  label: Text(strings.feature('Lägg till adress')),
                ),
                const Divider(height: 32),
                Text(
                  strings.feature('Kontaktadress per klubb'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final club in _rows('clubs'))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'club-address-${club['id']}-${club['address_id']}',
                      ),
                      initialValue: club['address_id'] as String? ?? '',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: club['name'] as String,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(strings.feature('Ingen adress delas')),
                        ),
                        for (final a in addresses)
                          DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(a['label'] as String),
                          ),
                      ],
                      onChanged: (value) => _command('choose_club_address', {
                        'club': club['id'],
                        'address_id': value == '' ? null : value,
                      }),
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  strings.feature('Begränsad åtkomst'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  strings.feature(
                    'Bara du och behörig vårdnadshavare kan ändra dessa inställningar. Utvalda kontaktpersoner får läsa säker kontaktväg och klubbens valda adress.',
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('privacy-protection'),
                  title: Text(strings.feature('Begränsa personuppgifter')),
                  value: _data?['protected'] == true,
                  onChanged: _protection,
                ),
                if (_data?['protected'] == true) ...[
                  TextButton(
                    onPressed: () => _protection(true),
                    child: Text(strings.feature('Ändra säker kontaktväg')),
                  ),
                  for (final club in _rows('clubs')) ...[
                    Text(
                      club['name'] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final candidate in _rows(
                      'candidates',
                    ).where((v) => v['club_id'] == club['id']))
                      SwitchListTile(
                        title: Text(candidate['name'] as String),
                        value: _rows('grants').any(
                          (g) =>
                              g['viewer_id'] == candidate['viewer_id'] &&
                              g['club_id'] == club['id'],
                        ),
                        onChanged: (value) =>
                            _command('set_private_contact_grant', {
                              'club': club['id'],
                              'viewer': candidate['viewer_id'],
                              'allow_access': value,
                            }),
                      ),
                    for (final grant in _rows('grants').where(
                      (g) =>
                          g['club_id'] == club['id'] &&
                          !_rows('candidates').any(
                            (c) =>
                                c['club_id'] == club['id'] &&
                                c['viewer_id'] == g['viewer_id'],
                          ),
                    ))
                      ListTile(
                        title: Text(grant['name'] as String),
                        trailing: TextButton(
                          onPressed: () =>
                              _command('set_private_contact_grant', {
                                'club': club['id'],
                                'viewer': grant['viewer_id'],
                                'allow_access': false,
                              }),
                          child: Text(strings.feature('Ta bort åtkomst')),
                        ),
                      ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
