part of '../../app/teamzone_app.dart';

/// One part of a module's own navigation.
class _ModuleSection {
  const _ModuleSection({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });
  final String label;
  final IconData icon, selectedIcon;
  final WidgetBuilder builder;
}

/// A module as its own app (decision package 11): it opens over TeamZone's
/// shell, full screen, with the module's name and accent color, its own
/// navigation (a bar on phones, a rail on wide screens) and a way back to
/// TeamZone. Pages opened inside it keep its look through [_ModuleScope].
class _ModuleShell extends StatefulWidget {
  const _ModuleShell({
    required this.title,
    required this.icon,
    required this.seed,
    required this.sections,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color seed;
  final List<_ModuleSection> sections;

  /// Opens a module over the whole app, above TeamZone's shell.
  static Future<void> open(BuildContext context, _ModuleShell shell) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => shell, fullscreenDialog: true),
      );

  /// The module's accent colors per module key.
  static const seeds = {
    'module.match_workspace': Color(0xFF1B5E9E),
    'module.team_development': Color(0xFF6A4C93),
    'module.training': Color(0xFFB8562B),
    'module.player_development': Color(0xFF2E7D5B),
  };

  /// The module's theme: TeamZone's look in the module's accent color.
  static ThemeData themeFor(BuildContext context, Color seed) {
    final base = Theme.of(context);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: base.brightness,
      ),
    );
  }

  @override
  State<_ModuleShell> createState() => _ModuleShellState();
}

class _ModuleShellState extends State<_ModuleShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = _ModuleShell.themeFor(context, widget.seed);
    final sections = widget.sections;
    final wide = AppBreakpoints.usesNavigationRail(
      MediaQuery.sizeOf(context).width,
    );
    final body = KeyedSubtree(
      key: ValueKey('module-section-$_index'),
      child: Builder(builder: sections[_index].builder),
    );
    return _ModuleScope(
      theme: theme,
      child: Theme(
        data: theme,
        child: Scaffold(
          appBar: _ModuleHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            icon: widget.icon,
            seed: widget.seed,
          ),
          body: wide && sections.length > 1
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      destinations: [
                        for (final section in sections)
                          NavigationRailDestination(
                            icon: Icon(section.icon),
                            selectedIcon: Icon(section.selectedIcon),
                            label: Text(strings.feature(section.label)),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: !wide && sections.length > 1
              ? NavigationBar(
                  key: const Key('module-navigation'),
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    for (final section in sections)
                      NavigationDestination(
                        icon: Icon(section.icon),
                        selectedIcon: Icon(section.selectedIcon),
                        label: strings.feature(section.label),
                      ),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

/// The module's header: its accent gradient, name and team, and the way
/// back to TeamZone.
class _ModuleHeader extends StatelessWidget implements PreferredSizeWidget {
  const _ModuleHeader({
    required this.title,
    required this.icon,
    required this.seed,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color seed;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AppBar(
      toolbarHeight: 64,
      foregroundColor: Colors.white,
      backgroundColor: seed,
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.lerp(seed, Colors.white, 0.18)!, seed],
          ),
        ),
      ),
      leading: IconButton(
        key: const Key('module-exit'),
        tooltip: strings.feature('Tillbaka till TeamZone'),
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.feature(title),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inside a module: its theme, so pages opened from it keep the module's
/// look; outside one (as from an event in TeamZone) [push] opens the page
/// as it is.
class _ModuleScope extends InheritedWidget {
  const _ModuleScope({required this.theme, required super.child});
  final ThemeData theme;

  static Future<T?> push<T>(
    BuildContext context,
    WidgetBuilder builder, {
    Color? seed,
  }) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ModuleScope>();
    final theme =
        scope?.theme ??
        (seed == null ? null : _ModuleShell.themeFor(context, seed));
    return Navigator.of(context).push(
      MaterialPageRoute<T>(
        builder: (routeContext) => theme == null
            ? builder(routeContext)
            : _ModuleScope(
                theme: theme,
                child: Theme(
                  data: theme,
                  child: Builder(builder: builder),
                ),
              ),
      ),
    );
  }

  @override
  bool updateShouldNotify(_ModuleScope oldWidget) => theme != oldWidget.theme;
}
