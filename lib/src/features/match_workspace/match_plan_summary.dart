part of '../../app/teamzone_app.dart';

/// Under Förberedelser in a match event, where the club has the Match
/// module: for leaders how far the match plan is and the way to it; for
/// players the plan's shown parts once it is published. Without the module
/// (the server says not_found) nothing shows.
class _MatchPlanSection extends StatefulWidget {
  const _MatchPlanSection({
    super.key,
    required this.eventId,
    required this.title,
    required this.calendar,
    required this.match,
    required this.sides,
  });
  final String eventId, title;
  final CalendarServices calendar;
  final MatchServices match;
  final _MatchSides sides;

  @override
  State<_MatchPlanSection> createState() => _MatchPlanSectionState();
}

class _MatchPlanSectionState extends State<_MatchPlanSection> {
  late Future<MatchPlan?> _plan = _load();

  Future<MatchPlan?> _load() => widget.calendar.matchPlans
      .getPlan(widget.eventId)
      .then<MatchPlan?>((plan) => plan, onError: (_) => null);

  Future<void> _open() async {
    await _MatchModule.openMatch(
      context,
      eventId: widget.eventId,
      title: widget.title,
      calendar: widget.calendar,
      match: widget.match,
      sides: widget.sides,
    );
    if (mounted) setState(() => _plan = _load());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<MatchPlan?>(
      future: _plan,
      builder: (context, snapshot) {
        final plan = snapshot.data;
        if (plan == null || (!plan.canEdit && plan.isEmpty)) {
          return const SizedBox.shrink();
        }
        final status = plan.revision == 0
            ? 'Ingen matchplan än'
            : plan.published
            ? 'Publicerad för spelarna'
            : 'Utkast, bara ledarna ser den';
        return Card(
          key: const Key('event-match-plan'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.feature('Matchplan'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                if (plan.canEdit) ...[
                  Text(strings.feature(status)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      key: const Key('event-match-plan-open'),
                      onPressed: _open,
                      child: Text(
                        strings.feature(
                          plan.revision == 0
                              ? 'Skapa matchplan'
                              : 'Öppna matchplanen',
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  for (final (title, section) in [
                    ('Taktik', plan.tactics),
                    ('Standardsituationer', plan.setPieces),
                    ('Motståndaren', plan.opponent),
                  ])
                    if (section != null && section.text.trim().isNotEmpty) ...[
                      Text(
                        strings.feature(title),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(section.text),
                      const SizedBox(height: 8),
                    ],
                  for (final link in plan.links)
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(link.url),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.link),
                      label: Text(link.title),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
