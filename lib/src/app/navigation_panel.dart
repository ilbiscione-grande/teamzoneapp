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
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .75),
        fontWeight: FontWeight.w700,
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
      decoration: BoxDecoration(
        color: Color.lerp(palette.danger, Colors.white, .3),
        borderRadius: BorderRadius.circular(12),
      ),
      // widthFactor 1: a plain alignment would stretch the pill across the
      // row and squeeze the label into one letter per line.
      child: Center(
        widthFactor: 1,
        child: Text(
          '$count',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF3A0D0D),
            fontWeight: FontWeight.w700,
          ),
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
          selectedTileColor: theme.brightness == Brightness.dark
              ? Color.lerp(theme.colorScheme.surface, palette.accent, .2)
              : palette.accentSoft,
          titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.tile),
          ),
        ),
      ),
    );
  }
}

/// Faint tactics-board marks (players, arrows, a centre circle) behind the
/// profile header.
class _NavPanelPitchPainter extends CustomPainter {
  const _NavPanelPitchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    Offset at(double x, double y) => Offset(size.width * x, size.height * y);
    void cross(Offset c) {
      const r = 6.0;
      canvas.drawLine(c + const Offset(-r, -r), c + const Offset(r, r), stroke);
      canvas.drawLine(c + const Offset(-r, r), c + const Offset(r, -r), stroke);
    }

    void arrow(Offset from, Offset control, Offset to) {
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
      // Dashed curve.
      for (final metric in path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 10) {
          canvas.drawPath(metric.extractPath(d, d + 5), stroke);
        }
        final end = metric.getTangentForOffset(metric.length);
        if (end != null) {
          final back = -end.vector * 8;
          final side = Offset(-back.dy, back.dx) * .6;
          canvas.drawLine(end.position, end.position + back + side, stroke);
          canvas.drawLine(end.position, end.position + back - side, stroke);
        }
      }
    }

    canvas.drawCircle(at(.5, .42), size.width * .2, stroke);
    canvas.drawLine(at(0, .42), at(.22, .42), stroke);
    canvas.drawLine(at(.78, .42), at(1, .42), stroke);
    canvas.drawCircle(at(.12, .2), 7, stroke);
    canvas.drawCircle(at(.86, .62), 7, stroke);
    canvas.drawCircle(at(.18, .7), 7, stroke);
    cross(at(.3, .1));
    cross(at(.72, .14));
    cross(at(.9, .3));
    cross(at(.08, .5));
    arrow(at(.14, .26), at(.2, .05), at(.36, .08));
    arrow(at(.66, .2), at(.8, .02), at(.92, .22));
    arrow(at(.2, .66), at(.06, .58), at(.1, .42));
    arrow(at(.82, .56), at(.96, .48), at(.88, .34));
  }

  @override
  bool shouldRepaint(_NavPanelPitchPainter old) => old.color != color;
}

/// The top of the panel: the picture in an accent ring with an edit badge,
/// name, roles and the team switcher, on a soft accent wash with faint
/// tactics marks.
class _NavPanelProfileHeader extends StatelessWidget {
  const _NavPanelProfileHeader({
    required this.profile,
    required this.contextValue,
    required this.ownSummary,
    required this.onOpenOwnProfile,
    required this.teamSwitcher,
  });
  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final Future<_OwnSummary> ownSummary;
  final VoidCallback onOpenOwnProfile;
  final Widget teamSwitcher;

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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .7, 1],
                    colors: dark
                        ? [
                            Color.lerp(colors.surface, palette.accent, .2)!,
                            Color.lerp(colors.surface, palette.accent, .06)!,
                            colors.surface,
                          ]
                        : [
                            Color.lerp(
                              palette.accentSoft,
                              palette.accent,
                              .12,
                            )!,
                            palette.accentSoft.withValues(alpha: .5),
                            colors.surface,
                          ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _NavPanelPitchPainter(
                  palette.accent.withValues(alpha: dark ? .16 : .12),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compact ? 8 : 28,
                    16,
                    compact ? 8 : 12,
                  ),
                  child: Column(
                    children: [
                      Semantics(
                        button: true,
                        label: strings.feature('Min profil'),
                        child: InkWell(
                          key: const Key('drawer-own-profile'),
                          onTap: onOpenOwnProfile,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
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
                                          width: 4,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        key: const Key('drawer-own-avatar'),
                                        radius: compact ? 30 : 50,
                                        backgroundColor: palette.accentSoft,
                                        foregroundColor: palette.accent,
                                        backgroundImage: avatar == null
                                            ? null
                                            : NetworkImage(avatar),
                                        child: avatar == null
                                            ? Icon(
                                                Icons.person,
                                                size: compact ? 32 : 52,
                                              )
                                            : null,
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 2,
                                      child: Container(
                                        width: 32,
                                        height: 32,
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
                                          size: 16,
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
                                  // A login address as the name stays on one
                                  // line.
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      (compact
                                              ? theme.textTheme.titleLarge
                                              : theme.textTheme.headlineSmall)
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  snapshot.data?.title ??
                                      _contextRolesLabel(strings, contextValue),
                                  key: const Key('drawer-own-roles'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: colors.onSurface.withValues(
                                      alpha: .7,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 2 : 6),
                      teamSwitcher,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 0),
                  child: IconButton.filledTonal(
                    key: const Key('drawer-own-profile-button'),
                    tooltip: strings.feature('Min profil'),
                    style: IconButton.styleFrom(
                      backgroundColor: palette.accentSoft,
                      foregroundColor: colors.onSurface,
                    ),
                    onPressed: onOpenOwnProfile,
                    icon: const Icon(Icons.person),
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

/// The active team under the roles: shield, team, club and a chevron.
class _NavPanelTeamSwitcher extends StatelessWidget {
  const _NavPanelTeamSwitcher({
    required this.contextValue,
    required this.pendingTeamRequests,
    required this.onTap,
  });
  final TeamZoneContext contextValue;
  final Future<int> pendingTeamRequests;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final team = contextValue.teamName ?? contextValue.clubName;
    return InkWell(
      key: const Key('drawer-team-switcher'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: FutureBuilder<int>(
          future: pendingTeamRequests,
          initialData: 0,
          builder: (context, snapshot) => Badge.count(
            count: snapshot.data ?? 0,
            isLabelVisible: (snapshot.data ?? 0) > 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 24, color: palette.accent),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    team,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (contextValue.teamName != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      contextValue.clubName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(Icons.expand_more, size: 20),
              ],
            ),
          ),
        ),
      ),
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
                  teamSwitcher: _NavPanelTeamSwitcher(
                    contextValue: contextValue,
                    pendingTeamRequests: pendingTeamRequests,
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
                  ),
                ),
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
