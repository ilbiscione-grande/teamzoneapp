part of '../../app/teamzone_app.dart';

/// Truppen in the Match module: the team's players by main position, with
/// shirt number and other positions, and each one's answer for the next
/// match. Positions and numbers are set under Laget in TeamZone.
class _MatchSquad extends StatefulWidget {
  const _MatchSquad({
    required this.clubId,
    required this.teamId,
    required this.calendar,
    required this.roster,
  });
  final String clubId, teamId;
  final CalendarServices calendar;
  final RosterServices roster;

  @override
  State<_MatchSquad> createState() => _MatchSquadState();
}

class _MatchSquadState extends State<_MatchSquad> {
  late Future<TeamRoles> _roles = _loadRoles();
  late final Future<(ModuleMatch?, Map<String, EventRosterPerson>)> _next =
      _loadNext();

  Future<TeamRoles> _loadRoles() =>
      widget.roster.listTeamRoles(clubId: widget.clubId, teamId: widget.teamId);

  /// The next match and the players' answers for it; without either the
  /// list still shows.
  Future<(ModuleMatch?, Map<String, EventRosterPerson>)> _loadNext() async {
    try {
      final next = _MatchModule.next(
        await _MatchModule.upcoming(widget.calendar, widget.teamId),
      );
      if (next == null) return (null, const <String, EventRosterPerson>{});
      final squad = await widget.calendar.getEventSquad(next.eventId);
      return (next, {for (final p in squad.roster) p.personId: p});
    } catch (_) {
      return (null, const <String, EventRosterPerson>{});
    }
  }

  static const _groups = ['goalkeeper', 'defender', 'midfielder', 'forward'];
  static const _groupLabels = {
    'goalkeeper': 'Målvakter',
    'defender': 'Försvarare',
    'midfielder': 'Mittfältare',
    'forward': 'Anfallare',
  };

  /// The general position a player's main position belongs to.
  static String? _group(TeamRole role, List<SportPosition> catalog) {
    final key =
        role.mainPosition ??
        role.positions.firstOrNull ??
        role.customPositions.firstOrNull;
    if (key == null) return null;
    final entry = catalog.where((e) => e.key == key).firstOrNull;
    final general = entry == null
        ? null
        : entry.isGeneral
        ? entry.key
        : entry.parent;
    return _groups.contains(general) ? general : null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<TeamRoles>(
      future: _roles,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(strings.feature('Truppen kunde inte hämtas.')),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final roles = snapshot.data!;
        final players = {
          for (final role in roles.roles)
            if (role.role == 'player') role.personId: role,
        }.values.toList()..sort(_byNumberThenName);
        if (players.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                strings.feature('Laget har inga spelare än.'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final grouped = <String?, List<TeamRole>>{};
        for (final player in players) {
          grouped
              .putIfAbsent(_group(player, roles.positionCatalog), () => [])
              .add(player);
        }
        return FutureBuilder(
          future: _next,
          builder: (context, next) {
            final (match, answers) =
                next.data ?? (null, const <String, EventRosterPerson>{});
            return RefreshIndicator(
              onRefresh: () async => setState(() => _roles = _loadRoles()),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _SquadSummary(
                    players: players.length,
                    match: match,
                    answers: answers,
                  ),
                  for (final group in [..._groups, null])
                    if (grouped[group]?.isNotEmpty == true) ...[
                      _GroupHeader(
                        label: group == null
                            ? 'Utan position'
                            : _groupLabels[group]!,
                        count: grouped[group]!.length,
                      ),
                      for (final player in grouped[group]!)
                        _SquadRow(
                          player: player,
                          catalog: roles.positionCatalog,
                          answer: match == null
                              ? null
                              : answers[player.personId],
                        ),
                    ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  static int _byNumberThenName(TeamRole a, TeamRole b) {
    final number = (a.jerseyNumber ?? 999).compareTo(b.jerseyNumber ?? 999);
    return number != 0 ? number : a.name.compareTo(b.name);
  }
}

/// How many players, and for the next match how many have answered yes,
/// no or not yet.
class _SquadSummary extends StatelessWidget {
  const _SquadSummary({
    required this.players,
    required this.match,
    required this.answers,
  });
  final int players;
  final ModuleMatch? match;
  final Map<String, EventRosterPerson> answers;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final called = answers.values.where((p) => p.isCalled).toList();
    int count(String state) =>
        called.where((p) => p.callupState == state).length;
    final yes = count('accepted'), no = count('declined');
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$players ${strings.feature('spelare')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              match == null
                  ? strings.feature('Ingen kommande match.')
                  : called.isEmpty
                  ? strings.feature('Ingen är kallad till nästa match än.')
                  : '${strings.feature('Nästa match')}: $yes '
                        '${strings.feature('kommer')}, $no '
                        '${strings.feature('kommer inte')}, '
                        '${called.length - yes - no} '
                        '${strings.feature('har inte svarat')}',
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        '${AppStrings.of(context).feature(label)} ($count)',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// One player: number, name, positions and the answer for the next match.
class _SquadRow extends StatelessWidget {
  const _SquadRow({
    required this.player,
    required this.catalog,
    required this.answer,
  });
  final TeamRole player;
  final List<SportPosition> catalog;
  final EventRosterPerson? answer;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final positions = _orderedPositions(player, catalog);
    final main = player.mainPosition;
    final ordered = [
      ?main,
      ...positions.where((position) => position != main),
    ].map((position) => _anyPositionLabel(strings, position)).join(' · ');
    return ListTile(
      key: Key('module-squad-${player.personId}'),
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: Text(
          player.jerseyNumber?.toString() ?? '–',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(player.name),
      subtitle: ordered.isEmpty ? null : Text(ordered),
      trailing: _AnswerBadge(answer: answer),
    );
  }
}

class _AnswerBadge extends StatelessWidget {
  const _AnswerBadge({required this.answer});
  final EventRosterPerson? answer;

  @override
  Widget build(BuildContext context) {
    final person = answer;
    if (person == null || !person.isCalled) return const SizedBox.shrink();
    final strings = AppStrings.of(context);
    final (label, icon, color) = switch (person.callupState) {
      'accepted' => ('Kommer', Icons.check_circle, Colors.green),
      'declined' => ('Kommer inte', Icons.cancel, Colors.red),
      _ => ('Inget svar', Icons.help_outline, Colors.grey),
    };
    return Tooltip(
      message: strings.feature(label),
      child: Icon(icon, color: color),
    );
  }
}
