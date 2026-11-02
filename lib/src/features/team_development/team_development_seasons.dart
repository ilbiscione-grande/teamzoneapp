part of '../../app/teamzone_app.dart';

/// Where a season stands today: going on, coming or done.
enum _TdpSeasonState { current, upcoming, past }

_TdpSeasonState _tdpSeasonState(DateTime startsOn, DateTime endsOn) {
  final today = DateUtils.dateOnly(DateTime.now());
  if (today.isBefore(startsOn)) return _TdpSeasonState.upcoming;
  if (today.isAfter(endsOn)) return _TdpSeasonState.past;
  return _TdpSeasonState.current;
}

String _tdpSeasonStateText(BuildContext context, _TdpSeasonState state) =>
    switch (state) {
      _TdpSeasonState.current => _tdpText(context, 'Pågår', 'Ongoing'),
      _TdpSeasonState.upcoming => _tdpText(context, 'Kommande', 'Upcoming'),
      _TdpSeasonState.past => _tdpText(context, 'Avslutad', 'Finished'),
    };

/// In the module's header, on every section: the season the plan shows,
/// whether it is going on, coming or done, and the way to another season
/// or a new one.
class _TdpSeasonSwitcher extends StatelessWidget {
  const _TdpSeasonSwitcher({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final plan = controller.plan;
      final seasons = controller.data?.seasons ?? const <SeasonSummary>[];
      if (plan == null) return const SizedBox.shrink();
      final state = _tdpSeasonState(plan.startsOn, plan.endsOn);
      final narrow = MediaQuery.sizeOf(context).width < 600;
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: PopupMenuButton<String>(
          key: const Key('tdp-season-switcher'),
          tooltip: _tdpText(
            context,
            'Byt säsong eller skapa en ny',
            'Change season or create a new one',
          ),
          onSelected: (value) => value == '_new'
              ? controller.createSeason(context)
              : controller.reload(planId: value),
          itemBuilder: (menuContext) => [
            PopupMenuItem<String>(
              enabled: false,
              height: 32,
              child: Text(
                _tdpText(menuContext, 'Lagets säsonger', "The team's seasons"),
                style: Theme.of(menuContext).textTheme.labelMedium,
              ),
            ),
            for (final season in seasons)
              CheckedPopupMenuItem<String>(
                key: ValueKey('tdp-season-item-${season.id}'),
                value: season.id,
                checked: season.id == plan.id,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(season.title),
                  subtitle: Text(
                    '${_tdpSeasonStateText(menuContext, _tdpSeasonState(season.startsOn, season.endsOn))}'
                    ' · ${_tdpRange(menuContext, season.startsOn, season.endsOn)}',
                  ),
                ),
              ),
            if (controller.canEdit) ...[
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                key: const Key('tdp-season-new'),
                value: '_new',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.add),
                  title: Text(
                    _tdpText(menuContext, 'Ny säsong…', 'New season…'),
                  ),
                  subtitle: Text(
                    _tdpText(
                      menuContext,
                      'Kan utgå från den här säsongen',
                      'Can start from this season',
                    ),
                  ),
                ),
              ),
            ],
          ],
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white54),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: narrow ? 110 : 260),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        narrow
                            ? _tdpSeasonStateText(context, state)
                            : '${_tdpSeasonStateText(context, state)} · ${_tdpRange(context, plan.startsOn, plan.endsOn)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, color: Colors.white),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Over every section while the plan shows a season other than the one
/// going on: which season it is, and the way back.
class _TdpOtherSeason extends StatelessWidget {
  const _TdpOtherSeason({required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  @override
  Widget build(BuildContext context) {
    final state = _tdpSeasonState(plan.startsOn, plan.endsOn);
    if (state == _TdpSeasonState.current) return const SizedBox.shrink();
    final seasons = controller.data?.seasons ?? const <SeasonSummary>[];
    final current = seasons
        .where(
          (season) =>
              _tdpSeasonState(season.startsOn, season.endsOn) ==
              _TdpSeasonState.current,
        )
        .firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: const Key('tdp-season-banner'),
        color: state == _TdpSeasonState.past
            ? colors.surfaceContainerHighest
            : colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(
                state == _TdpSeasonState.past
                    ? Icons.history
                    : Icons.upcoming_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state == _TdpSeasonState.past
                      ? _tdpText(
                          context,
                          'Du tittar på ${plan.title}, som är avslutad (${_tdpRange(context, plan.startsOn, plan.endsOn)}).',
                          'You are looking at ${plan.title}, which has finished (${_tdpRange(context, plan.startsOn, plan.endsOn)}).',
                        )
                      : _tdpText(
                          context,
                          'Du planerar ${plan.title}, som börjar ${_tdpDate(context, plan.startsOn)}.',
                          'You are planning ${plan.title}, which starts ${_tdpDate(context, plan.startsOn)}.',
                        ),
                ),
              ),
              if (current != null)
                TextButton(
                  key: const Key('tdp-season-to-current'),
                  onPressed: () => controller.reload(planId: current.id),
                  child: Text(
                    _tdpText(
                      context,
                      'Till pågående säsong',
                      'To the ongoing season',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
