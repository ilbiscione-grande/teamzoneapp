part of '../../app/teamzone_app.dart';

// UX review, club functionary without a team: Home shows the work your club
// permissions give and the club's teams; Laget lists the teams, and a team
// opens read-only.

String _boardOfficeLabel(AppStrings strings, String office) =>
    strings.feature(switch (office) {
      'chair' => 'Ordförande',
      'treasurer' => 'Kassör',
      'secretary' => 'Sekreterare',
      'auditor' => 'Revisor',
      _ => 'Ledamot',
    });

/// "Ordförande · Revisor" for your board offices; null without any.
String? _boardOfficesLabel(AppStrings strings, List<String> offices) {
  if (offices.isEmpty) return null;
  const order = ['chair', 'treasurer', 'secretary', 'member', 'auditor'];
  final sorted = [...offices]
    ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
  return sorted.map((office) => _boardOfficeLabel(strings, office)).join(' · ');
}

/// "tis 21 okt. · 17:00" for a team's coming activity.
String _clubEventWhen(BuildContext context, ClubTeamEvent event) {
  final localizations = MaterialLocalizations.of(context);
  final start = event.startsAt.toLocal();
  // "tis 22 okt.": the short weekday, not a letter shared by tis and tor.
  final day = localizations.formatMediumDate(start);
  if (event.allDay) return day;
  return '$day · ${TimeOfDay.fromDateTime(start).format(context)}';
}

IconData _clubEventIcon(String type) => switch (type) {
  'match' => Icons.sports_soccer_outlined,
  'meeting' => Icons.groups_outlined,
  'activity' => Icons.celebration_outlined,
  _ => Icons.fitness_center_outlined,
};

void _openClubTeam(
  BuildContext context,
  ClubHomeTeam team,
  RosterServices? roster,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _ClubTeamPage(team: team, roster: roster),
    ),
  );
}

/// Home of a club context: the tasks, then the teams.
class _ClubHomeContent extends StatelessWidget {
  const _ClubHomeContent({
    required this.home,
    required this.contextValue,
    required this.roster,
    required this.onNavigate,
  });
  final ClubHome home;
  final TeamZoneContext contextValue;
  final RosterServices? roster;
  final ValueChanged<String> onNavigate;

  Widget _task(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
    int badge = 0,
  }) => Card(
    key: key,
    child: ListTile(
      leading: Badge.count(
        count: badge,
        isLabelVisible: badge > 0,
        child: Icon(icon),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onNavigate(route),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final board = home.board;
    final economy = home.economy;
    final members = home.members;
    final tasks = <Widget>[
      if (board != null)
        _task(
          context,
          key: const ValueKey('club-home-board'),
          icon: Icons.badge_outlined,
          title: strings.feature('Styrelse'),
          subtitle: board.pendingChanges > 0
              ? '${board.pendingChanges} ${strings.feature('mandatändringar väntar')}'
              : '${board.activeMandates} ${strings.feature('aktiva mandat')}',
          badge: board.pendingChanges,
          route: ProductRouteContract.board,
        ),
      if (economy != null)
        _task(
          context,
          key: const ValueKey('club-home-economy'),
          icon: Icons.account_balance_wallet_outlined,
          title: strings.feature('Ekonomi'),
          subtitle: economy.accounts == 0
              ? strings.feature('Inga kassor än')
              : economy.pendingEntries > 0
              ? '${economy.pendingEntries} ${strings.feature('poster väntar på attest')}'
              : '${economy.accounts} ${strings.feature('kassor')}',
          badge: economy.pendingEntries,
          route: ProductRouteContract.economy,
        ),
      if (members != null) ...[
        _task(
          context,
          key: const ValueKey('club-home-applications'),
          icon: Icons.how_to_reg_outlined,
          title: strings.feature('Medlemsansökningar'),
          subtitle: members.pendingApplications > 0
              ? '${members.pendingApplications} ${strings.feature('väntar på beslut')}'
              : strings.feature('Inga väntande'),
          badge: members.pendingApplications,
          route: ProductRouteContract.teamApplications(),
        ),
        _task(
          context,
          key: const ValueKey('club-home-team-requests'),
          icon: Icons.approval_outlined,
          title: strings.feature('Förfrågningar om nya lag'),
          subtitle: members.pendingTeamRequests > 0
              ? '${members.pendingTeamRequests} ${strings.feature('väntar på beslut')}'
              : strings.feature('Inga väntande'),
          badge: members.pendingTeamRequests,
          route: _clubTeamRequestsRoute,
        ),
      ],
      if (contextValue.can('club.memberships.manage'))
        _task(
          context,
          key: const ValueKey('club-home-permissions'),
          icon: Icons.admin_panel_settings_outlined,
          title: strings.feature('Klubbens behörigheter'),
          subtitle: strings.feature(
            'Vem som sköter publicering, medlemmar, anslag och domare',
          ),
          route: ProductRouteContract.clubPermissions,
        ),
      if (home.publication case final publication?)
        _task(
          context,
          key: const ValueKey('club-home-team-pages'),
          icon: Icons.public_outlined,
          title: strings.feature('Ansökningar om lagsida'),
          subtitle: publication.pendingTeamPages > 0
              ? '${publication.pendingTeamPages} ${strings.feature('väntar på beslut')}'
              : strings.feature('Inga väntande'),
          badge: publication.pendingTeamPages,
          route: ProductRouteContract.publication,
        ),
      if (contextValue.can('club.referees.manage'))
        _task(
          context,
          key: const ValueKey('club-home-referees'),
          icon: Icons.sports_outlined,
          title: strings.feature('Domartillsättning'),
          subtitle: strings.feature('Klubbens matcher och domare'),
          route: _refereeBoardRoute,
        ),
      if (home.canAnnounce)
        _task(
          context,
          key: const ValueKey('club-home-announce'),
          icon: Icons.campaign_outlined,
          title: strings.feature('Skicka anslag'),
          subtitle: strings.feature('Till ledare, spelare eller hela klubben'),
          route: ProductRouteContract.inboxAnnouncement(),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...tasks,
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            strings.feature('Klubbens lag'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        _ClubTeamsList(teams: home.teams, roster: roster),
      ],
    );
  }
}

/// The club's teams with their size and next activity; each opens.
class _ClubTeamsList extends StatelessWidget {
  const _ClubTeamsList({required this.teams, required this.roster});
  final List<ClubHomeTeam> teams;
  final RosterServices? roster;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (teams.isEmpty) {
      return Text(strings.feature('Klubben har inga lag än.'));
    }
    return Card(
      child: Column(
        children: [
          for (final team in teams)
            ListTile(
              key: ValueKey('club-team-${team.teamId}'),
              leading: const Icon(Icons.shield_outlined),
              title: Text(team.name),
              subtitle: Text(
                [
                  '${team.memberCount} ${strings.feature('lagmedlemmar')}',
                  if (team.upcoming.firstOrNull case final next?)
                    '${strings.feature('Nästa')}: ${next.title} ${_clubEventWhen(context, next)}',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openClubTeam(context, team, roster),
            ),
        ],
      ),
    );
  }
}

/// Laget in a club context: the club's teams instead of "not in a team".
/// It also opens the club admin's queues that team links ask for.
class _ClubTeamsSurface extends StatefulWidget {
  const _ClubTeamsSurface({
    required this.contextValue,
    required this.clubHome,
    required this.roster,
    required this.membership,
    required this.initialAction,
    required this.fallback,
  });
  final TeamZoneContext contextValue;
  final ClubHomeServices clubHome;
  final RosterServices roster;
  final MembershipServices membership;
  final String? initialAction;

  /// Shown when the club's teams cannot be listed.
  final Widget fallback;

  @override
  State<_ClubTeamsSurface> createState() => _ClubTeamsSurfaceState();
}

class _ClubTeamsSurfaceState extends State<_ClubTeamsSurface> {
  late Future<ClubHome?> _home = _load();
  bool _openedAction = false;

  Future<ClubHome?> _load() async {
    try {
      return await widget.clubHome.loadClubHome(widget.contextValue.id);
    } catch (error) {
      AppErrors.caught('club_home_surface._ClubTeamsSurface', error);
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openAction());
  }

  @override
  void didUpdateWidget(covariant _ClubTeamsSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) {
      setState(() => _home = _load());
    }
    if (oldWidget.initialAction != widget.initialAction) {
      _openedAction = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAction());
    }
  }

  void _reload() {
    if (mounted) setState(() => _home = _load());
  }

  /// From Home's cards: the membership applications or team requests.
  Future<void> _openAction() async {
    if (_openedAction || !mounted) return;
    if (!widget.contextValue.can('club.memberships.manage')) return;
    final action = widget.initialAction;
    if (action == 'applications') {
      _openedAction = true;
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _MembershipReviewSheet(
          contextValue: widget.contextValue,
          membership: widget.membership,
          onApproved: () async => _reload(),
        ),
      );
    } else if (action == 'team-requests') {
      _openedAction = true;
      await _showTeamCreationRequests(
        context: context,
        activeContext: widget.contextValue,
        membership: widget.membership,
        onContextsChanged: () async {},
        onRequestsChanged: _reload,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<ClubHome?>(
      future: _home,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(
            label: strings.feature('Laddar klubbens lag'),
          );
        }
        final home = snapshot.data;
        if (home == null) return widget.fallback;
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _home;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                strings.feature('Klubbens lag'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                strings.feature(
                  'Du har inget eget lag. Här ser du klubbens lag och vad som är på gång.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _ClubTeamsList(teams: home.teams, roster: widget.roster),
            ],
          ),
        );
      },
    );
  }
}

/// A club team, read-only: picture, presentation, leaders and the coming
/// activities (what, when, where).
class _ClubTeamPage extends StatefulWidget {
  const _ClubTeamPage({required this.team, required this.roster});
  final ClubHomeTeam team;
  final RosterServices? roster;

  @override
  State<_ClubTeamPage> createState() => _ClubTeamPageState();
}

class _ClubTeamPageState extends State<_ClubTeamPage> {
  late final Future<TeamOverview?> _overview = _load();

  Future<TeamOverview?> _load() async {
    final roster = widget.roster;
    if (roster == null) return null;
    try {
      return await roster
          .getTeamOverview(teamId: widget.team.teamId)
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      AppErrors.caught('club_home_surface._ClubTeamPage', error);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final team = widget.team;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: theme.textTheme.titleLarge),
    );
    return Scaffold(
      appBar: AppBar(title: Text(team.name)),
      body: FutureBuilder<TeamOverview?>(
        future: _overview,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AppLoadingIndicator(
              label: strings.feature('Laddar lagöversikt'),
            );
          }
          final overview = snapshot.data;
          return ListView(
            key: ValueKey('club-team-page-${team.teamId}'),
            padding: const EdgeInsets.all(24),
            children: [
              if (overview != null) ...[
                _TeamImage(value: overview),
                const SizedBox(height: 20),
              ],
              Text(team.name, style: theme.textTheme.headlineMedium),
              Text(
                [
                  ?overview?.clubName,
                  '${team.memberCount} ${strings.feature('lagmedlemmar')}',
                ].join(' · '),
              ),
              section(strings.feature('Kommande')),
              if (team.upcoming.isEmpty)
                Text(strings.feature('Inga kommande aktiviteter.'))
              else
                Card(
                  child: Column(
                    children: [
                      for (final event in team.upcoming)
                        ListTile(
                          leading: Icon(_clubEventIcon(event.eventType)),
                          title: Text(event.title),
                          subtitle: Text(
                            [
                              _clubEventWhen(context, event),
                              ?event.locationName,
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
                ),
              if (overview != null) ...[
                section(strings.feature('Om laget')),
                Text(
                  overview.summary ??
                      strings.feature(
                        'Ingen laginformation har publicerats ännu.',
                      ),
                ),
                section(strings.feature('Ledare')),
                if (overview.leaders.isEmpty)
                  Text(strings.feature('Inga ledare visas ännu.'))
                else
                  for (final leader in overview.leaders)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(leader.displayName),
                    ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// DR-01: the coming meetings of your club role on a team context's Home,
/// read from your club context's calendar.
class _ClubMeetingsSection extends StatefulWidget {
  const _ClubMeetingsSection({
    required this.clubContextId,
    required this.calendar,
    required this.onNavigate,
  });
  final String clubContextId;
  final CalendarServices calendar;
  final ValueChanged<String> onNavigate;

  @override
  State<_ClubMeetingsSection> createState() => _ClubMeetingsSectionState();
}

class _ClubMeetingsSectionState extends State<_ClubMeetingsSection> {
  late Future<List<CalendarEventSummary>> _meetings = _load();

  Future<List<CalendarEventSummary>> _load() async {
    final now = DateTime.now();
    try {
      final events = await widget.calendar
          .listCalendar(
            contextIds: [widget.clubContextId],
            from: now,
            to: now.add(const Duration(days: 60)),
          )
          .timeout(const Duration(seconds: 15));
      return events
          .where(
            (event) =>
                event.type == 'meeting' &&
                event.state != 'cancelled' &&
                event.endsAt.isAfter(now),
          )
          .take(3)
          .toList(growable: false);
    } catch (error) {
      AppErrors.caught('club_home_surface._ClubMeetingsSection', error);
      return const [];
    }
  }

  @override
  void didUpdateWidget(covariant _ClubMeetingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clubContextId != widget.clubContextId) _meetings = _load();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<CalendarEventSummary>>(
        future: _meetings,
        builder: (context, snapshot) {
          final meetings = snapshot.data ?? const <CalendarEventSummary>[];
          // Nothing to show is shown as nothing.
          if (meetings.isEmpty) return const SizedBox.shrink();
          final strings = AppStrings.of(context);
          return Column(
            key: const ValueKey('club-meetings'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text(
                  strings.feature('Klubbens möten'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Card(
                child: Column(
                  children: [
                    for (final meeting in meetings)
                      ListTile(
                        key: ValueKey('club-meeting-${meeting.id}'),
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(meeting.title),
                        subtitle: Text(
                          _clubEventWhen(
                            context,
                            ClubTeamEvent(
                              title: meeting.title,
                              eventType: meeting.type,
                              startsAt: meeting.startsAt,
                              endsAt: meeting.endsAt,
                              allDay: meeting.allDay,
                            ),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onNavigate(
                          ProductRouteContract.calendarEvent(meeting.id),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      );
}
