part of '../../app/teamzone_app.dart';

/// The event's own heading above the status and tabs: the type's icon in a
/// soft circle, the title, and the club and team.
class _EventHeader extends StatelessWidget {
  const _EventHeader({
    required this.type,
    required this.title,
    required this.subtitle,
  });
  final String type, title, subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final match = type == 'match';
    return Padding(
      key: const ValueKey('event-header'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: match ? palette.dangerSoft : palette.accentSoft,
            child: Icon(
              _homeEventIcon(type),
              size: 28,
              color: match ? palette.onDangerSoft : palette.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of the Info tab as its own card: an icon, a title, a line under
/// it and an optional action on the right.
class _EventInfoCard extends StatelessWidget {
  const _EventInfoCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.soft = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;

  /// In place of the icon, for the date tile.
  final Widget? leading;
  final Widget? trailing;

  /// The icon in a soft accent circle, for notes rather than facts.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            leading ??
                (soft
                    ? CircleAvatar(
                        radius: 22,
                        backgroundColor: palette.accentSoft,
                        child: Icon(icon, color: palette.accent),
                      )
                    : SizedBox(
                        width: 44,
                        child: Icon(icon, color: palette.accent),
                      )),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle case final text? when text.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// The event's date as a tile: weekday, day and month.
class _EventDateTile extends StatelessWidget {
  const _EventDateTile({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final material = MaterialLocalizations.of(context);
    final style = textTheme.labelSmall?.copyWith(
      color: palette.accent,
      fontWeight: FontWeight.w700,
    );
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Column(
        children: [
          Text(
            _homeShortWeekday(material, day).toUpperCase(),
            style: style?.copyWith(letterSpacing: .6),
          ),
          Text(
            '${day.day}',
            style: textTheme.headlineMedium?.copyWith(
              color: palette.accent,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          Text(
            material
                .formatShortMonthDay(day)
                .replaceAll(RegExp(r'[0-9]'), '')
                .trim(),
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Without callups: "Kan du inte komma?" with the button to report it,
/// kept at the bottom of the page.
class _EventAbsenceBar extends StatelessWidget {
  const _EventAbsenceBar({
    required this.personId,
    required this.title,
    required this.saving,
    required this.onReport,
  });
  final String personId, title;
  final bool saving;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Material(
      key: ValueKey('event-absence-$personId'),
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      elevation: 6,
      shadowColor: Colors.black26,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            Icon(Icons.event_busy_outlined, color: palette.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    strings.feature('Ledarna får besked.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ValueKey('event-absence-report-$personId'),
              onPressed: saving ? null : onReport,
              child: Text(strings.feature('Anmäl frånvaro')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section card on Förberedelser and Uppföljning: the theme's card colour
/// and outline, so the tabs read like the Info tab.
ShapeDecoration _eventSectionCard(BuildContext context) {
  final theme = Theme.of(context);
  return ShapeDecoration(
    color: theme.cardTheme.color ?? theme.colorScheme.surface,
    shape:
        theme.cardTheme.shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
  );
}
