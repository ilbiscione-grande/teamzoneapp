part of '../../app/teamzone_app.dart';

/// "LÖR" from "lör 31 okt." — the locale's short weekday, at most three
/// letters so "tors" lines up with the others.
String _homeShortWeekday(MaterialLocalizations material, DateTime day) {
  final weekday = material
      .formatMediumDate(day)
      .split(' ')
      .first
      .replaceAll(RegExp(r'[,.]'), '')
      .toUpperCase();
  return weekday.length > 3 ? weekday.substring(0, 3) : weekday;
}

IconData _homeEventIcon(String type) => switch (type) {
  'match' => Icons.emoji_events,
  'training' => Icons.sports,
  'meeting' => Icons.groups,
  'activity' => Icons.local_activity,
  _ => Icons.event,
};

/// The Home page's hero card: what is on now, later today, tomorrow or
/// next — a round accent badge, title, time and place, thumbs up/down
/// while the own callup can be answered — followed by three quick-action
/// tiles for the same event.
class _HomeHeroEventCard extends StatelessWidget {
  const _HomeHeroEventCard({
    required this.event,
    required this.now,
    required this.onNavigate,
    required this.pendingCallupId,
    required this.onRespond,
  });
  final LeaderHomeEvent event;
  final DateTime now;
  final ValueChanged<String> onNavigate;
  final String? pendingCallupId;
  final void Function(LeaderHomeCallup callup, String response) onRespond;

  String _moment(MaterialLocalizations material, AppStrings strings) {
    final start = event.startsAt.toLocal();
    final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(start));
    final today = DateUtils.dateOnly(now);
    final day = DateUtils.dateOnly(start);
    if (!event.startsAt.isAfter(now) && event.endsAt.isAfter(now)) {
      final end = material.formatTimeOfDay(
        TimeOfDay.fromDateTime(event.endsAt.toLocal()),
      );
      return strings.formatFeature('PÅGÅR NU · SLUTAR {end}', {'end': end});
    }
    if (day == today) {
      return strings.formatFeature('SENARE IDAG · {time}', {'time': time});
    }
    if (day == today.add(const Duration(days: 1))) {
      return strings.formatFeature('IMORGON · {time}', {'time': time});
    }
    return strings.formatFeature('NÄSTA · {date} · {time}', {
      'date': material.formatMediumDate(start).toUpperCase(),
      'time': time,
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final material = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final colors = theme.colorScheme;
    final match = event.type == 'match';
    final place = [
      event.locationName,
      event.address,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    final callup = event.myCallup;
    final canRespond = callup != null && callup.canRespond;
    String clock(DateTime at) =>
        material.formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));
    final eventRoute = ProductRouteContract.calendarEvent(event.id);
    final card = Card(
      key: const Key('home-hero-event'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onNavigate(eventRoute),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _moment(material, strings),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.muted,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  if (canRespond)
                    Text(
                      strings.feature('Kommer du?'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: match ? palette.danger : colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _homeEventIcon(event.type),
                      color: match ? Colors.white : colors.onPrimary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(event.title, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          '${clock(event.startsAt)} – ${clock(event.endsAt)}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (place.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: palette.muted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    place,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: palette.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (canRespond)
                    _HomeRsvpButtons(
                      response: callup.state,
                      busy: pendingCallupId != null,
                      onRespond: (response) => onRespond(callup, response),
                    )
                  else
                    Icon(Icons.chevron_right, color: palette.muted),
                ],
              ),
              if (callup != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _CallupStatus(callup: callup),
                ),
            ],
          ),
        ),
      ),
    );
    final directions = place.isEmpty
        ? null
        : () => launchUrl(
            Uri.https('www.google.com', '/maps/search/', {
              'api': '1',
              'query': place,
            }),
            mode: LaunchMode.externalApplication,
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          const SizedBox(height: 12),
          Row(
            spacing: 10,
            children: [
              _HomeQuickTile(
                icon: Icons.info_outline,
                label: strings.feature('Detaljer'),
                onTap: () => onNavigate(eventRoute),
              ),
              _HomeQuickTile(
                icon: Icons.near_me_outlined,
                label: strings.feature('Vägbeskrivning'),
                onTap: directions,
              ),
              _HomeQuickTile(
                icon: Icons.description_outlined,
                label: strings.feature('Förberedelser'),
                onTap: () => onNavigate('$eventRoute?tab=preparation'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Thumbs up/down for the hero card's callup: soft mint and pale red
/// tiles, the chosen answer filled. Declining still asks for a reason.
class _HomeRsvpButtons extends StatelessWidget {
  const _HomeRsvpButtons({
    required this.response,
    required this.busy,
    required this.onRespond,
  });
  final String response;
  final bool busy;
  final ValueChanged<String> onRespond;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final palette = AppPalette.of(context);
    final colors = Theme.of(context).colorScheme;
    Widget button({
      required String value,
      required String label,
      required String chosenLabel,
      required IconData icon,
      required Color soft,
      required Color strong,
      required Color onStrong,
    }) {
      final selected = response == value;
      return Tooltip(
        message: selected ? chosenLabel : label,
        child: Semantics(
          selected: selected,
          child: IconButton(
            onPressed: busy
                ? null
                : selected
                ? () {}
                : () => onRespond(value),
            style: IconButton.styleFrom(
              backgroundColor: selected ? strong : soft,
              foregroundColor: selected ? onStrong : strong,
              disabledBackgroundColor: soft.withValues(alpha: .6),
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip)),
              ),
            ),
            icon: Icon(icon, size: 22),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        button(
          value: 'accepted',
          label: strings.feature('Acceptera'),
          chosenLabel: strings.feature('Accepterat'),
          icon: Icons.thumb_up,
          soft: palette.accentSoft,
          strong: palette.accent,
          onStrong: colors.onPrimary,
        ),
        button(
          value: 'declined',
          label: strings.feature('Avböj'),
          chosenLabel: strings.feature('Avböjt'),
          icon: Icons.thumb_down,
          soft: palette.dangerSoft,
          strong: palette.danger,
          onStrong: Colors.white,
        ),
      ],
    );
  }
}

/// A square quick-action tile: an accent icon over a short label.
class _HomeQuickTile extends StatelessWidget {
  const _HomeQuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = onTap != null;
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 84,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 26,
                  color: enabled ? palette.accent : palette.muted,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Kommande aktiviteter" with an optional "Visa alla" link, followed by
/// one card per event.
class _HomeEventList extends StatelessWidget {
  const _HomeEventList({
    required this.title,
    required this.children,
    this.onShowAll,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onShowAll != null)
                  TextButton(
                    onPressed: onShowAll,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.accent,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppStrings.of(context).feature('Visa alla')),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final child in children)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: child),
        ],
      ),
    );
  }
}

/// A weekday over a large day number, mint for training and other events,
/// pale red for matches.
class _HomeDateTile extends StatelessWidget {
  const _HomeDateTile({required this.day, required this.match});
  final DateTime day;
  final bool match;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final background = match ? palette.dangerSoft : palette.accentSoft;
    final foreground = match ? palette.onDangerSoft : palette.accent;
    return Container(
      width: 52,
      height: 56,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _homeShortWeekday(MaterialLocalizations.of(context), day),
            style: textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: .6,
            ),
          ),
          Text(
            '${day.day}',
            style: textTheme.headlineSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

/// One card under "Resten av idag" or "Kommande aktiviteter": a date tile,
/// the event type's icon, title, time and place, whether it is on now or
/// finished, and the own callup with Acceptera/Avböj while it can still be
/// answered.
class _HomeEventRow extends StatelessWidget {
  const _HomeEventRow({
    required this.event,
    required this.now,
    required this.isToday,
    required this.onNavigate,
    required this.pendingCallupId,
    required this.onRespond,
  });
  final LeaderHomeEvent event;
  final DateTime now;
  final bool isToday;
  final ValueChanged<String> onNavigate;
  final String? pendingCallupId;
  final void Function(LeaderHomeCallup callup, String response) onRespond;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final local = event.startsAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final match = event.type == 'match';
    final finished = !event.endsAt.isAfter(now);
    final ongoing = !finished && !event.startsAt.isAfter(now);
    final callup = event.myCallup;
    String clock(DateTime at) =>
        material.formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));
    final details = [
      if (isToday)
        clock(event.startsAt)
      else
        '${clock(event.startsAt)} – ${clock(event.endsAt)}',
      if (finished) strings.feature('Avslutad'),
      if (ongoing) strings.feature('Pågår'),
    ];
    final place = event.locationName?.trim();
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.muted);
    return Opacity(
      opacity: finished ? .55 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onNavigate(ProductRouteContract.calendarEvent(event.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _HomeDateTile(day: local, match: match),
                    const SizedBox(width: 14),
                    Icon(
                      _homeEventIcon(event.type),
                      color: match ? palette.danger : palette.accent,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(details.join(' · '), style: muted),
                          if (place != null && place.isNotEmpty)
                            Text(
                              place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      finished ? Icons.check : Icons.chevron_right,
                      color: palette.muted,
                    ),
                  ],
                ),
                if (callup != null && !finished)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 4),
                    child: _CallupStatus(callup: callup),
                  ),
                if (callup != null && callup.canRespond && !finished)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _CallupResponseButtons(
                        busy: pendingCallupId != null,
                        saving: pendingCallupId == callup.id,
                        response: callup.state,
                        compact: false,
                        onRespond: (response) => onRespond(callup, response),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
