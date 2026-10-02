part of '../../app/teamzone_app.dart';

/// TEAM-15: temporary contact pages (link and QR code, valid for 14 days) for
/// the club and its teams, and the details sent through them. A person is
/// added to a team with one tap.
const _publicSiteOrigin = String.fromEnvironment(
  'PUBLIC_SITE_URL',
  defaultValue: 'https://public.teamzoneapp.se',
);

String _intakeFormUrl(IntakeFormLink form) =>
    '$_publicSiteOrigin/anmalan/${form.token}';

class _IntakeSurface extends StatefulWidget {
  const _IntakeSurface({
    required this.contextValue,
    required this.roster,
    this.onPeopleAdded,
  });
  final TeamZoneContext contextValue;
  final RosterServices roster;
  final VoidCallback? onPeopleAdded;
  @override
  State<_IntakeSurface> createState() => _IntakeSurfaceState();
}

class _IntakeSurfaceState extends State<_IntakeSurface> {
  late Future<IntakeOverview> _load = _fetch();
  final Set<String> _busy = {};

  Future<IntakeOverview> _fetch() => widget.roster
      .getIntakeOverview(clubId: widget.contextValue.clubId)
      .timeout(const Duration(seconds: 15));

  void _reload() => setState(() {
    _load = _fetch();
  });

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _createForm(String? teamId, String name) =>
      _run('form:$teamId', () async {
        final strings = AppStrings.of(context);
        try {
          final form = await widget.roster.createIntakeForm(
            clubId: widget.contextValue.clubId,
            teamId: teamId,
          );
          _reload();
          if (mounted) await _showQr(form, name);
        } catch (_) {
          _show(
            strings.feature(
              'Sidan kunde inte skapas. Kontrollera din behörighet.',
            ),
          );
        }
      });

  /// QR code and direct link to share the page.
  Future<void> _showQr(IntakeFormLink form, String name) {
    final strings = AppStrings.of(context);
    final url = _intakeFormUrl(form);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.feature('Dela sidan')),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: Theme.of(dialogContext).textTheme.titleMedium),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    key: const ValueKey('intake-qr'),
                    data: url,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(url, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                strings
                    .feature('Gäller till {date}')
                    .replaceAll('{date}', _formatBirthDate(form.expiresAt.toLocal())),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              _show(strings.feature('Länken är kopierad.'));
            },
            icon: const Icon(Icons.copy),
            label: Text(strings.feature('Kopiera länk')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.feature('Stäng')),
          ),
        ],
      ),
    );
  }

  Future<void> _closeForm(IntakeFormLink form) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.feature('Stäng sidan?')),
        content: Text(
          strings.feature(
            'Sidan slutar fungera direkt. Redan inskickade uppgifter finns kvar. Du kan skapa en ny sida senare.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.feature('Stäng sidan')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run('close:${form.id}', () async {
      try {
        await widget.roster.closeIntakeForm(formId: form.id);
        _reload();
      } catch (_) {
        _show(strings.feature('Sidan kunde inte stängas. Försök igen.'));
      }
    });
  }

  /// The team a submission goes to by default: the team whose link was
  /// used, else the active team, else the first one you may add to.
  IntakeTeam? _defaultTeam(IntakeOverview data, IntakeSubmission submission) {
    IntakeTeam? find(String? id) =>
        data.teams.where((team) => team.id == id).firstOrNull;
    return find(submission.teamId) ??
        find(widget.contextValue.teamId) ??
        data.teams.firstOrNull;
  }

  Future<void> _accept(
    IntakeSubmission submission,
    IntakeTeam team,
    String role,
  ) => _run(submission.id, () async {
    final strings = AppStrings.of(context);
    try {
      await widget.roster.acceptIntakeSubmission(
        submissionId: submission.id,
        teamId: team.id,
        role: role,
        idempotencyKey: _newUuid(),
      );
      _show(
        strings
            .feature('{name} lades till i {team}.')
            .replaceAll('{name}', submission.fullName)
            .replaceAll('{team}', team.name),
      );
      widget.onPeopleAdded?.call();
      _reload();
    } catch (_) {
      _show(
        strings.feature(
          role == 'leader'
              ? 'Personen kunde inte läggas till som ledare. Kontrollera att du får hantera lagets ledare.'
              : 'Personen kunde inte läggas till. Försök igen.',
        ),
      );
    }
  });

  Future<void> _chooseTeamAndRole(
    IntakeOverview data,
    IntakeSubmission submission,
  ) async {
    final strings = AppStrings.of(context);
    var team = _defaultTeam(data, submission);
    var role = 'player';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(submission.fullName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('intake-team'),
                initialValue: team?.id,
                isExpanded: true,
                decoration: InputDecoration(labelText: strings.feature('Lag')),
                items: [
                  for (final item in data.teams)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (value) => setDialog(
                  () => team = data.teams.firstWhere((item) => item.id == value),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                key: const ValueKey('intake-role'),
                segments: [
                  ButtonSegment(
                    value: 'player',
                    label: Text(strings.feature('Spelare')),
                  ),
                  ButtonSegment(
                    value: 'leader',
                    label: Text(strings.feature('Ledare')),
                  ),
                ],
                selected: {role},
                onSelectionChanged: (value) =>
                    setDialog(() => role = value.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.feature('Avbryt')),
            ),
            FilledButton(
              key: const ValueKey('intake-confirm'),
              onPressed: team == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(strings.feature('Lägg till')),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && team != null) {
      await _accept(submission, team!, role);
    }
  }

  Future<void> _updateExisting(
    IntakeOverview data,
    IntakeSubmission submission,
  ) async {
    final strings = AppStrings.of(context);
    final choice = await showDialog<(IntakeTeam, RosterPersonSummary)>(
      context: context,
      builder: (_) => _IntakeMergeDialog(
        roster: widget.roster,
        clubId: widget.contextValue.clubId,
        teams: data.teams,
        initialTeam: _defaultTeam(data, submission),
        submission: submission,
      ),
    );
    if (choice == null) return;
    final (team, person) = choice;
    await _run(submission.id, () async {
      try {
        await widget.roster.updatePersonFromIntake(
          submissionId: submission.id,
          teamId: team.id,
          personId: person.id,
        );
        _show(
          strings
              .feature('{name}s uppgifter är uppdaterade.')
              .replaceAll('{name}', person.displayName),
        );
        widget.onPeopleAdded?.call();
        _reload();
      } catch (_) {
        _show(strings.feature('Personen kunde inte uppdateras. Försök igen.'));
      }
    });
  }

  Future<void> _dismiss(IntakeSubmission submission) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.feature('Ta bort uppgifterna?')),
        content: Text(
          strings
              .feature('{name}s uppgifter tas bort utan att läggas till.')
              .replaceAll('{name}', submission.fullName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.feature('Ta bort')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(submission.id, () async {
      try {
        await widget.roster.dismissIntakeSubmission(
          submissionId: submission.id,
        );
        _reload();
      } catch (_) {
        _show(strings.feature('Uppgifterna kunde inte tas bort. Försök igen.'));
      }
    });
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  List<Widget> _formSection(IntakeOverview data, AppStrings strings) {
    final activeTeam = data.teams
        .where((team) => team.id == widget.contextValue.teamId)
        .firstOrNull;
    final hasTeamForm =
        activeTeam != null &&
        data.forms.any((form) => form.teamId == activeTeam.id);
    final hasClubForm = data.forms.any((form) => form.teamId == null);
    return [
      _heading(strings.feature('Aktiva sidor')),
      Text(
        strings.feature(
          'Skapa en tillfällig sida där spelare, ledare eller föräldrar fyller i sina kontaktuppgifter utan att logga in. Sidan gäller i 14 dagar och delas med QR-kod eller länk. Det som skickas in hamnar här.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      for (final form in data.forms)
        Card(
          key: ValueKey('intake-form-${form.id}'),
          child: ListTile(
            leading: const Icon(Icons.link),
            title: Text(form.teamName ?? strings.feature('Hela klubben')),
            subtitle: Text(
              '${strings.feature('Gäller till {date}').replaceAll('{date}', _formatBirthDate(form.expiresAt.toLocal()))}\n${_intakeFormUrl(form)}',
            ),
            isThreeLine: true,
            trailing: Wrap(
              children: [
                IconButton(
                  key: ValueKey('intake-qr-${form.id}'),
                  tooltip: strings.feature('Visa QR-kod'),
                  icon: const Icon(Icons.qr_code_2),
                  onPressed: () => _showQr(
                    form,
                    form.teamName ?? strings.feature('Hela klubben'),
                  ),
                ),
                IconButton(
                  key: ValueKey('intake-copy-${form.id}'),
                  tooltip: strings.feature('Kopiera länk'),
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _intakeFormUrl(form)),
                    );
                    _show(strings.feature('Länken är kopierad.'));
                  },
                ),
                IconButton(
                  tooltip: strings.feature('Stäng sidan'),
                  icon: const Icon(Icons.link_off),
                  onPressed: _busy.contains('close:${form.id}')
                      ? null
                      : () => _closeForm(form),
                ),
              ],
            ),
          ),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (activeTeam != null && !hasTeamForm)
            OutlinedButton.icon(
              key: const ValueKey('intake-create-team'),
              onPressed: _busy.contains('form:${activeTeam.id}')
                  ? null
                  : () => _createForm(activeTeam.id, activeTeam.name),
              icon: const Icon(Icons.qr_code_2),
              label: Text(
                strings
                    .feature('Skapa sida för {team}')
                    .replaceAll('{team}', activeTeam.name),
              ),
            ),
          if (data.canManageClub && !hasClubForm)
            OutlinedButton.icon(
              key: const ValueKey('intake-create-club'),
              onPressed: _busy.contains('form:null')
                  ? null
                  : () => _createForm(null, strings.feature('Hela klubben')),
              icon: const Icon(Icons.qr_code_2),
              label: Text(strings.feature('Skapa sida för hela klubben')),
            ),
        ],
      ),
    ];
  }

  Widget _submissionCard(
    IntakeOverview data,
    IntakeSubmission submission,
    AppStrings strings,
  ) {
    final team = _defaultTeam(data, submission);
    final busy = _busy.contains(submission.id);
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('intake-submission-${submission.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(submission.fullName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                _formatBirthDate(submission.birthDate),
                submission.phone,
                submission.email,
              ].join(' · '),
            ),
            Text(
              '${submission.streetAddress}, ${submission.postalCode} ${submission.city}',
            ),
            const SizedBox(height: 2),
            Text(
              strings
                  .feature('Via {source}')
                  .replaceAll(
                    '{source}',
                    submission.teamName ?? strings.feature('klubbens sida'),
                  ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (team != null)
                  FilledButton.icon(
                    key: ValueKey('intake-add-${submission.id}'),
                    onPressed: busy
                        ? null
                        : () => _accept(submission, team, 'player'),
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.group_add_outlined),
                    label: Text(
                      strings
                          .feature('Lägg till i {team}')
                          .replaceAll('{team}', team.name),
                    ),
                  ),
                OutlinedButton.icon(
                  key: ValueKey('intake-update-${submission.id}'),
                  onPressed: busy
                      ? null
                      : () => _updateExisting(data, submission),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: Text(strings.feature('Uppdatera befintlig')),
                ),
                TextButton(
                  key: ValueKey('intake-choose-${submission.id}'),
                  onPressed: busy
                      ? null
                      : () => _chooseTeamAndRole(data, submission),
                  child: Text(strings.feature('Annat lag eller roll')),
                ),
                IconButton(
                  tooltip: strings.feature('Ta bort'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy ? null : () => _dismiss(submission),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.feature('Kontaktuppdatering')),
        actions: [
          IconButton(
            tooltip: strings.feature('Uppdatera'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<IntakeOverview>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StateCard(
              icon: Icons.lock_outline,
              title: strings.feature('Kontaktuppgifterna kunde inte hämtas'),
              message: strings.feature(
                'Kontrollera din behörighet och anslutning och försök igen.',
              ),
              action: FilledButton(
                onPressed: _reload,
                child: Text(strings.feature('Försök igen')),
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return AppLoadingIndicator(label: strings.loading);
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _load;
            },
            child: ListView(
              key: const ValueKey('intake-surface'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                ..._formSection(data, strings),
                _heading(
                  '${strings.feature('Inskickade uppgifter')} (${data.submissions.length})',
                ),
                if (data.submissions.isEmpty)
                  Text(strings.feature('Inga inskickade uppgifter just nu.'))
                else
                  for (final submission in data.submissions)
                    _submissionCard(data, submission, strings),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Picks the existing person the sent details belong to: a team, then a
/// person in it. Names sharing a word with the sent name come first.
class _IntakeMergeDialog extends StatefulWidget {
  const _IntakeMergeDialog({
    required this.roster,
    required this.clubId,
    required this.teams,
    required this.initialTeam,
    required this.submission,
  });
  final RosterServices roster;
  final String clubId;
  final List<IntakeTeam> teams;
  final IntakeTeam? initialTeam;
  final IntakeSubmission submission;
  @override
  State<_IntakeMergeDialog> createState() => _IntakeMergeDialogState();
}

class _IntakeMergeDialogState extends State<_IntakeMergeDialog> {
  late IntakeTeam? _team = widget.initialTeam;
  late Future<List<RosterPersonSummary>> _people = _load();
  final _search = TextEditingController();
  RosterPersonSummary? _selected;

  /// Leaders by person id; they come from the team's roles, not the squad.
  Set<String> _leaders = const {};

  /// Active players and the team's leaders.
  Future<List<RosterPersonSummary>> _load() async {
    final team = _team;
    if (team == null) return const [];
    final (people, roles) = await (
      widget.roster.listPeople(clubId: widget.clubId, teamId: team.id),
      widget.roster
          .listTeamRoles(clubId: widget.clubId, teamId: team.id)
          .then<TeamRoles?>((value) => value, onError: (_) => null),
    ).wait.timeout(const Duration(seconds: 15));
    final active = [
      for (final person in people)
        if (person.assignmentState == 'active') person,
    ];
    final known = {for (final person in active) person.id};
    final leaders = <String>{};
    for (final role in roles?.roles ?? const <TeamRole>[]) {
      if (role.role == 'player') continue;
      leaders.add(role.personId);
      if (known.add(role.personId)) {
        active.add(
          RosterPersonSummary(
            id: role.personId,
            displayName: role.name,
            safeguardingRequired: false,
            teamId: team.id,
            teamName: team.name,
            assignmentState: 'active',
          ),
        );
      }
    }
    if (mounted) setState(() => _leaders = leaders);
    return active;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static Set<String> _words(String name) => name
      .toLowerCase()
      .split(RegExp(r'[\s.-]+'))
      .where((word) => word.length > 1)
      .toSet();

  bool _likelyMatch(RosterPersonSummary person) => _words(
    person.displayName,
  ).intersection(_words(widget.submission.fullName)).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.feature('Uppdatera befintlig person')),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings
                  .feature(
                    'Telefon, e-post och adress från {name} sparas på personen du väljer. Namnet ändras inte.',
                  )
                  .replaceAll('{name}', widget.submission.fullName),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('intake-merge-team'),
              initialValue: _team?.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: strings.feature('Lag')),
              items: [
                for (final team in widget.teams)
                  DropdownMenuItem(value: team.id, child: Text(team.name)),
              ],
              onChanged: (value) => setState(() {
                _team = widget.teams.firstWhere((team) => team.id == value);
                _selected = null;
                _people = _load();
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.feature('Sök person'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<RosterPersonSummary>>(
                future: _people,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        strings.feature('Truppen kunde inte hämtas.'),
                      ),
                    );
                  }
                  final people = snapshot.data;
                  if (people == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final query = _search.text.trim().toLowerCase();
                  final shown =
                      people
                          .where(
                            (person) =>
                                query.isEmpty ||
                                person.displayName.toLowerCase().contains(
                                  query,
                                ),
                          )
                          .toList()
                        ..sort((a, b) {
                          final match = (_likelyMatch(b) ? 1 : 0).compareTo(
                            _likelyMatch(a) ? 1 : 0,
                          );
                          return match != 0
                              ? match
                              : a.displayName.compareTo(b.displayName);
                        });
                  if (shown.isEmpty) {
                    return Center(
                      child: Text(strings.feature('Inga personer hittades.')),
                    );
                  }
                  return RadioGroup<String>(
                    groupValue: _selected?.id,
                    onChanged: (value) => setState(
                      () => _selected = shown.firstWhere(
                        (person) => person.id == value,
                      ),
                    ),
                    child: ListView(
                      children: [
                        for (final person in shown)
                          RadioListTile<String>(
                            key: ValueKey('intake-merge-${person.id}'),
                            value: person.id,
                            title: Text(person.displayName),
                            subtitle:
                                _likelyMatch(person) ||
                                    _leaders.contains(person.id)
                                ? Text(
                                    [
                                      if (_leaders.contains(person.id))
                                        strings.feature('Ledare'),
                                      if (_likelyMatch(person))
                                        strings.feature('Möjlig matchning'),
                                    ].join(' · '),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          key: const ValueKey('intake-merge-confirm'),
          onPressed: _team == null || _selected == null
              ? null
              : () => Navigator.pop(context, (_team!, _selected!)),
          child: Text(strings.feature('Uppdatera')),
        ),
      ],
    );
  }
}
