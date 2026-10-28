part of '../../app/teamzone_app.dart';

/// The team's picture as a banner with the team and club on it and the
/// member count in a chip; a soft accent field with an icon without one.
class _TeamBanner extends StatelessWidget {
  const _TeamBanner({required this.value});
  final TeamOverview value;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    // The dark theme's accent is a light green; it is deepened there so the
    // white names keep their contrast.
    final dark = theme.brightness == Brightness.dark;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette.accent, Colors.black, dark ? .5 : 0)!,
            Color.lerp(palette.accent, Colors.black, dark ? .8 : .45)!,
          ],
        ),
      ),
      child: Align(
        alignment: const Alignment(.8, -.4),
        child: Icon(
          Icons.groups_outlined,
          size: 72,
          color: Colors.white.withValues(alpha: .35),
          semanticLabel: strings.feature('Ingen lagbild'),
        ),
      ),
    );
    return SizedBox(
      key: const ValueKey('team-overview-banner'),
      height: 172,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (value.imageUrl == null)
              fallback
            else
              Image.network(
                value.imageUrl!,
                fit: BoxFit.cover,
                semanticLabel: strings
                    .feature('Lagbild för {team}')
                    .replaceFirst('{team}', value.teamName),
                errorBuilder: (_, _, _) => fallback,
              ),
            // Darkens the lower part so the names read on any picture.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [.35, 1],
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          value.teamName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          value.clubName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: .9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    key: const ValueKey('team-overview-member-count'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${value.memberCount} '
                          '${strings.feature('medlemmar')}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section title on the team overview, with "Visa alla" on the right
/// when the section has a fuller list elsewhere.
class _TeamSectionHeader extends StatelessWidget {
  const _TeamSectionHeader({required this.title, this.onShowAll});
  final String title;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (onShowAll != null)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.of(context).accent,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onShowAll,
            child: Text(AppStrings.of(context).feature('Visa alla')),
          ),
      ],
    ),
  );
}

/// An event on the team overview in the calendar's card style: the date
/// tile, the type's icon, the title, then the result of a played match or
/// the time, and the place.
class _TeamOverviewEventCard extends StatelessWidget {
  const _TeamOverviewEventCard({required this.event});
  final CalendarEventSummary event;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final start = event.startsAt.toLocal();
    final match = event.type == 'match';
    final hasResult =
        match &&
        event.matchState == 'completed' &&
        event.scoreUs != null &&
        event.scoreOpponent != null;
    final time = event.allDay
        ? strings.feature('Heldag')
        : _eventTimeRange(context, start, event.endsAt.toLocal());
    final details = [
      if (hasResult) strings.domainValue(event.type) else time,
      if (event.locationName?.trim().isNotEmpty ?? false) event.locationName!,
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => GoRouter.of(
          context,
        ).push(ProductRouteContract.calendarEvent(event.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _HomeDateTile(day: DateUtils.dateOnly(start), match: match),
              const SizedBox(width: 14),
              Icon(
                _homeEventIcon(event.type),
                color: match ? theme.colorScheme.onSurface : palette.accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasResult)
                      Text(
                        '${event.scoreUs} – ${event.scoreOpponent}',
                        key: ValueKey('team-overview-result-${event.id}'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: palette.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shortcuts to the team's other tabs and pages, two to a row.
class _TeamQuickLinks extends StatelessWidget {
  const _TeamQuickLinks({required this.links});
  final List<
    ({IconData icon, String title, String subtitle, VoidCallback onTap})
  >
  links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final link in links)
              // One height for all, room for a subtitle on two lines.
              SizedBox(
                width: width,
                height: 84,
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: link.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(link.icon, color: palette.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  link.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  link.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: palette.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
