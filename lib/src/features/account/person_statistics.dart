part of '../../app/teamzone_app.dart';

/// PROF-05: the Statistik tab on a member profile. Every figure is about the
/// person on the profile, app use included (through their own account).
/// Shown to the person and the team's leaders.
class _PersonStatisticsView extends StatefulWidget {
  const _PersonStatisticsView({
    super.key,
    required this.profile,
    required this.clubId,
    required this.teamId,
    required this.personId,
    this.homeMember = true,
    this.initial,
    this.header,
  });
  final ProfileServices profile;
  final String clubId, teamId, personId;

  /// Players have training and match figures; leaders mostly not.
  final bool homeMember;

  /// Figures already being loaded by the profile; loaded here otherwise.
  final Future<PersonStatistics>? initial;

  /// The profile's heading, above the figures.
  final Widget? header;

  @override
  State<_PersonStatisticsView> createState() => _PersonStatisticsViewState();
}

class _PersonStatisticsViewState extends State<_PersonStatisticsView> {
  late Future<PersonStatistics> _load = widget.initial ?? _reload();

  Future<PersonStatistics> _reload() => widget.profile
      .getPersonStatistics(
        clubId: widget.clubId,
        teamId: widget.teamId,
        personId: widget.personId,
      )
      .timeout(const Duration(seconds: 15));

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<PersonStatistics>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(label: strings.loading);
        }
        final stats = snapshot.data;
        if (stats == null) {
          return _StateCard(
            icon: Icons.bar_chart_outlined,
            title: strings.feature('Statistiken kunde inte laddas'),
            message: strings.feature(
              'Statistik visas för personen själv och lagets ledare.',
            ),
            action: TextButton(
              onPressed: () => setState(() {
                _load = _reload();
              }),
              child: Text(strings.feature('Försök igen')),
            ),
          );
        }
        final app = stats.app;
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _load = _reload();
            });
            await _load;
          },
          child: ListView(
            key: const ValueKey('person-statistics'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 4),
              ],
              _StatSection(
                title: strings.feature('Träning och match'),
                icon: Icons.sports_soccer_outlined,
                tiles: [
                  _StatTile(
                    icon: Icons.fitness_center_outlined,
                    label: strings.feature('Träningsnärvaro'),
                    value: '${stats.trainingsAttended}/${stats.trainingsTotal}',
                    detail: _withExtra(
                      strings,
                      _percent(stats.trainingsAttended, stats.trainingsTotal),
                      stats.trainingsExtra,
                    ),
                  ),
                  _StatTile(
                    icon: Icons.sports_soccer_outlined,
                    label: strings.feature('Matcher spelade'),
                    value: '${stats.matchesPlayed}/${stats.matchesTotal}',
                    detail: _withExtra(
                      strings,
                      _percent(stats.matchesPlayed, stats.matchesTotal),
                      stats.matchesExtra,
                    ),
                  ),
                  _StatTile(
                    key: const ValueKey('stat-goals'),
                    icon: Icons.sports_score_outlined,
                    label: strings.feature('Mål'),
                    value: '${stats.goals}',
                  ),
                  _StatTile(
                    icon: Icons.handshake_outlined,
                    label: strings.feature('Assist'),
                    value: '${stats.assists}',
                  ),
                  _StatTile(
                    icon: Icons.style_outlined,
                    label: strings.feature('Kort'),
                    value: '${stats.cards}',
                  ),
                ],
              ),
              _StatSection(
                title: strings.feature('Kallelser'),
                icon: Icons.how_to_reg_outlined,
                tiles: [
                  _StatTile(
                    icon: Icons.mark_email_unread_outlined,
                    label: strings.feature('Mottagna'),
                    value: '${stats.callupsReceived}',
                  ),
                  _StatTile(
                    icon: Icons.check_circle_outline,
                    label: strings.feature('Tackat ja'),
                    value: '${stats.callupsAccepted}',
                    detail: _percent(
                      stats.callupsAccepted,
                      stats.callupsReceived,
                    ),
                  ),
                  _StatTile(
                    icon: Icons.cancel_outlined,
                    label: strings.feature('Tackat nej'),
                    value: '${stats.callupsDeclined}',
                  ),
                  _StatTile(
                    key: const ValueKey('stat-response-time'),
                    icon: Icons.schedule,
                    label: strings.feature('Snittid för svar'),
                    value: stats.averageResponseMinutes == null
                        ? '–'
                        : _duration(strings, stats.averageResponseMinutes!),
                  ),
                ],
              ),
              if (app != null)
                _StatSection(
                  title: strings.feature('Appen'),
                  icon: Icons.phone_iphone_outlined,
                  tiles: [
                    _StatTile(
                      key: const ValueKey('stat-streak'),
                      icon: Icons.local_fire_department_outlined,
                      label: strings.feature('Dagar i rad'),
                      value: '${app.currentStreak}',
                      detail: app.currentStreak > 0 ? '🔥' : null,
                    ),
                    _StatTile(
                      icon: Icons.emoji_events_outlined,
                      label: strings.feature('Längsta svit'),
                      value: '${app.longestStreak}',
                    ),
                    _StatTile(
                      icon: Icons.calendar_month_outlined,
                      label: strings.feature('Aktiva dagar (30 d)'),
                      value: '${app.activeDays30}',
                    ),
                    _StatTile(
                      key: const ValueKey('stat-messages'),
                      icon: Icons.send_outlined,
                      label: strings.feature('Skickade meddelanden'),
                      value: '${app.messagesSent}',
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  String? _percent(int part, int total) =>
      total == 0 ? null : '${(part * 100 / total).round()} %';

  String _duration(AppStrings strings, int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes < 60 * 24) {
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      return rest == 0 ? '$hours h' : '$hours h $rest min';
    }
    final days = (minutes / (60 * 24)).toStringAsFixed(1).replaceAll('.0', '');
    return '$days ${strings.feature('dygn')}';
  }
}

/// A heading and a card with one row per figure.
class _StatSection extends StatelessWidget {
  const _StatSection({
    required this.title,
    required this.icon,
    required this.tiles,
  });
  final String title;
  final IconData icon;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: palette.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (index, tile) in tiles.indexed) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 48,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: .5,
                      ),
                    ),
                  tile,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A figure as a row: an icon, the label, an optional detail and the value.
class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });
  final IconData icon;
  final String label, value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: palette.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                if (detail != null)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// "75 % · +2 utan kallelse": attendance without a callup is shown but is
/// not part of the rate (which counts only events the person was called to).
String? _withExtra(AppStrings strings, String? rate, int extra) {
  if (extra == 0) return rate;
  final label = strings.isSwedish
      ? '+$extra utan kallelse'
      : '+$extra without callup';
  return rate == null ? label : '$rate · $label';
}
