part of '../../app/teamzone_app.dart';

// Klubb: the club administrator's work in one place (UX review, lucka 5).
// Before, it was spread over Home, the team switcher, the quick actions,
// Settings → Klubb and the side menu. Everything here opens the same sheets
// and pages as before; nothing new is decided on the server. Permissions are
// listed as they are and not widened (see permissions-review.md).

/// Fees are handled by club admin and treasurer (club-members-and-fees.md);
/// the treasurer's economy.manage counts only in the club's own context.
bool _canHandleClubFees(TeamZoneContext context) =>
    context.can('club.memberships.manage') ||
    (context.teamId == null && context.can('economy.manage'));

/// The club's own context (no team) for [active]'s club, if you have one.
TeamZoneContext? _clubContextFor(
  TeamZoneContext active,
  List<TeamZoneContext> contexts,
) {
  if (active.teamId == null) return active;
  final club = contexts.where((item) => item.teamId == null);
  return club.where((item) => item.id == active.clubContextId).firstOrNull ??
      club.where((item) => item.clubId == active.clubId).firstOrNull;
}

class _ClubAdminSurface extends StatefulWidget {
  const _ClubAdminSurface({
    required this.contextValue,
    required this.contexts,
    required this.overview,
    required this.roster,
    required this.membership,
    required this.profileServices,
    required this.onNavigate,
    required this.onContextsChanged,
    required this.onTeamCreated,
    required this.onTeamRequestsChanged,
  });
  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final OverviewServices overview;
  final RosterServices roster;
  final MembershipServices membership;
  final ProfileServices profileServices;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onContextsChanged;
  final Future<void> Function(String teamId) onTeamCreated;
  final VoidCallback onTeamRequestsChanged;

  @override
  State<_ClubAdminSurface> createState() => _ClubAdminSurfaceState();
}

class _ClubAdminSurfaceState extends State<_ClubAdminSurface> {
  late Future<ClubHome?> _home = _load();

  /// The club's queues are the club context's; a team context would show
  /// only its own team's applications.
  TeamZoneContext get _clubContext =>
      _clubContextFor(widget.contextValue, widget.contexts) ??
      widget.contextValue;

  Future<ClubHome?> _load() async {
    final overview = widget.overview;
    final club = _clubContextFor(widget.contextValue, widget.contexts);
    if (club == null || overview is! ClubHomeServices) return null;
    try {
      return await (overview as ClubHomeServices).loadClubHome(club.id);
    } catch (error) {
      AppErrors.caught('club_admin_surface._load', error);
      return null;
    }
  }

  void _reload() => setState(() {
    _home = _load();
  });

  @override
  void didUpdateWidget(covariant _ClubAdminSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) _reload();
  }

  Future<void> _openApplications() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MembershipReviewSheet(
        contextValue: _clubContext,
        membership: widget.membership,
        onApproved: () async => _reload(),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openTeamRequests() async {
    await _showTeamCreationRequests(
      context: context,
      activeContext: _clubContext,
      membership: widget.membership,
      onContextsChanged: widget.onContextsChanged,
      onRequestsChanged: () {
        widget.onTeamRequestsChanged();
        if (mounted) _reload();
      },
    );
  }

  void _openTeams(List<ClubHomeTeam> teams) {
    final strings = AppStrings.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(strings.feature('Klubbens lag'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [_ClubTeamsList(teams: teams, roster: widget.roster)],
          ),
        ),
      ),
    );
  }

  String _pending(AppStrings strings, int? count) => count == null
      ? strings.feature('Öppna kön')
      : count > 0
      ? '$count ${strings.feature('väntar på beslut')}'
      : strings.feature('Inga väntande');

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final contextValue = widget.contextValue;
    final title = strings.feature('Klubb');
    final admin = contextValue.can('club.memberships.manage');
    if (!admin && !_canHandleClubFees(contextValue)) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _StateCard(
            icon: Icons.domain_disabled_outlined,
            title: title,
            message: strings.feature(
              'Klubbsidan är för klubbens administratörer.',
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<ClubHome?>(
        future: _home,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final home = snapshot.data;
          final members = home?.members;
          final clubId = contextValue.clubId;
          final clubName = contextValue.clubName;
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _home;
            },
            child: ListView(
              key: const ValueKey('club-admin'),
              padding: const EdgeInsets.all(16),
              children: [
                Text(clubName, style: Theme.of(context).textTheme.titleLarge),
                if (loading) const LinearProgressIndicator(),
                if (admin)
                  _ClubAdminSection(
                    title: strings.feature('Att hantera'),
                    children: [
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-applications'),
                        icon: Icons.how_to_reg_outlined,
                        title: strings.feature('Medlemsansökningar'),
                        subtitle: _pending(
                          strings,
                          members?.pendingApplications,
                        ),
                        badge: members?.pendingApplications ?? 0,
                        onTap: _openApplications,
                      ),
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-team-requests'),
                        icon: Icons.approval_outlined,
                        title: strings.feature('Förfrågningar om nya lag'),
                        subtitle: _pending(
                          strings,
                          members?.pendingTeamRequests,
                        ),
                        badge: members?.pendingTeamRequests ?? 0,
                        onTap: _openTeamRequests,
                      ),
                      if (contextValue.can('publication.manage'))
                        _ClubAdminTile(
                          key: const ValueKey('club-admin-team-pages'),
                          icon: Icons.public_outlined,
                          title: strings.feature('Ansökningar om lagsida'),
                          subtitle: _pending(
                            strings,
                            home?.publication?.pendingTeamPages,
                          ),
                          badge: home?.publication?.pendingTeamPages ?? 0,
                          onTap: () => widget.onNavigate(
                            ProductRouteContract.publication,
                          ),
                        ),
                    ],
                  ),
                _ClubAdminSection(
                  title: strings.feature('Medlemmar'),
                  children: [
                    if (widget.membership
                        case final ClubRegisterServices register when admin)
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-register'),
                        icon: Icons.contacts_outlined,
                        title: strings.feature('Medlemsregister'),
                        subtitle: strings.feature(
                          'Alla i klubben, vem som är medlem och i vilken kategori',
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _ClubRegisterPage(
                              clubId: clubId,
                              clubName: clubName,
                              services: register,
                            ),
                          ),
                        ),
                      ),
                    if (widget.membership case final ClubFeesProvider fees
                        when _canHandleClubFees(contextValue))
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-fees'),
                        icon: Icons.payments_outlined,
                        title: strings.feature('Avgifter'),
                        subtitle: strings.feature(
                          'Medlemsavgifter och lagavgifter, med familjerabatt',
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _ClubFeeRoundsPage(
                              clubId: clubId,
                              teams: [
                                for (final team
                                    in home?.teams ?? const <ClubHomeTeam>[])
                                  (id: team.teamId, name: team.name),
                              ],
                              services: fees.clubFees,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (admin)
                  _ClubAdminSection(
                    title: strings.feature('Lag och uppdrag'),
                    children: [
                      if (home != null)
                        _ClubAdminTile(
                          key: const ValueKey('club-admin-teams'),
                          icon: Icons.groups_outlined,
                          title: strings.feature('Klubbens lag'),
                          subtitle:
                              '${home.teams.length} ${strings.feature('lag')}',
                          onTap: () => _openTeams(home.teams),
                        ),
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-create-team'),
                        icon: Icons.add_circle_outline,
                        title: strings.feature('Skapa ytterligare lag'),
                        subtitle: strings.feature(
                          'Lägg till ett nytt lag i den aktiva klubben.',
                        ),
                        onTap: () => _createTeamFromContextPicker(
                          context: context,
                          activeContext: _clubContext,
                          membership: widget.membership,
                          onTeamCreated: widget.onTeamCreated,
                        ),
                      ),
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-permissions'),
                        icon: Icons.admin_panel_settings_outlined,
                        title: strings.feature('Klubbens behörigheter'),
                        subtitle: strings.feature(
                          'Vem som sköter publicering, medlemmar, anslag och domare',
                        ),
                        onTap: () => widget.onNavigate(
                          ProductRouteContract.clubPermissions,
                        ),
                      ),
                      if (contextValue.can('club.referees.manage'))
                        _ClubAdminTile(
                          key: const ValueKey('club-admin-referees'),
                          icon: Icons.sports_outlined,
                          title: strings.feature('Domartillsättning'),
                          subtitle: strings.feature(
                            'Klubbens matcher och domare',
                          ),
                          onTap: () => widget.onNavigate(_refereeBoardRoute),
                        ),
                    ],
                  ),
                if (admin)
                  _ClubAdminSection(
                    title: strings.feature('Klubbens utseende och status'),
                    children: [
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-badge'),
                        icon: Icons.verified_user_outlined,
                        title: strings.feature('Klubbmärke'),
                        subtitle: strings.feature(
                          'Visas på klubbens medlemskort.',
                        ),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => _ClubBadgeDialog(
                            profile: widget.profileServices,
                            clubId: clubId,
                            clubName: clubName,
                          ),
                        ),
                      ),
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-colors'),
                        icon: Icons.palette_outlined,
                        title: strings.feature('Klubbens färger'),
                        subtitle: strings.feature(
                          'Färger på klubbens publika sidor.',
                        ),
                        onTap: () => showDialog<bool>(
                          context: context,
                          builder: (_) => _ClubColorsDialog(
                            profile: widget.profileServices,
                            clubId: clubId,
                            clubName: clubName,
                          ),
                        ),
                      ),
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-verification'),
                        icon: Icons.verified_outlined,
                        title: strings.feature('Klubbverifiering'),
                        subtitle: strings.feature(
                          'Se officiell status eller skicka underlag till TeamZone.',
                        ),
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => _ClubVerificationSheet(
                            clubId: clubId,
                            membership: widget.membership,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (contextValue.can('club.billing.manage'))
                  _ClubAdminSection(
                    title: strings.feature('Abonnemang'),
                    children: [
                      _ClubAdminTile(
                        key: const ValueKey('club-admin-billing'),
                        icon: Icons.payments_outlined,
                        title: strings.feature('Abonnemang'),
                        subtitle: strings.feature(
                          'Klubbens abonnemang i TeamZone',
                        ),
                        onTap: () =>
                            widget.onNavigate(ProductRouteContract.billing),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ClubAdminSection extends StatelessWidget {
  const _ClubAdminSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    ],
  );
}

class _ClubAdminTile extends StatelessWidget {
  const _ClubAdminTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Badge.count(
      count: badge,
      isLabelVisible: badge > 0,
      child: Icon(icon),
    ),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
