part of '../../app/teamzone_app.dart';

// Medlemsregister (club-members-and-fees.md, step 1): one plain list of
// everyone in the club, who is a member in which category, filtered by team
// or membership and exported as CSV. Opened from the Klubb page.

String _memberCategoryLabel(AppStrings strings, String? category) =>
    strings.feature(switch (category) {
      'youth' => 'Barn och ungdom',
      'adult' => 'Vuxen',
      'supporter' => 'Stödmedlem',
      _ => 'Okänd kategori',
    });

enum _MemberFilter { all, members, notMembers }

/// Every team in the register, for the team filter.
const _noTeamFilter = '';
const _withoutTeamFilter = '-';

class _ClubRegisterPage extends StatefulWidget {
  const _ClubRegisterPage({
    required this.clubId,
    required this.clubName,
    required this.services,
  });
  final String clubId;
  final String clubName;
  final ClubRegisterServices services;

  @override
  State<_ClubRegisterPage> createState() => _ClubRegisterPageState();
}

class _ClubRegisterPageState extends State<_ClubRegisterPage> {
  late Future<ClubRegister> _register = _load();
  final _search = TextEditingController();
  _MemberFilter _filter = _MemberFilter.all;
  String _team = _noTeamFilter;

  Future<ClubRegister> _load() =>
      widget.services.loadClubRegister(widget.clubId);

  void _reload() => setState(() {
    _register = _load();
  });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ClubRegisterPerson> _visible(List<ClubRegisterPerson> people) {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final person in people)
        if ((query.isEmpty || person.name.toLowerCase().contains(query)) &&
            switch (_filter) {
              _MemberFilter.all => true,
              _MemberFilter.members => person.isMember,
              _MemberFilter.notMembers => !person.isMember,
            } &&
            switch (_team) {
              _noTeamFilter => true,
              _withoutTeamFilter => person.teams.isEmpty,
              final team => person.teams.any((item) => item.teamId == team),
            })
          person,
    ];
  }

  Future<void> _export(List<ClubRegisterPerson> people) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      final saved = await saveClubRegisterCsv(
        'medlemsregister-$day.csv',
        clubRegisterCsv(
          people,
          roleLabel: strings.domainValue,
          categoryLabel: (category) => _memberCategoryLabel(strings, category),
        ),
      );
      if (saved) {
        messenger.showSnackBar(
          SnackBar(content: Text(strings.feature('Registret är exporterat.'))),
        );
      }
    } catch (error) {
      AppErrors.caught('club_register._export', error);
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.feature('Registret kunde inte exporteras.')),
        ),
      );
    }
  }

  Future<void> _open(ClubRegisterPerson person) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ClubRegisterPersonSheet(
        clubId: widget.clubId,
        person: person,
        services: widget.services,
      ),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.feature('Medlemsregister')),
        actions: [
          FutureBuilder<ClubRegister>(
            future: _register,
            builder: (context, snapshot) => IconButton(
              key: const ValueKey('club-register-export'),
              tooltip: strings.feature('Exportera som CSV'),
              icon: const Icon(Icons.download_outlined),
              onPressed: snapshot.data == null
                  ? null
                  : () => _export(_visible(snapshot.data!.people)),
            ),
          ),
        ],
      ),
      body: FutureBuilder<ClubRegister>(
        future: _register,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _StateCard(
                icon: Icons.sync_problem,
                title: strings.couldNotLoad,
                message: strings.safeError,
                action: FilledButton(
                  onPressed: _reload,
                  child: Text(strings.retry),
                ),
              ),
            );
          }
          final register = snapshot.data;
          if (register == null) {
            return AppLoadingIndicator(label: strings.loading);
          }
          final teams = <String, String>{
            for (final person in register.people)
              for (final team in person.teams) team.teamId: team.teamName,
          }.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
          final visible = _visible(register.people);
          final members = visible.where((person) => person.isMember);
          String count(String category) =>
              '${members.where((person) => person.category == category).length}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const ValueKey('club-register-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: strings.feature('Sök på namn'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final (filter, label) in [
                      (_MemberFilter.all, 'Alla'),
                      (_MemberFilter.members, 'Medlemmar'),
                      (_MemberFilter.notMembers, 'Ej medlemmar'),
                    ])
                      ChoiceChip(
                        key: ValueKey('club-register-filter-${filter.name}'),
                        label: Text(strings.feature(label)),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    DropdownButton<String>(
                      key: const ValueKey('club-register-team'),
                      value: _team,
                      onChanged: (value) =>
                          setState(() => _team = value ?? _noTeamFilter),
                      items: [
                        DropdownMenuItem(
                          value: _noTeamFilter,
                          child: Text(strings.feature('Alla lag')),
                        ),
                        for (final team in teams)
                          DropdownMenuItem(
                            value: team.key,
                            child: Text(team.value),
                          ),
                        DropdownMenuItem(
                          value: _withoutTeamFilter,
                          child: Text(strings.feature('Utan lag')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  key: const ValueKey('club-register-summary'),
                  '${visible.length} ${strings.feature(visible.length == 1 ? 'person' : 'personer')} · '
                  '${members.length} ${strings.feature(members.length == 1 ? 'medlem' : 'medlemmar')} '
                  '(${strings.feature('Barn och ungdom')} ${count('youth')}, '
                  '${strings.feature('Vuxen')} ${count('adult')}, '
                  '${strings.feature('Stödmedlem')} ${count('supporter')})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _register;
                  },
                  child: visible.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                strings.feature('Ingen matchar sökningen.'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          key: const ValueKey('club-register-list'),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) => _ClubRegisterRow(
                            person: visible[index],
                            onTap: () => _open(visible[index]),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "P2014 · Spelare, F2012 · Ledare", or the guardian's children.
String _registerRolesLine(AppStrings strings, ClubRegisterPerson person) {
  final parts = [
    for (final team in person.teams)
      '${team.teamName} · ${strings.domainValue(team.role)}',
    if (person.clubRole) strings.feature('Klubbuppdrag'),
    if (person.teams.isEmpty && person.children.isNotEmpty)
      '${strings.feature('Vårdnadshavare till')} ${person.children.join(', ')}',
  ];
  return parts.isEmpty ? strings.feature('Inget lag') : parts.join(', ');
}

class _ClubRegisterRow extends StatelessWidget {
  const _ClubRegisterRow({required this.person, required this.onTap});
  final ClubRegisterPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey('club-register-${person.personId}'),
      title: Text(
        person.birthYear == null
            ? person.name
            : '${person.name} (${person.birthYear})',
      ),
      subtitle: Text(
        _registerRolesLine(strings, person),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        person.isMember
            ? _memberCategoryLabel(strings, person.category)
            : strings.feature(
                person.coveredByChild ? 'Via barnet' : 'Ej medlem',
              ),
        style: TextStyle(
          color: person.isMember ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// One person: teams, guardians, account and the membership to change.
class _ClubRegisterPersonSheet extends StatefulWidget {
  const _ClubRegisterPersonSheet({
    required this.clubId,
    required this.person,
    required this.services,
  });
  final String clubId;
  final ClubRegisterPerson person;
  final ClubRegisterServices services;

  @override
  State<_ClubRegisterPersonSheet> createState() =>
      _ClubRegisterPersonSheetState();
}

/// The category choice for "follow the birth year".
const _automaticCategory = 'automatic';

class _ClubRegisterPersonSheetState extends State<_ClubRegisterPersonSheet> {
  late bool _member = widget.person.isMember;
  late final _email = TextEditingController(text: widget.person.email ?? '');
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// The address fee reminders go to, for someone without an account.
  Future<void> _saveEmail() async {
    final strings = AppStrings.of(context);
    setState(() {
      _saving = true;
      _emailError = null;
    });
    try {
      await widget.services.setClubPersonEmail(
        clubId: widget.clubId,
        personId: widget.person.personId,
        email: _email.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      AppErrors.caught('club_register._saveEmail', error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _emailError = strings.feature(
          error is ClubRegisterInvalidEmail
              ? 'Det ser inte ut som en e-postadress.'
              : 'Adressen kunde inte sparas. Försök igen.',
        );
      });
    }
  }

  late String _category = widget.person.categorySet
      ? widget.person.category ?? _automaticCategory
      : _automaticCategory;
  bool _saving = false;
  String? _error;

  bool get _changed =>
      _member != widget.person.isMember ||
      _category !=
          (widget.person.categorySet
              ? widget.person.category ?? _automaticCategory
              : _automaticCategory);

  Future<void> _save() async {
    final strings = AppStrings.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.services.setClubMembership(
        clubId: widget.clubId,
        personId: widget.person.personId,
        isMember: _member,
        category: _category == _automaticCategory ? null : _category,
        expectedRevision: widget.person.revision,
        idempotencyKey: _newUuid(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      AppErrors.caught('club_register._save', error);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = strings.feature(
          error is ClubRegisterConflict
              ? 'Någon annan har ändrat personen. Stäng och öppna igen.'
              : 'Ändringen kunde inte sparas. Försök igen.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final person = widget.person;
    final theme = Theme.of(context);
    final automatic = person.birthYear == null
        ? strings.feature('Efter födelseår (okänt)')
        : '${strings.feature('Efter födelseår')}: '
              '${_memberCategoryLabel(strings, clubMemberCategoryFor(person.birthYear))}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('club-register-person'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(person.name, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: strings.feature('Stäng'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            if (person.birthYear != null)
              Text('${strings.feature('Född')} ${person.birthYear}'),
            const SizedBox(height: 8),
            Text(_registerRolesLine(strings, person)),
            if (person.guardians.isNotEmpty)
              Text(
                '${strings.feature('Vårdnadshavare')}: ${person.guardians.join(', ')}',
              ),
            if (person.children.isNotEmpty)
              Text('${strings.feature('Barn')}: ${person.children.join(', ')}'),
            Text(
              strings.feature(
                person.hasAccount
                    ? 'Har konto i TeamZone'
                    : 'Har inget konto i TeamZone',
              ),
            ),
            if (person.emailEditable) ...[
              const SizedBox(height: 12),
              Text(
                strings.feature('E-post för påminnelser'),
                style: theme.textTheme.titleSmall,
              ),
              Text(
                strings.feature(
                  'Personen har inget konto i TeamZone. Påminnelser om avgifter går hit, och för ett barn till vårdnadshavarnas adresser.',
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('club-register-email'),
                      controller: _email,
                      enabled: !_saving,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'namn@example.com',
                        errorText: _emailError,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const ValueKey('club-register-email-save'),
                    onPressed: _saving ? null : _saveEmail,
                    child: Text(strings.feature('Spara')),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),
            _ClubRegisterRoles(
              clubId: widget.clubId,
              person: person,
              services: widget.services,
              onChanged: () => Navigator.of(context).pop(true),
            ),
            const Divider(height: 24),
            SwitchListTile(
              key: const ValueKey('club-register-member'),
              contentPadding: EdgeInsets.zero,
              title: Text(strings.feature('Medlem i klubben')),
              subtitle: Text(
                strings.feature(
                  'Spelare, ledare och funktionärer är medlemmar om inget annat sägs.',
                ),
              ),
              value: _member,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _member = value),
            ),
            if (_member) ...[
              const SizedBox(height: 8),
              Text(
                strings.feature('Medlemskategori'),
                style: theme.textTheme.titleSmall,
              ),
              RadioGroup<String>(
                groupValue: _category,
                onChanged: (value) {
                  if (_saving || value == null) return;
                  setState(() => _category = value);
                },
                child: Column(
                  children: [
                    for (final (value, label) in [
                      (_automaticCategory, automatic),
                      for (final category in clubMemberCategories)
                        (category, _memberCategoryLabel(strings, category)),
                    ])
                      RadioListTile<String>(
                        key: ValueKey('club-register-category-$value'),
                        contentPadding: EdgeInsets.zero,
                        value: value,
                        title: Text(label),
                      ),
                  ],
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('club-register-save'),
              onPressed: _saving || !_changed ? null : _save,
              child: Text(strings.feature('Spara')),
            ),
          ],
        ),
      ),
    );
  }
}
