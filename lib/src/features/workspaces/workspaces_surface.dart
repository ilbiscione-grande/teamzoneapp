part of '../../app/teamzone_app.dart';

/// Arbetsytor: the leaders' hub for the modules (decision package 11):
/// Match, Team Development Plan, Träning and IDP. It opens what already
/// exists and lists the modules with the club's access to them, from the
/// server; a module still being built says so rather than pretending.
class _WorkspacesSurface extends StatefulWidget {
  const _WorkspacesSurface({
    required this.contextValue,
    required this.modules,
    required this.calendar,
    required this.onNavigate,
  });
  final TeamZoneContext contextValue;
  final ModuleServices modules;
  final CalendarServices calendar;
  final ValueChanged<String> onNavigate;

  @override
  State<_WorkspacesSurface> createState() => _WorkspacesSurfaceState();
}

class _WorkspacesSurfaceState extends State<_WorkspacesSurface> {
  late Future<TeamModules> _modules = _load();

  Future<TeamModules> _load() {
    final teamId = widget.contextValue.teamId;
    return teamId == null
        ? Future.value(const TeamModules())
        : widget.modules.getTeamModules(teamId: teamId);
  }

  @override
  void didUpdateWidget(covariant _WorkspacesSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.teamId != widget.contextValue.teamId) {
      _modules = _load();
    }
  }

  static const _icons = {
    'module.match_workspace': Icons.sports_soccer_outlined,
    'module.team_development': Icons.event_note_outlined,
    'module.training': Icons.fitness_center_outlined,
    'module.player_development': Icons.trending_up_outlined,
  };

  /// The modules built so far open their page; the rest are still being built.
  void Function()? _opener(ModuleInfo module) {
    final teamId = widget.contextValue.teamId;
    if (!module.open || teamId == null) return null;
    return switch (module.key) {
      'module.match_workspace' => () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              _MatchWorkspacePage(teamId: teamId, calendar: widget.calendar),
        ),
      ),
      _ => null,
    };
  }

  /// The club's access in words: open in beta, bought, read-only once
  /// ended, or not included.
  static String _status(ModuleInfo module) => switch (module.access) {
    'write' when module.beta => 'Beta',
    'write' => 'Ingår',
    'read_only' => 'Skrivskyddad',
    _ => 'Ingår inte',
  };

  @override
  Widget build(BuildContext context) {
    final contextValue = widget.contextValue;
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          strings.destination(ProductRouteContract.workspaces),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          strings.feature(
            'Ledarnas verktyg samlade på ett ställe. Fler arbetsytor kommer.',
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            key: const Key('workspace-development'),
            leading: const Icon(Icons.trending_up_outlined),
            title: Text(strings.destination(ProductRouteContract.development)),
            subtitle: Text(strings.feature('Spelarnas utveckling och mål')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.onNavigate(ProductRouteContract.development),
          ),
        ),
        if (contextValue.can('event.manage') ||
            contextValue.can('event.attendance.manage'))
          Card(
            child: ListTile(
              key: const Key('workspace-statistics'),
              leading: const Icon(Icons.query_stats_outlined),
              title: Text(strings.feature('Lagstatistik')),
              subtitle: Text(
                strings.feature('Närvaro, svar och aktiviteter över tid'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  widget.onNavigate(ProductRouteContract.teamStatistics),
            ),
          ),
        const SizedBox(height: 24),
        Text(strings.feature('Moduler'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        FutureBuilder<TeamModules>(
          future: _modules,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(strings.feature('Modulerna kunde inte hämtas.'));
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            // The app's own modules; a web tool's link shows where it is used.
            final modules = [
              for (final module in snapshot.data!.modules)
                if (module.key.startsWith('module.')) module,
            ];
            return Column(
              children: [
                for (final module in modules)
                  ListTile(
                    key: Key('workspace-module-${module.key}'),
                    enabled: _opener(module) != null,
                    onTap: _opener(module),
                    leading: Icon(_icons[module.key] ?? Icons.widgets_outlined),
                    title: Text(module.title),
                    subtitle: Text(
                      _opener(module) != null
                          ? module.description
                          : '${module.description}. ${strings.feature('Byggs nu.')}',
                    ),
                    trailing: Chip(
                      label: Text(strings.feature(_status(module))),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
