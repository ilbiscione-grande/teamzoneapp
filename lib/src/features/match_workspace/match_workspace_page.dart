part of '../../app/teamzone_app.dart';

/// The Match module (decision package 11): the team's matches, coming or
/// played, each opening its match page. The module's first step is the
/// match plan; live and analysis follow in its next steps.
class _MatchWorkspacePage extends StatefulWidget {
  const _MatchWorkspacePage({required this.teamId, required this.calendar});
  final String teamId;
  final CalendarServices calendar;

  @override
  State<_MatchWorkspacePage> createState() => _MatchWorkspacePageState();
}

class _MatchWorkspacePageState extends State<_MatchWorkspacePage> {
  bool _played = false;
  late Future<List<ModuleMatch>> _matches = _load();

  Future<List<ModuleMatch>> _load() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    return widget.calendar.matchPlans.listMatches(
      teamId: widget.teamId,
      from: _played
          ? midnight.subtract(const Duration(days: 180))
          : midnight.subtract(const Duration(days: 1)),
      to: _played ? midnight : midnight.add(const Duration(days: 120)),
    );
  }

  Future<void> _open(ModuleMatch match) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MatchPage(
          eventId: match.eventId,
          title: match.title,
          calendar: widget.calendar,
        ),
      ),
    );
    if (mounted) setState(() => _matches = _load());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.feature('Match'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                _matches = _load();
              }),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ModuleMatch>>(
              future: _matches,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      strings.feature('Matcherna kunde inte hämtas.'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final matches = _played
                    ? snapshot.data!.reversed.toList()
                    : snapshot.data!;
                if (matches.isEmpty) {
                  return Center(
                    child: Text(
                      strings.feature(
                        _played
                            ? 'Inga spelade matcher.'
                            : 'Inga kommande matcher.',
                      ),
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final match in matches)
                      _MatchRow(match: match, onTap: () => _open(match)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.onTap});
  final ModuleMatch match;
  final VoidCallback onTap;

  static String _status(String value) => switch (value) {
    'published' => 'Publicerad',
    'draft' => 'Utkast',
    _ => 'Saknas',
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(match.startsAt);
    final time = TimeOfDay.fromDateTime(match.startsAt).format(context);
    final place = switch (match.homeAway) {
      'home' => strings.feature('Hemma'),
      'away' => strings.feature('Borta'),
      _ => null,
    };
    return ListTile(
      key: Key('module-match-${match.eventId}'),
      leading: const Icon(Icons.sports_soccer_outlined),
      title: Text(
        match.opponentName?.isNotEmpty == true
            ? '${strings.feature('Mot')} ${match.opponentName}'
            : match.title,
      ),
      subtitle: Text(
        [
          '$date $time',
          ?place,
          if (match.state == 'cancelled') strings.feature('Inställd'),
          '${strings.feature('Matchplan')}: ${strings.feature(_status(match.plan))}',
          '${strings.feature('Uppställning')}: ${strings.feature(_status(match.lineup))}',
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// One match in the module: Förberedelse (the match plan), Live and Analys.
class _MatchPage extends StatelessWidget {
  const _MatchPage({
    required this.eventId,
    required this.title,
    required this.calendar,
  });
  final String eventId, title;
  final CalendarServices calendar;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    Widget later(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(strings.feature(text), textAlign: TextAlign.center),
      ),
    );
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: TabBar(
            tabs: [
              Tab(text: strings.feature('Förberedelse')),
              Tab(text: strings.feature('Live')),
              Tab(text: strings.feature('Analys')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MatchPlanEditor(eventId: eventId, calendar: calendar),
            later(
              'Live i Matchmodulen kommer i nästa steg. Tills dess loggar du '
              'matchen i Matchläge under aktiviteten.',
            ),
            later(
              'Analysen med speltid, statistik och händelser på planen kommer '
              'när livedelen är klar.',
            ),
          ],
        ),
      ),
    );
  }
}
