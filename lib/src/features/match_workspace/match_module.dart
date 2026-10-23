part of '../../app/teamzone_app.dart';

/// The Match module (decision package 11) as its own app: Översikt with
/// the next match and the team's matches, and Truppen with the players'
/// positions and their answers for the next match.
abstract final class _MatchModule {
  static const _key = 'module.match_workspace';

  static Future<void> open(
    BuildContext context, {
    required TeamZoneContext team,
    required CalendarServices calendar,
    required RosterServices roster,
    required MatchServices match,
  }) => _ModuleShell.open(
    context,
    _ModuleShell(
      title: 'Match',
      subtitle: team.teamName,
      icon: Icons.sports_soccer,
      seed: _ModuleShell.seeds[_key]!,
      sections: [
        _ModuleSection(
          label: 'Översikt',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          builder: (_) => _MatchOverview(
            teamId: team.teamId!,
            teamName: team.teamName ?? 'Vårt lag',
            calendar: calendar,
            match: match,
          ),
        ),
        _ModuleSection(
          label: 'Truppen',
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups,
          builder: (_) => _MatchSquad(
            clubId: team.clubId,
            teamId: team.teamId!,
            calendar: calendar,
            roster: roster,
          ),
        ),
      ],
    ),
  );

  /// One match's page in the module's look, from inside the module or from
  /// the event in TeamZone.
  static Future<void> openMatch(
    BuildContext context, {
    required String eventId,
    required String title,
    required CalendarServices calendar,
    required MatchServices match,
    required _MatchSides sides,
    List<ModuleMatch> matches = const [],
    bool live = false,
  }) => _ModuleScope.push<void>(
    context,
    (_) => _MatchPage(
      eventId: eventId,
      title: title,
      calendar: calendar,
      match: match,
      sides: sides,
      matches: matches,
      live: live,
    ),
    seed: _ModuleShell.seeds[_key],
  );

  /// The team's matches from yesterday on; [played] the past half year;
  /// both in date order.
  static Future<List<ModuleMatch>> upcoming(
    CalendarServices calendar,
    String teamId,
  ) {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    return calendar.matchPlans.listMatches(
      teamId: teamId,
      from: midnight.subtract(const Duration(days: 1)),
      to: midnight.add(const Duration(days: 120)),
    );
  }

  static Future<List<ModuleMatch>> played(
    CalendarServices calendar,
    String teamId,
  ) {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    return calendar.matchPlans.listMatches(
      teamId: teamId,
      from: midnight.subtract(const Duration(days: 180)),
      to: midnight,
    );
  }

  /// The next match still to be played, if any.
  static ModuleMatch? next(List<ModuleMatch> matches) => matches
      .where(
        (match) =>
            match.state != 'cancelled' &&
            match.startsAt.isAfter(
              DateTime.now().subtract(const Duration(hours: 3)),
            ),
      )
      .firstOrNull;
}

/// Översikt: the next match up front, then the coming or played matches.
class _MatchOverview extends StatefulWidget {
  const _MatchOverview({
    required this.teamId,
    required this.teamName,
    required this.calendar,
    required this.match,
  });
  final String teamId, teamName;
  final CalendarServices calendar;
  final MatchServices match;

  @override
  State<_MatchOverview> createState() => _MatchOverviewState();
}

class _MatchOverviewState extends State<_MatchOverview> {
  bool _played = false;
  late Future<List<ModuleMatch>> _upcoming = _MatchModule.upcoming(
    widget.calendar,
    widget.teamId,
  );
  Future<List<ModuleMatch>>? _past;

  void _reload() => setState(() {
    _upcoming = _MatchModule.upcoming(widget.calendar, widget.teamId);
    if (_past != null) {
      _past = _MatchModule.played(widget.calendar, widget.teamId);
    }
  });

  /// Opens [match] with [among] to step between, as in the old app.
  Future<void> _open(ModuleMatch match, List<ModuleMatch> among) async {
    await _MatchModule.openMatch(
      context,
      eventId: match.eventId,
      title: match.opponentName?.isNotEmpty == true
          ? '${AppStrings.of(context).feature('Mot')} ${match.opponentName}'
          : match.title,
      calendar: widget.calendar,
      match: widget.match,
      sides: (
        team: widget.teamName,
        opponent: match.opponentName,
        homeAway: match.homeAway,
      ),
      matches: among,
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<List<ModuleMatch>>(
      future: _upcoming,
      builder: (context, upcoming) {
        if (upcoming.hasError) {
          return Center(
            child: Text(strings.feature('Matcherna kunde inte hämtas.')),
          );
        }
        if (!upcoming.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final next = _MatchModule.next(upcoming.data!);
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: next == null
                    ? _NoNextMatch(strings: strings)
                    : _NextMatchCard(
                        match: next,
                        onOpen: () => _open(next, upcoming.data!),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: SegmentedButton<bool>(
                  key: const Key('match-workspace-period'),
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(strings.feature('Kommande')),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(strings.feature('Spelade')),
                    ),
                  ],
                  selected: {_played},
                  onSelectionChanged: (value) => setState(() {
                    _played = value.first;
                    _past ??= _MatchModule.played(
                      widget.calendar,
                      widget.teamId,
                    );
                  }),
                ),
              ),
              if (!_played)
                ..._rows(
                  strings,
                  upcoming.data!.where((m) => m.eventId != next?.eventId),
                  'Inga fler kommande matcher.',
                  upcoming.data!,
                )
              else
                FutureBuilder<List<ModuleMatch>>(
                  future: _past,
                  builder: (context, past) => past.hasData
                      ? Column(
                          children: _rows(
                            strings,
                            past.data!.reversed,
                            'Inga spelade matcher.',
                            past.data!,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: past.hasError
                                ? Text(
                                    strings.feature(
                                      'Matcherna kunde inte hämtas.',
                                    ),
                                  )
                                : const CircularProgressIndicator(),
                          ),
                        ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _rows(
    AppStrings strings,
    Iterable<ModuleMatch> matches,
    String empty,
    List<ModuleMatch> among,
  ) => matches.isEmpty
      ? [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(strings.feature(empty))),
          ),
        ]
      : [
          for (final match in matches)
            _MatchRow(match: match, onTap: () => _open(match, among)),
        ];
}

class _NoNextMatch extends StatelessWidget {
  const _NoNextMatch({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        strings.feature(
          'Ingen kommande match. Matcher läggs in i kalendern i TeamZone.',
        ),
      ),
    ),
  );
}

/// The next match in large: who, when and where, how far it is prepared,
/// and the way into it.
class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({required this.match, required this.onOpen});
  final ModuleMatch match;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final date = MaterialLocalizations.of(
      context,
    ).formatFullDate(match.startsAt);
    final time = TimeOfDay.fromDateTime(match.startsAt).format(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(match.startsAt).difference(today).inDays;
    final when = switch (days) {
      <= 0 => 'Idag',
      1 => 'Imorgon',
      _ => 'Om $days dagar',
    };
    final place = switch (match.homeAway) {
      'home' => 'Hemma',
      'away' => 'Borta',
      _ => null,
    };
    const white = TextStyle(color: Colors.white);
    return DecoratedBox(
      key: const Key('module-next-match'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, Colors.black, 0.45)!,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${strings.feature('Nästa match')} · ${strings.feature(when)}',
              style: white.copyWith(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              match.opponentName?.isNotEmpty == true
                  ? '${strings.feature('Mot')} ${match.opponentName}'
                  : match.title,
              style: white.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              [
                '$date $time',
                if (place != null) strings.feature(place),
              ].join(' · '),
              style: white,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(label: 'Matchplan', value: match.plan),
                _StatusPill(label: 'Uppställning', value: match.lineup),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const Key('module-open-next-match'),
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward),
              label: Text(strings.feature('Öppna matchen')),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final (text, icon) = switch (value) {
      'published' => ('Publicerad', Icons.check_circle),
      'draft' => ('Utkast', Icons.edit_note),
      _ => ('Saknas', Icons.radio_button_unchecked),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              '${strings.feature(label)}: ${strings.feature(text)}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
