part of '../../app/teamzone_app.dart';

// Lägg till person (2026-11-13): the member register adds someone new to
// the club without an application or a team roster: a board member or
// functionary, a club member, or a leader in one or more teams with a
// title. With an e-mail address the app hands over an invitation code so
// they can connect their account.

/// Opens the form; true when someone was added.
Future<bool> _openClubRegisterAddPerson(
  BuildContext context, {
  required String clubId,
  required ClubRegisterServices services,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _ClubRegisterAddPerson(clubId: clubId, services: services),
      ),
    ) ==
    true;

class _ClubRegisterAddPerson extends StatefulWidget {
  const _ClubRegisterAddPerson({required this.clubId, required this.services});
  final String clubId;
  final ClubRegisterServices services;

  @override
  State<_ClubRegisterAddPerson> createState() => _ClubRegisterAddPersonState();
}

class _ClubRegisterAddPersonState extends State<_ClubRegisterAddPerson> {
  late final Future<List<({String id, String name})>> _teams = widget.services
      .listClubTeams(widget.clubId)
      .timeout(const Duration(seconds: 15));
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _clubRoles = <String>{'club_functionary'};
  final _leaderTeams = <String>{};
  String? _title;
  bool _saving = false;
  String? _error;
  final _idempotencyKey = newClubRegisterUuid();

  /// After saving with an e-mail address: the code to hand over.
  String? _code;
  String? _addedName;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      (_clubRoles.isNotEmpty || _leaderTeams.isNotEmpty);

  Future<void> _save() async {
    final strings = AppStrings.of(context);
    final email = _email.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final personId = await widget.services.createClubPerson(
        clubId: widget.clubId,
        name: _name.text.trim(),
        email: email.isEmpty ? null : email,
        clubRoles: _clubRoles.toList(),
        leaderTeamIds: _leaderTeams.toList(),
        leaderTitle: _leaderTeams.isEmpty ? null : _title,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      if (email.isEmpty) {
        Navigator.of(context).pop(true);
        return;
      }
      String? code;
      try {
        code = await widget.services.issueClubPersonInvitation(
          personId: personId,
          email: email,
        );
      } catch (error) {
        // The person is added; only the code failed. It can be made later
        // from the team roster.
        AppErrors.caught('club_register_add._invite', error);
      }
      if (!mounted) return;
      if (code == null) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _code = code;
        _addedName = _name.text.trim();
        _saving = false;
      });
    } catch (error) {
      final code = error is ClubPersonCreateException ? error.code : null;
      if (code == null) AppErrors.caught('club_register_add._save', error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = strings.feature(switch (code) {
          'invalid_email' => 'E-postadressen ser inte ut att stämma.',
          'no_role' => 'Välj minst en roll.',
          _ => 'Personen kunde inte läggas till. Försök igen.',
        });
      });
    }
  }

  Future<void> _copyCode() async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _code!));
    messenger.showSnackBar(
      SnackBar(
        content: Text(strings.feature('Inbjudningskoden har kopierats.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final code = _code;
    return Scaffold(
      key: const ValueKey('club-register-add'),
      appBar: AppBar(
        title: Text(strings.feature('Lägg till person')),
        actions: [
          if (code == null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                key: const ValueKey('club-register-add-save'),
                onPressed: _saving || !_valid ? null : _save,
                child: Text(strings.feature('Lägg till')),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: code != null
              ? ListView(
                  key: const ValueKey('club-register-add-code'),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${_addedName ?? ''} ${strings.feature('är tillagd.')}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.feature(
                        'Skicka inbjudningskoden till personen. När hen har '
                        'skapat ett konto med samma e-postadress klistrar hen '
                        'in koden under Inställningar → Använd kod. Koden '
                        'gäller i 14 dagar.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(code),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('club-register-add-copy'),
                          onPressed: _copyCode,
                          icon: const Icon(Icons.copy_outlined),
                          label: Text(strings.feature('Kopiera')),
                        ),
                        FilledButton(
                          key: const ValueKey('club-register-add-done'),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(strings.feature('Klar')),
                        ),
                      ],
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      key: const ValueKey('club-register-add-name'),
                      controller: _name,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: strings.feature('Namn'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      key: const ValueKey('club-register-add-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: strings.feature('E-post (valfritt)'),
                        helperText: strings.feature(
                          'Med e-post får du en inbjudningskod att skicka, så '
                          'att personen kan koppla sitt konto.',
                        ),
                        helperMaxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      strings.feature('I klubben'),
                      style: theme.textTheme.titleMedium,
                    ),
                    for (final role in _clubWideRoles)
                      CheckboxListTile(
                        key: ValueKey('club-register-add-role-$role'),
                        contentPadding: EdgeInsets.zero,
                        value: _clubRoles.contains(role),
                        title: Text(_clubRoleLabel(strings, role)),
                        subtitle: role == 'club_functionary'
                            ? Text(
                                strings.feature(
                                  'Styrelseposten registreras sedan under '
                                  'Uppdrag → Styrelse.',
                                ),
                              )
                            : null,
                        onChanged: (on) => setState(
                          () => on == true
                              ? _clubRoles.add(role)
                              : _clubRoles.remove(role),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      strings.feature('Ledare i lag'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<({String id, String name})>>(
                      future: _teams,
                      builder: (context, snapshot) {
                        final teams = snapshot.data;
                        if (teams == null) {
                          return snapshot.hasError
                              ? Text(
                                  strings.feature('Lagen kunde inte hämtas.'),
                                )
                              : const LinearProgressIndicator();
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final team in teams)
                              FilterChip(
                                key: ValueKey(
                                  'club-register-add-team-${team.id}',
                                ),
                                label: Text(team.name),
                                selected: _leaderTeams.contains(team.id),
                                onSelected: (on) => setState(
                                  () => on
                                      ? _leaderTeams.add(team.id)
                                      : _leaderTeams.remove(team.id),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    if (_leaderTeams.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        key: const ValueKey('club-register-add-title'),
                        initialValue: _title,
                        decoration: InputDecoration(
                          labelText: strings.feature('Titel i laget'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(strings.feature('Ledare')),
                          ),
                          for (final title in clubLeaderTitles)
                            DropdownMenuItem(
                              value: title,
                              child: Text(_titleLabel(strings, title)),
                            ),
                        ],
                        onChanged: (value) => setState(() => _title = value),
                      ),
                    ],
                    if (_error case final error?) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
