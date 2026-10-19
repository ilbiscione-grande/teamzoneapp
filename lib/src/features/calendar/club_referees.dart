import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/calendar/club_referee_pay.dart';
import 'package:teamzone_app/src/features/calendar/referee_home.dart';
import 'package:teamzone_app/src/features/calendar/referee_services.dart';

/// REF-02: föreningsdomare and the club's domaransvarig. The home page has
/// "Mina domaruppdrag" for club referees (and their guardians); the board
/// ("Domartillsättning", or "Domarersättning" for the one who only pays)
/// opens from the menu for the active club.
class RefereeHomeCards extends StatefulWidget {
  const RefereeHomeCards({super.key, required this.services});
  final RefereeServices? services;

  @override
  State<RefereeHomeCards> createState() => _RefereeHomeCardsState();
}

class _RefereeHomeCardsState extends State<RefereeHomeCards> {
  late Future<RefereeSummary> _summary = _load();

  Future<RefereeSummary> _load() async {
    final services = widget.services;
    if (services == null) return const RefereeSummary();
    try {
      return await services.summary().timeout(const Duration(seconds: 15));
    } catch (error) {
      AppErrors.caught('club_referees.summary', error);
      return const RefereeSummary();
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!mounted) return;
    final next = _load();
    setState(() {
      _summary = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    if (services == null) return const SizedBox.shrink();
    return FutureBuilder<RefereeSummary>(
      future: _summary,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null || !summary.clubReferee) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (summary.clubReferee)
              Card(
                key: const ValueKey('club-referee-card'),
                child: ListTile(
                  leading: const Icon(Icons.sports),
                  title: const Text('Mina domaruppdrag'),
                  subtitle: Text(
                    summary.openCount > 0
                        ? '${summary.openCount} lediga uppdrag att anmäla sig till'
                        : 'Föreningsdomare',
                  ),
                  trailing: summary.openCount > 0
                      ? Badge.count(count: summary.openCount)
                      : const Icon(Icons.chevron_right),
                  onTap: () => _open(ClubRefereePage(services: services)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The club referee's page: requests and assignments, and the own club's
/// open places to sign up for (domaransvarig approves).
class ClubRefereePage extends StatefulWidget {
  const ClubRefereePage({super.key, required this.services});
  final RefereeServices services;

  @override
  State<ClubRefereePage> createState() => _ClubRefereePageState();
}

class _ClubRefereePageState extends State<ClubRefereePage> {
  late Future<List<OpenClubMatch>> _open = widget.services.openClubMatches();
  int _revision = 0;

  void _reload() {
    final next = widget.services.openClubMatches();
    setState(() {
      _open = next;
      _revision++;
    });
  }

  Future<void> _signUp(OpenClubMatch item) async {
    final open = item.match.openSlots;
    if (open.isEmpty) return;
    var slot = open.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Anmäl till matchen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.match.matchup),
              Text('Domare: ${item.personName}'),
              if (open.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: slot,
                  decoration: const InputDecoration(labelText: 'Plats'),
                  items: [
                    for (final value in open)
                      DropdownMenuItem(
                        value: value,
                        child: Text(refereeSlotLabel(value)),
                      ),
                  ],
                  onChanged: (value) => setDialog(() => slot = value ?? slot),
                ),
              const SizedBox(height: 8),
              const Text('Domaransvarig godkänner anmälan.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              key: const ValueKey('club-referee-sign-up-send'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Anmäl'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.services.requestClub(
        item.match.eventId,
        slot,
        item.personId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anmälan är skickad till domaransvarig.')),
      );
      _reload();
    } catch (error) {
      AppErrors.caught('club_referees.signUp', error);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(refereeErrorText(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mina domaruppdrag')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            RefereeHome(
              key: ValueKey('club-referee-home-$_revision'),
              services: widget.services,
              showMatchSearch: false,
            ),
            const SizedBox(height: 16),
            Text(
              'Lediga uppdrag i klubben',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FutureBuilder<List<OpenClubMatch>>(
              future: _open,
              builder: (context, snapshot) {
                final items = snapshot.data;
                if (items == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Inga lediga uppdrag just nu.'),
                  );
                }
                return Column(
                  children: [
                    for (final item in items)
                      Card(
                        key: ValueKey(
                          'club-open-${item.match.eventId}-${item.personId}',
                        ),
                        child: ListTile(
                          title: Text(item.match.matchup),
                          subtitle: Text(
                            [
                              '${material.formatMediumDate(item.match.startsAt.toLocal())} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(item.match.startsAt.toLocal()))}',
                              ?item.match.location,
                              if (items.map((i) => i.personId).toSet().length >
                                  1)
                                item.personName,
                              if (item.clash) 'krockar med annat',
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () => _signUp(item),
                        ),
                      ),
                  ],
                );
              },
            ),
            MyRefereePaySection(
              key: ValueKey('club-referee-pay-$_revision'),
              services: widget.services,
            ),
          ],
        ),
      ),
    );
  }
}

/// The domaransvarig's board: the club's matches (assign, approve
/// sign-ups, choose the kind of referee), the club referees and
/// domaransvariga, and the rules per team.
class ClubRefereeBoardPage extends StatefulWidget {
  const ClubRefereeBoardPage({
    super.key,
    required this.services,
    required this.clubId,
    required this.clubName,
    this.canManage = true,
    this.canPay = false,
    this.teamId,
    this.teamName,
  });
  final RefereeServices services;
  final String clubId, clubName;

  /// The active team: its matches are shown first; the whole club is one
  /// tap away.
  final String? teamId, teamName;

  /// Domaransvarig: matches, reports, referees and rules.
  final bool canManage;

  /// Domarersättning: the payout lists.
  final bool canPay;

  @override
  State<ClubRefereeBoardPage> createState() => _ClubRefereeBoardPageState();
}

class _ClubRefereeBoardPageState extends State<ClubRefereeBoardPage> {
  late DateTime _from = DateUtils.dateOnly(DateTime.now());
  late Future<ClubRefereeBoard>? _board = widget.canManage ? _load() : null;
  bool _onlyMissing = false;
  late bool _onlyTeam = widget.teamId != null;
  bool _busy = false;

  DateTime get _to => _from.add(const Duration(days: 13));

  Future<ClubRefereeBoard> _load() =>
      widget.services.board(widget.clubId, _from, _to);

  void _reload() {
    final next = _load();
    setState(() {
      _board = next;
    });
  }

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done)));
      }
      if (mounted) _reload();
    } catch (error) {
      AppErrors.caught('club_referees.board', error);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(refereeErrorText(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(ClubBoardMatch item, String slot) async {
    final candidates = await widget.services
        .candidates(item.match.eventId)
        .catchError((_) => const <ClubRefereeInfo>[]);
    if (!mounted) return;
    final picked = await showModalBottomSheet<ClubRefereeInfo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _CandidateSheet(
        title: '${refereeSlotLabel(slot)} · ${item.match.matchup}',
        candidates: candidates,
      ),
    );
    if (picked == null) return;
    await _run(
      () => widget.services.propose(
        item.match.eventId,
        slot,
        personId: picked.personId,
      ),
      '${picked.name} har fått förfrågan.',
    );
  }

  Future<ClubPerson?> _pickPerson(String title) =>
      showModalBottomSheet<ClubPerson>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _PersonSearchSheet(
          title: title,
          search: (query) =>
              widget.services.searchClubPeople(widget.clubId, query),
        ),
      );

  Future<void> _editReferee(ClubRefereeInfo? existing) async {
    var person = existing == null
        ? null
        : ClubPerson(personId: existing.personId, name: existing.name);
    if (person == null) {
      person = await _pickPerson('Lägg till föreningsdomare');
      if (person == null || !mounted) return;
    }
    DateTime? trained = existing?.trainedOn;
    DateTime? valid = existing?.validUntil;
    final material = MaterialLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          Future<void> pick(bool trainedDate) async {
            final now = DateTime.now();
            final value = await showDatePicker(
              context: dialogContext,
              firstDate: DateTime(now.year - 10),
              lastDate: DateTime(now.year + 10),
              initialDate: (trainedDate ? trained : valid) ?? now,
            );
            if (value != null) {
              setDialog(() => trainedDate ? trained = value : valid = value);
            }
          }

          return AlertDialog(
            title: Text(person!.name),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Utbildning klar'),
                  subtitle: Text(
                    trained == null
                        ? 'Ej angiven'
                        : material.formatMediumDate(trained!),
                  ),
                  onTap: () => pick(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Giltig till'),
                  subtitle: Text(
                    valid == null
                        ? 'Ej angiven'
                        : material.formatMediumDate(valid!),
                  ),
                  onTap: () => pick(false),
                ),
              ],
            ),
            actions: [
              if (existing != null)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'end'),
                  child: const Text('Avsluta rollen'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Avbryt'),
              ),
              FilledButton(
                key: const ValueKey('club-referee-save'),
                onPressed: () => Navigator.pop(dialogContext, 'save'),
                child: const Text('Spara'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    final chosen = person;
    await _run(
      () => widget.services.setClubReferee(
        widget.clubId,
        chosen.personId,
        result == 'save',
        trainedOn: trained,
        validUntil: valid,
      ),
      result == 'save'
          ? '${chosen.name} är föreningsdomare.'
          : '${chosen.name} är inte längre föreningsdomare.',
    );
  }

  Future<void> _editRule(TeamRefereeDefault rule) async {
    var kind = rule.kind ?? 'club';
    var slots = rule.slotCount.clamp(1, 3);
    var homeOnly = rule.homeOnly;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(rule.teamName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('referee-rule-kind'),
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Domare'),
                items: [
                  for (final value in const ['club', 'federation', 'none'])
                    DropdownMenuItem(
                      value: value,
                      child: Text(refereeKindLabel(value)),
                    ),
                ],
                onChanged: (value) => setDialog(() => kind = value ?? kind),
              ),
              if (kind != 'none')
                DropdownButtonFormField<int>(
                  initialValue: slots,
                  decoration: const InputDecoration(labelText: 'Antal domare'),
                  items: [
                    for (final value in const [1, 2, 3])
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setDialog(() => slots = value ?? slots),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: homeOnly,
                onChanged: (value) => setDialog(() => homeOnly = value),
                title: const Text('Bara hemmamatcher'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              key: const ValueKey('referee-rule-save'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Spara'),
            ),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    var changed = 0;
    await _run(() async {
      changed = await widget.services.saveTeamDefault(
        rule.teamId,
        kind,
        kind == 'none' ? 0 : slots,
        homeOnly,
      );
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Regeln är sparad. $changed kommande matcher fick den direkt.',
            ),
          ),
        );
    }
  }

  Widget _withBoard(Widget Function(ClubRefereeBoard board) build) =>
      FutureBuilder<ClubRefereeBoard>(
        future: _board,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: _reload,
                child: const Text('Översikten kunde inte hämtas. Försök igen.'),
              ),
            );
          }
          final board = snapshot.data;
          if (board == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return build(board);
        },
      );

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, Widget)>[
      if (widget.canManage) ...[
        ('Matcher', _withBoard(_matches)),
        (
          'Rapporter',
          ClubRefereeReportsView(
            services: widget.services,
            clubId: widget.clubId,
          ),
        ),
        ('Domare', _withBoard(_referees)),
        ('Regler', _withBoard(_rules)),
      ],
      if (widget.canPay)
        (
          'Ersättning',
          ClubRefereePayoutsView(
            services: widget.services,
            clubId: widget.clubId,
            pickPerson: _pickPerson,
          ),
        ),
    ];
    final title = widget.canManage ? 'Domartillsättning' : 'Domarersättning';
    if (tabs.length == 1) {
      return Scaffold(
        appBar: AppBar(title: Text('$title · ${widget.clubName}')),
        body: tabs.single.$2,
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('$title · ${widget.clubName}'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          ),
        ),
        body: TabBarView(children: [for (final tab in tabs) tab.$2]),
      ),
    );
  }

  Widget _matches(ClubRefereeBoard board) {
    final material = MaterialLocalizations.of(context);
    final inScope = board.matches
        .where((item) => !_onlyTeam || item.teamId == widget.teamId)
        .toList();
    final shown = inScope
        .where(
          (item) =>
              !_onlyMissing || (item.refereeKind == 'club' && item.missing > 0),
        )
        .toList();
    final missing = inScope
        .where((item) => item.refereeKind == 'club' && item.missing > 0)
        .length;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Föregående två veckor',
              onPressed: () {
                _from = _from.subtract(const Duration(days: 14));
                _reload();
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${material.formatShortDate(_from)} – ${material.formatShortDate(_to)}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: 'Nästa två veckor',
              onPressed: () {
                _from = _from.add(const Duration(days: 14));
                _reload();
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                missing == 0
                    ? 'Alla matcher med föreningsdomare är tillsatta.'
                    : '$missing matcher saknar föreningsdomare.',
              ),
            ),
            if (widget.teamId != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  key: const ValueKey('referee-board-only-team'),
                  label: Text(widget.teamName ?? 'Laget'),
                  selected: _onlyTeam,
                  onSelected: (value) => setState(() => _onlyTeam = value),
                ),
              ),
            FilterChip(
              key: const ValueKey('referee-board-only-missing'),
              label: const Text('Bara saknade'),
              selected: _onlyMissing,
              onSelected: (value) => setState(() => _onlyMissing = value),
            ),
          ],
        ),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Inga matcher i perioden.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final item in shown) _matchCard(item),
      ],
    );
  }

  Widget _matchCard(ClubBoardMatch item) {
    final material = MaterialLocalizations.of(context);
    final start = item.match.startsAt.toLocal();
    final places = item.refereeKind == 'none'
        ? 0
        : item.match.slotCount.clamp(item.refereeKind == 'club' ? 1 : 0, 3);
    return Card(
      key: ValueKey('referee-board-match-${item.match.eventId}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.match.matchup,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('referee-board-kind-${item.match.eventId}'),
                  tooltip: 'Typ av domare',
                  onSelected: (kind) => _run(
                    () => widget.services.setKind(item.match.eventId, kind),
                  ),
                  itemBuilder: (_) => [
                    for (final value in const ['club', 'federation', 'none'])
                      PopupMenuItem(
                        value: value,
                        child: Text(refereeKindLabel(value)),
                      ),
                  ],
                  child: Chip(label: Text(refereeKindLabel(item.refereeKind))),
                ),
              ],
            ),
            Text(
              [
                '${material.formatMediumDate(start)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
                ?item.match.location,
              ].join(' · '),
            ),
            for (final slot in refereeSlots.take(places)) _slotRow(item, slot),
          ],
        ),
      ),
    );
  }

  Widget _slotRow(ClubBoardMatch item, String slot) {
    final referee = item.referees
        .where((value) => value.slot == slot)
        .firstOrNull;
    final club = item.refereeKind == 'club';
    final state = switch (referee?.state) {
      'awaiting_referee' => 'väntar på svar',
      'awaiting_coordinator' => 'anmäld – godkänn?',
      'awaiting_team' => 'väntar på laget',
      'confirmed' => 'bekräftad',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(refereeSlotLabel(slot)),
          subtitle: Text(
            referee == null ? 'Ledig' : '${referee.name} · $state',
          ),
          trailing: referee == null
              ? (club
                    ? TextButton(
                        key: ValueKey(
                          'referee-board-assign-${item.match.eventId}-$slot',
                        ),
                        onPressed: _busy ? null : () => _assign(item, slot),
                        child: const Text('Tillsätt'),
                      )
                    : null)
              : (referee.kind == 'club'
                    ? IconButton(
                        tooltip: 'Ta bort',
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => widget.services.withdraw(referee.id),
                              ),
                        icon: const Icon(Icons.close),
                      )
                    : null),
        ),
        if (referee?.state == 'awaiting_coordinator')
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.services.respond(referee!.id, false),
                      ),
                child: const Text('Neka'),
              ),
              FilledButton(
                key: ValueKey('referee-board-approve-${referee!.id}'),
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.services.respond(referee.id, true),
                        '${referee.name} är tillsatt.',
                      ),
                child: const Text('Godkänn'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _referees(ClubRefereeBoard board) {
    final material = MaterialLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(
          key: const ValueKey('club-referee-add'),
          onPressed: _busy ? null : () => _editReferee(null),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Lägg till föreningsdomare'),
        ),
        if (board.referees.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Inga föreningsdomare ännu.'),
          ),
        for (final referee in board.referees)
          ListTile(
            key: ValueKey('club-referee-${referee.personId}'),
            leading: const Icon(Icons.sports),
            title: Text(referee.name),
            subtitle: Text(
              [
                if (referee.age != null) '${referee.age} år',
                '${referee.seasonCount} uppdrag i år',
                if (referee.validUntil != null)
                  'utbildning giltig till ${material.formatShortDate(referee.validUntil!)}'
                else if (referee.trainedOn == null)
                  'utbildning ej angiven',
              ].join(' · '),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editReferee(referee),
          ),
        if (board.canAppointCoordinators) ...[
          const Divider(height: 32),
          Text(
            'Domaransvariga',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Kan tillsätta föreningsdomare och godkänna anmälningar. Klubbens administratörer kan alltid.',
          ),
          for (final person in board.coordinators)
            ListTile(
              title: Text(person.name),
              trailing: IconButton(
                tooltip: 'Ta bort som domaransvarig',
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.services.setCoordinator(
                          widget.clubId,
                          person.personId,
                          false,
                        ),
                      ),
                icon: const Icon(Icons.close),
              ),
            ),
          TextButton.icon(
            key: const ValueKey('club-referee-coordinator-add'),
            onPressed: _busy
                ? null
                : () async {
                    final person = await _pickPerson('Lägg till domaransvarig');
                    if (person == null) return;
                    await _run(
                      () => widget.services.setCoordinator(
                        widget.clubId,
                        person.personId,
                        true,
                      ),
                      '${person.name} är domaransvarig.',
                    );
                  },
            icon: const Icon(Icons.add),
            label: const Text('Lägg till domaransvarig'),
          ),
        ],
      ],
    );
  }

  Widget _rules(ClubRefereeBoard board) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const Text(
        'Regeln sätter typ och antal domare på lagets nya och kommande matcher som inte redan har en typ.',
      ),
      for (final rule in board.defaults)
        ListTile(
          key: ValueKey('referee-rule-${rule.teamId}'),
          title: Text(rule.teamName),
          subtitle: Text(
            rule.kind == null
                ? 'Ingen regel'
                : [
                    refereeKindLabel(rule.kind),
                    if (rule.kind != 'none') '${rule.slotCount} st',
                    rule.homeOnly ? 'hemmamatcher' : 'alla matcher',
                  ].join(' · '),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editRule(rule),
        ),
      ClubRefereeFeesSection(services: widget.services, clubId: widget.clubId),
    ],
  );
}

class _CandidateSheet extends StatelessWidget {
  const _CandidateSheet({required this.title, required this.candidates});
  final String title;
  final List<ClubRefereeInfo> candidates;

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (candidates.isEmpty)
        const Text('Inga föreningsdomare att välja. Lägg till under Domare.'),
      for (final candidate in candidates)
        ListTile(
          key: ValueKey('club-candidate-${candidate.personId}'),
          leading: Icon(
            candidate.clash || candidate.ageOk == false
                ? Icons.warning_amber_outlined
                : Icons.sports,
          ),
          title: Text(candidate.name),
          subtitle: Text(
            [
              '${candidate.seasonCount} uppdrag i år',
              if (candidate.age != null) '${candidate.age} år',
              if (candidate.clash) 'krockar med annat',
              if (candidate.ageOk == false) 'för ung för laget',
              if (candidate.ageOk == null) 'ålder okänd',
            ].join(' · '),
          ),
          onTap: () => Navigator.pop(context, candidate),
        ),
    ],
  );
}

class _PersonSearchSheet extends StatefulWidget {
  const _PersonSearchSheet({required this.title, required this.search});
  final String title;
  final Future<List<ClubPerson>> Function(String query) search;

  @override
  State<_PersonSearchSheet> createState() => _PersonSearchSheetState();
}

class _PersonSearchSheetState extends State<_PersonSearchSheet> {
  Timer? _debounce;
  List<ClubPerson>? _results;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        TextField(
          key: const ValueKey('club-person-search'),
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Sök person i klubben',
          ),
          onChanged: (value) {
            _query = value.trim();
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), () async {
              final text = _query;
              if (text.length < 2) {
                if (mounted) setState(() => _results = null);
                return;
              }
              try {
                final results = await widget.search(text);
                if (mounted && text == _query) {
                  setState(() => _results = results);
                }
              } catch (error) {
                AppErrors.caught('club_referees.searchPeople', error);
                if (mounted) setState(() => _results = const []);
              }
            });
          },
        ),
        if (_results != null)
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (_results!.isEmpty)
                  const ListTile(title: Text('Ingen träff.')),
                for (final person in _results!)
                  ListTile(
                    key: ValueKey('club-person-${person.personId}'),
                    title: Text(person.name),
                    subtitle: Text(
                      [
                        ?person.teamNames,
                        if (person.age != null) '${person.age} år',
                        if (person.clubReferee) 'föreningsdomare',
                      ].join(' · '),
                    ),
                    onTap: () => Navigator.pop(context, person),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
