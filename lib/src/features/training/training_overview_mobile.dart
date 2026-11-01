part of '../../app/teamzone_app.dart';

/// The overview on a phone: the session in figures over a picture, the
/// place, focus, squad and material as tiles, the goals, and below them
/// the session squad and the event's settings.
class _TrainingOverviewMobile extends StatefulWidget {
  const _TrainingOverviewMobile({
    required this.session,
    required this.blocks,
    required this.theme,
    required this.published,
    required this.squad,
    required this.candidates,
    required this.event,
    required this.preparation,
    required this.goals,
    required this.squadCard,
    required this.settingsCard,
    required this.evaluation,
    required this.onPlanning,
    required this.onPreparation,
    required this.onPublished,
    required this.onFocus,
  });
  final TrainingSession session;
  final List<TrainingBlock> blocks;
  final TextEditingController theme;
  final bool published;
  final List<TrainingBlockPlayer> squad;
  final Future<List<EventRosterPerson>>? candidates;
  final Future<(EventDetails, SquadDetails)> event;
  final Future<EventPreparation> preparation;
  final Future<EventFollowup> goals;
  final Widget squadCard, settingsCard;
  final Widget? evaluation;
  final VoidCallback onPlanning, onPreparation, onFocus;
  final ValueChanged<bool> onPublished;

  @override
  State<_TrainingOverviewMobile> createState() =>
      _TrainingOverviewMobileState();
}

class _TrainingOverviewMobileState extends State<_TrainingOverviewMobile> {
  final _squadKey = GlobalKey();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        key: const Key('training-session-overview'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _hero(context),
          const SizedBox(height: 12),
          _tiles(context),
          const SizedBox(height: 12),
          _goals(context),
          const SizedBox(height: 12),
          KeyedSubtree(key: _squadKey, child: widget.squadCard),
          const SizedBox(height: 12),
          widget.settingsCard,
          if (widget.evaluation != null) ...[
            const SizedBox(height: 12),
            widget.evaluation!,
          ],
        ],
      ),
    ),
  );

  /// The session's figures over a placeholder picture of a pitch.
  Widget _hero(BuildContext context) {
    final strings = AppStrings.of(context);
    final text = Theme.of(context).textTheme;
    Widget figure(
      String value,
      String label, {
      Key? key,
      VoidCallback? onTap,
    }) => Flexible(
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: text.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  strings.feature(label),
                  style: text.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final divider = Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.white38,
    );
    return Container(
      height: 168,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4F7F45), Color(0xFF1E3A22)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -18,
            top: -18,
            child: Icon(
              Icons.sports_soccer,
              size: 132,
              color: Color(0x22FFFFFF),
            ),
          ),
          Positioned(top: 12, right: 12, child: _publishChip(context)),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                figure('${widget.session.eventMinutes}', 'minuter'),
                divider,
                figure(
                  '${widget.blocks.length}',
                  'övningar',
                  key: const Key('training-open-planning'),
                  onTap: widget.onPlanning,
                ),
                divider,
                FutureBuilder<List<EventRosterPerson>>(
                  future: widget.candidates,
                  builder: (context, snapshot) => figure(
                    snapshot.data == null
                        ? '${widget.squad.length}'
                        : '${widget.squad.length}/${max(widget.squad.length, snapshot.data!.length)}',
                    'deltagare',
                    onTap: _showSquad,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _publishChip(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<bool>(
      key: const Key('training-session-published'),
      tooltip: strings.feature('Synlighet'),
      onSelected: widget.onPublished,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: true,
          checked: widget.published,
          child: Text(strings.feature('Visa passet för spelarna')),
        ),
        CheckedPopupMenuItem(
          value: false,
          checked: !widget.published,
          child: Text(strings.feature('Bara ledarna ser passet')),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.published
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              strings.feature(widget.published ? 'Publicerad' : 'Utkast'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  void _showSquad() {
    final target = _squadKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required Widget body,
    VoidCallback? onTap,
  }) {
    final text = Theme.of(context).textTheme;
    return _ProgramPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.of(context).feature(title),
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      child: body,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tiles(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final place = FutureBuilder<(EventDetails, SquadDetails)>(
      future: widget.event,
      builder: (context, snapshot) {
        final details = snapshot.data?.$1;
        final text = [details?.locationName, details?.locationPitch]
            .whereType<String>()
            .where((part) => part.trim().isNotEmpty)
            .join(' – ');
        return Text(
          text.isEmpty ? strings.feature('Ingen plats angiven') : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
    final focus = ListenableBuilder(
      listenable: widget.theme,
      builder: (context, _) => Text(
        widget.theme.text.trim().isEmpty
            ? strings.feature('Lägg till träningsfokus')
            : widget.theme.text.trim(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final names = [
      for (final player in widget.squad)
        if (player.name.trim().isNotEmpty) player.name.trim(),
    ];
    final squad = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.formatFeature('{count} spelare', {
            'count': widget.squad.length,
          }),
        ),
        if (widget.squad.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (final name in names.take(3))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: colors.surfaceContainerHigh,
                    child: Text(
                      name
                          .split(' ')
                          .where((part) => part.isNotEmpty)
                          .take(2)
                          .map((part) => part[0].toUpperCase())
                          .join(),
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (widget.squad.length > min(3, names.length))
                Text('+${widget.squad.length - min(3, names.length)}'),
            ],
          ),
        ],
      ],
    );
    final material = FutureBuilder<EventPreparation>(
      future: widget.preparation,
      builder: (context, snapshot) {
        final count =
            snapshot.data?.itemsOf(PreparationKind.material).length ?? 0;
        return Text(strings.formatFeature('{count} objekt', {'count': count}));
      },
    );
    Widget pair(Widget left, Widget right) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      ),
    );
    return Column(
      children: [
        pair(
          _tile(
            context,
            icon: Icons.place_outlined,
            color: colors.primary,
            title: 'Plats',
            body: place,
          ),
          _tile(
            context,
            icon: Icons.track_changes,
            color: const Color(0xFFC4573A),
            title: 'Träningsfokus',
            body: focus,
            onTap: widget.onFocus,
          ),
        ),
        const SizedBox(height: 10),
        pair(
          _tile(
            context,
            icon: Icons.groups_outlined,
            color: const Color(0xFF1E5BB8),
            title: 'Sessionstrupp',
            body: squad,
            onTap: _showSquad,
          ),
          _tile(
            context,
            icon: Icons.inventory_2_outlined,
            color: const Color(0xFFC4573A),
            title: 'Material',
            body: material,
            onTap: widget.onPreparation,
          ),
        ),
      ],
    );
  }

  Widget _goals(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<EventFollowup>(
      future: widget.goals,
      builder: (context, snapshot) {
        final goals = [
          for (final goal in snapshot.data?.kpis ?? const <EventKpi>[])
            goal.label,
        ];
        return _tile(
          context,
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF4F8A3C),
          title: 'Träningsmål',
          onTap: widget.onPreparation,
          body: Row(
            children: [
              Expanded(
                child: Text(
                  goals.isEmpty
                      ? strings.feature('Inga träningsmål än.')
                      : goals.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        );
      },
    );
  }
}
