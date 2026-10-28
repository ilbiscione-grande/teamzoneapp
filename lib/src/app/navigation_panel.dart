part of 'teamzone_app.dart';

/// A small label over a group of rows: "HUVUDMENY", "VERKTYG", ...
class _NavPanelSection extends StatelessWidget {
  const _NavPanelSection(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 16, 16, 6),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppPalette.of(context).muted,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
      ),
    ),
  );
}

/// A count on a row: a small red circle.
class _NavPanelCount extends StatelessWidget {
  const _NavPanelCount(this.count);
  final int count;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.lerp(palette.danger, Colors.white, .3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xFF3A0D0D),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One row (icon + label) inside the navigation panel, shared by the primary
/// destinations, tools and the capability-gated admin items. The active
/// page sits on a soft accent pill in the accent color.
class _NavPanelRow extends StatelessWidget {
  const _NavPanelRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.trailing,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: trailing,
          selected: selected,
          onTap: onTap,
          dense: true,
          minTileHeight: 48,
          iconColor: theme.colorScheme.onSurface,
          textColor: theme.colorScheme.onSurface,
          selectedColor: palette.accent,
          selectedTileColor: palette.accentSoft,
          titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.tile),
            side: selected && dark
                ? BorderSide(color: palette.accent.withValues(alpha: .35))
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// The top of the panel: the profile picture as a toned backdrop, the
/// picture itself in an accent ring with an edit badge, name and roles.
class _NavPanelProfileHeader extends StatelessWidget {
  const _NavPanelProfileHeader({
    required this.profile,
    required this.contextValue,
    required this.ownSummary,
    required this.onOpenOwnProfile,
  });
  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final Future<_OwnSummary> ownSummary;
  final VoidCallback onOpenOwnProfile;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = AppPalette.of(context);
    final dark = theme.brightness == Brightness.dark;
    // A short window (a laptop, a phone on its side) gets a smaller header.
    final compact = MediaQuery.sizeOf(context).height < 760;
    return FutureBuilder<_OwnSummary>(
      future: ownSummary,
      builder: (context, snapshot) {
        final avatar = snapshot.data?.avatar;
        final name = snapshot.data?.name ?? profile.displayName;
        return Stack(
          children: [
            Positioned.fill(
              child: avatar == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [palette.accentSoft, colors.surface],
                        ),
                      ),
                    )
                  : Image.network(
                      avatar,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      opacity: AlwaysStoppedAnimation(dark ? .45 : .6),
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
            // Tones the picture toward the accent and fades it into the
            // panel, so the name stays readable.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .55, 1],
                    colors: [
                      palette.accent.withValues(alpha: dark ? .25 : .18),
                      colors.surface.withValues(alpha: dark ? .7 : .55),
                      colors.surface,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Semantics(
                  button: true,
                  label: strings.feature('Min profil'),
                  child: InkWell(
                    key: const Key('drawer-own-profile'),
                    onTap: onOpenOwnProfile,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        compact ? 8 : 32,
                        16,
                        compact ? 12 : 20,
                      ),
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.surface,
                                  border: Border.all(
                                    color: palette.accent,
                                    width: 3,
                                  ),
                                ),
                                child: CircleAvatar(
                                  key: const Key('drawer-own-avatar'),
                                  radius: compact ? 30 : 46,
                                  backgroundColor: palette.accentSoft,
                                  foregroundColor: palette.accent,
                                  backgroundImage: avatar == null
                                      ? null
                                      : NetworkImage(avatar),
                                  child: avatar == null
                                      ? Icon(
                                          Icons.person,
                                          size: compact ? 32 : 48,
                                        )
                                      : null,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 2,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.surface,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.edit,
                                    size: 15,
                                    color: colors.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 8 : 14),
                          Text(
                            name.trim().isEmpty
                                ? strings.feature('Min profil')
                                : name,
                            key: const Key('drawer-own-name'),
                            textAlign: TextAlign.center,
                            // A login address as the name stays on one line.
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (compact
                                        ? theme.textTheme.titleLarge
                                        : theme.textTheme.headlineSmall)
                                    ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            snapshot.data?.title ??
                                _contextRolesLabel(strings, contextValue),
                            key: const Key('drawer-own-roles'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colors.onSurface.withValues(alpha: .75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shared content for the mobile navigation drawer (opened via the app bar's
/// avatar) and the permanent tablet/desktop sidebar: profile, team switcher,
/// the main destinations, tools, capability-gated admin links, and
/// settings/sign-out at the bottom. Follows the app's light/dark theme.
class _AppNavigationPanel extends StatelessWidget {
  const _AppNavigationPanel({
    required this.profile,
    required this.contextValue,
    required this.contexts,
    required this.currentLocation,
    required this.onNavigate,
    required this.onContextChanged,
    required this.membership,
    required this.onContextsChanged,
    required this.onTeamCreated,
    required this.pendingTeamRequests,
    required this.onTeamRequestsChanged,
    required this.onSignOut,
    required this.closeDrawer,
    required this.onOpenOwnProfile,
    required this.ownSummary,
    this.refereeSummary,
    this.onOpenRefereeBoard,
  });

  /// REF-02: the clubs where the person is domaransvarig or pays referees.
  final Future<RefereeSummary>? refereeSummary;
  final void Function(
    ({String id, String name, bool canManage, bool canPay, int pendingReports})
    club,
  )?
  onOpenRefereeBoard;

  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final String currentLocation;
  final ValueChanged<String> onNavigate;
  final ValueChanged<TeamZoneContext> onContextChanged;
  final MembershipServices membership;
  final Future<void> Function() onContextsChanged;
  final Future<void> Function(String teamId) onTeamCreated;
  final Future<int> pendingTeamRequests;
  final VoidCallback onTeamRequestsChanged;
  final Future<void> Function() onSignOut;
  final VoidCallback onOpenOwnProfile;
  final Future<_OwnSummary> ownSummary;
  // Null on tablet/desktop, where this panel is a permanent sidebar rather
  // than a dismissible drawer. Closes via the Scaffold's own ScaffoldState
  // (see the GlobalKey in _ProductShellState), not Navigator.pop: a
  // Scaffold's Drawer is not a route on the ambient Navigator, so popping it
  // that way silently did nothing — found via a physical walkthrough
  // ("draget stängs inte när man trycker på en meny-rad").
  final VoidCallback? closeDrawer;

  void _go(String path) {
    onNavigate(path);
    closeDrawer?.call();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final hasAdminLinks =
        contextValue.can('club.billing.manage') ||
        _hasEconomyCapability(contextValue) ||
        _hasBoardCapability(contextValue);
    final isLeader =
        contextValue.rolePackage == 'leader' ||
        contextValue.rolePackages.contains('leader');
    final hasReferees = refereeSummary != null && onOpenRefereeBoard != null;
    const chevron = Icon(Icons.chevron_right);
    // A short window gets a tighter footer, so the menu rows keep room.
    final compact = MediaQuery.sizeOf(context).height < 760;
    final divider = Divider(
      height: 17,
      indent: 24,
      endIndent: 24,
      color: theme.colorScheme.outlineVariant,
    );
    // A Material, not a ColoredBox: the rows paint their selected pill on it.
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile and team switcher scroll with the rows, so a short
          // window still shows the menu.
          Expanded(
            child: ListView(
              key: const Key('app-navigation-panel-list'),
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                _NavPanelProfileHeader(
                  profile: profile,
                  contextValue: contextValue,
                  ownSummary: ownSummary,
                  onOpenOwnProfile: onOpenOwnProfile,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      side: theme.brightness == Brightness.dark
                          ? BorderSide(color: theme.colorScheme.outlineVariant)
                          : BorderSide.none,
                    ),
                    elevation: theme.brightness == Brightness.dark ? 0 : 3,
                    child: InkWell(
                      onTap: () => _showContextPicker(
                        context: context,
                        contexts: contexts,
                        activeContext: contextValue,
                        pendingTeamRequests: pendingTeamRequests,
                        onContextChanged: onContextChanged,
                        membership: membership,
                        onContextsChanged: onContextsChanged,
                        onTeamCreated: onTeamCreated,
                        onTeamRequestsChanged: onTeamRequestsChanged,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 28,
                              color: palette.accent,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: FutureBuilder<int>(
                                future: pendingTeamRequests,
                                initialData: 0,
                                builder: (context, snapshot) => Badge.count(
                                  count: snapshot.data ?? 0,
                                  isLabelVisible: (snapshot.data ?? 0) > 0,
                                  child: _ContextTwoLineLabel(
                                    contextValue: contextValue,
                                  ),
                                ),
                              ),
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _NavPanelSection(strings.feature('Huvudmeny')),
                for (final path in _drawerMainOrder)
                  _NavPanelRow(
                    icon: _destinationFor(path).icon,
                    label: strings.destination(path),
                    selected: currentLocation.startsWith(path),
                    onTap: () => _go(path),
                  ),
                if (isLeader || hasReferees) ...[
                  divider,
                  _NavPanelSection(strings.feature('Verktyg')),
                ],
                if (isLeader)
                  _NavPanelRow(
                    icon: _destinationFor(ProductRouteContract.workspaces).icon,
                    label: strings.destination(ProductRouteContract.workspaces),
                    selected: currentLocation.startsWith(
                      ProductRouteContract.workspaces,
                    ),
                    onTap: () => _go(ProductRouteContract.workspaces),
                  ),
                // REF-02: one row for the active club's referees.
                if (hasReferees)
                  FutureBuilder<RefereeSummary>(
                    future: refereeSummary,
                    builder: (context, snapshot) {
                      final club = snapshot.data?.coordinatorClubs
                          .where((item) => item.id == contextValue.clubId)
                          .firstOrNull;
                      if (club == null) return const SizedBox.shrink();
                      return _NavPanelRow(
                        key: const Key('drawer-referee-board'),
                        icon: club.canManage
                            ? Icons.assignment_ind_outlined
                            : Icons.payments_outlined,
                        label: strings.feature(
                          club.canManage
                              ? 'Domartillsättning'
                              : 'Domarersättning',
                        ),
                        trailing: club.canManage && club.pendingReports > 0
                            ? _NavPanelCount(club.pendingReports)
                            : null,
                        onTap: () => onOpenRefereeBoard!(club),
                      );
                    },
                  ),
                if (hasAdminLinks) ...[
                  divider,
                  _NavPanelSection(strings.feature('Administration')),
                  if (contextValue.can('club.billing.manage'))
                    _NavPanelRow(
                      icon: Icons.payments_outlined,
                      label: strings.feature('Abonnemang'),
                      trailing: chevron,
                      onTap: () => _go('/billing'),
                    ),
                  if (_hasEconomyCapability(contextValue))
                    _NavPanelRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: strings.feature('Ekonomi'),
                      trailing: chevron,
                      onTap: () => _go('/economy'),
                    ),
                  if (_hasBoardCapability(contextValue))
                    _NavPanelRow(
                      icon: Icons.badge_outlined,
                      label: strings.feature('Styrelse'),
                      trailing: chevron,
                      onTap: () => _go('/board'),
                    ),
                ],
              ],
            ),
          ),
          divider,
          SafeArea(
            top: false,
            child: Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurface,
                          ),
                          onPressed: () => _go(ProductRouteContract.settings),
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(strings.feature('Inställningar')),
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        indent: 10,
                        endIndent: 10,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurface,
                          ),
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout),
                          label: Text(strings.signOut),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 2 : 10),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Team'),
                      TextSpan(
                        text: 'Zone',
                        style: TextStyle(color: palette.accent),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  semanticsLabel: 'TeamZone',
                  style:
                      (compact
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: compact ? 8 : 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
