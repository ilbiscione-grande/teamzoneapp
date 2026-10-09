part of '../../app/teamzone_app.dart';

/// Arbetsytor: the leaders' hub for the coming modules (Träning, Match,
/// Utveckling, Planering …). A placeholder for now: it opens what already
/// exists and names what is planned, without pretending the rest works.
class _WorkspacesSurface extends StatelessWidget {
  const _WorkspacesSurface({
    required this.contextValue,
    required this.onNavigate,
  });
  final TeamZoneContext contextValue;
  final ValueChanged<String> onNavigate;

  static const _planned = [
    (
      Icons.fitness_center_outlined,
      'Träning',
      'Träningsplanering och övningsbank',
    ),
    (
      Icons.sports_soccer_outlined,
      'Match',
      'Matchförberedelser, statistik och analys',
    ),
    (
      Icons.event_note_outlined,
      'Planering',
      'Säsong, perioder och fokusområden',
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
            onTap: () => onNavigate(ProductRouteContract.development),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          strings.feature('Planerade arbetsytor'),
          style: theme.textTheme.titleMedium,
        ),
        for (final (icon, title, subtitle) in _planned)
          ListTile(
            enabled: false,
            leading: Icon(icon),
            title: Text(strings.feature(title)),
            subtitle: Text(strings.feature(subtitle)),
            trailing: Text(
              strings.feature('Kommer'),
              style: theme.textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}
