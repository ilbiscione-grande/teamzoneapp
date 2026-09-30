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
  });
  final ProfileServices profile;
  final String clubId, teamId, personId;

  /// Players have training and match figures; leaders mostly not.
  final bool homeMember;

  @override
  State<_PersonStatisticsView> createState() => _PersonStatisticsViewState();
}

class _PersonStatisticsViewState extends State<_PersonStatisticsView> {
  late Future<PersonStatistics> _load = _reload();

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
            padding: const EdgeInsets.all(16),
            children: [
              _StatSection(
                title: strings.feature('Träning och match'),
                icon: Icons.sports_soccer_outlined,
                tiles: [
                  _StatTile(
                    label: strings.feature('Träningsnärvaro'),
                    value: '${stats.trainingsAttended}/${stats.trainingsTotal}',
                    detail: _percent(
                      stats.trainingsAttended,
                      stats.trainingsTotal,
                    ),
                  ),
                  _StatTile(
                    label: strings.feature('Matcher spelade'),
                    value: '${stats.matchesPlayed}/${stats.matchesTotal}',
                    detail: _percent(stats.matchesPlayed, stats.matchesTotal),
                  ),
                  _StatTile(
                    key: const ValueKey('stat-goals'),
                    label: strings.feature('Mål'),
                    value: '${stats.goals}',
                  ),
                  _StatTile(
                    label: strings.feature('Assist'),
                    value: '${stats.assists}',
                  ),
                  _StatTile(
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
                    label: strings.feature('Mottagna'),
                    value: '${stats.callupsReceived}',
                  ),
                  _StatTile(
                    label: strings.feature('Tackat ja'),
                    value: '${stats.callupsAccepted}',
                    detail: _percent(
                      stats.callupsAccepted,
                      stats.callupsReceived,
                    ),
                  ),
                  _StatTile(
                    label: strings.feature('Tackat nej'),
                    value: '${stats.callupsDeclined}',
                  ),
                  _StatTile(
                    key: const ValueKey('stat-response-time'),
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
                      label: strings.feature('Dagar i rad'),
                      value: '${app.currentStreak}',
                      detail: app.currentStreak > 0 ? '🔥' : null,
                    ),
                    _StatTile(
                      label: strings.feature('Längsta svit'),
                      value: '${app.longestStreak}',
                    ),
                    _StatTile(
                      label: strings.feature('Aktiva dagar (30 d)'),
                      value: '${app.activeDays30}',
                    ),
                    _StatTile(
                      key: const ValueKey('stat-messages'),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520 ? 4 : 2;
              final width =
                  (constraints.maxWidth - 10 * (columns - 1)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final tile in tiles) SizedBox(width: width, child: tile),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    this.detail,
  });
  final String label, value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 6),
                  Text(detail!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
