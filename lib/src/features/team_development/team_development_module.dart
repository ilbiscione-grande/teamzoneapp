part of '../../app/teamzone_app.dart';

/// Team Development Plan (decision package 11, MFD-10) as its own app:
/// Översikt with the season, the period now and its goals; Säsongen with
/// the periods on a timeline; Mål with every goal of the season.
abstract final class _TeamDevelopmentModule {
  static const _key = 'module.team_development';

  static Future<void> open(
    BuildContext context, {
    required TeamZoneContext team,
    required TeamDevelopmentServices services,
  }) {
    final controller = _TdpController(services, team.teamId!);
    return _ModuleShell.open(
      context,
      _ModuleShell(
        title: 'Team Development Plan',
        subtitle: team.teamName,
        icon: Icons.event_note,
        seed: _ModuleShell.seeds[_key]!,
        sections: [
          _ModuleSection(
            label: 'Översikt',
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            builder: (_) => _TdpOverview(controller: controller),
          ),
          _ModuleSection(
            label: 'Säsongen',
            icon: Icons.view_timeline_outlined,
            selectedIcon: Icons.view_timeline,
            builder: (_) => _TdpSeason(controller: controller),
          ),
          _ModuleSection(
            label: 'Spelidé',
            icon: Icons.lightbulb_outline,
            selectedIcon: Icons.lightbulb,
            builder: (_) => _TdpPlay(controller: controller),
          ),
          _ModuleSection(
            label: 'Mål',
            icon: Icons.flag_outlined,
            selectedIcon: Icons.flag,
            builder: (_) => _TdpGoals(controller: controller),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

/// The plan shared by the module's sections: loaded once, and replaced by
/// the plan each change returns.
class _TdpController extends ChangeNotifier {
  _TdpController(this.services, this.teamId) {
    unawaited(reload());
  }
  final TeamDevelopmentServices services;
  final String teamId;
  TeamDevelopment? data;
  Object? error;
  bool _disposed = false;

  SeasonPlan? get plan => data?.plan;
  bool get canEdit => data?.canEdit == true;

  Future<void> reload({String? planId}) async {
    try {
      final value = await services.get(teamId, planId: planId ?? plan?.id);
      data = value;
      error = null;
    } catch (caught) {
      AppErrors.caught('team_development.reload', caught);
      error = caught;
    }
    if (!_disposed) notifyListeners();
  }

  /// Runs a change and shows the plan it returns; a refusal is told and a
  /// plan changed elsewhere is read again. True when it was saved.
  Future<bool> change(
    BuildContext context,
    Future<SeasonPlan> Function() run, {
    String? done,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.of(context);
    try {
      final saved = await run();
      final current = data;
      data = TeamDevelopment(
        canEdit: current?.canEdit ?? true,
        seasons: [
          for (final season in current?.seasons ?? const <SeasonSummary>[])
            season.id == saved.id
                ? SeasonSummary(
                    id: saved.id,
                    title: saved.title,
                    startsOn: saved.startsOn,
                    endsOn: saved.endsOn,
                  )
                : season,
        ],
        plan: saved,
      );
      if (!_disposed) notifyListeners();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
      return true;
    } on TeamDevelopmentException catch (refused) {
      messenger.showSnackBar(SnackBar(content: Text(refused.message)));
      if (refused.code == 'stale_revision') await reload();
      return false;
    } catch (caught) {
      AppErrors.caught('team_development.change', caught);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Planen kunde inte sparas.'))),
      );
      return false;
    }
  }

  Future<void> createSeason(BuildContext context) async {
    final last = data?.seasons.firstOrNull;
    final draft = await _SeasonDialog.show(context, after: last?.endsOn);
    if (draft == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.of(context);
    try {
      var created = await services.createPlan(
        teamId: teamId,
        title: draft.title,
        startsOn: draft.startsOn,
        endsOn: draft.endsOn,
        vision: draft.vision,
      );
      if (draft.checkinEveryDays != null) {
        created = await services.savePlan(
          created,
          title: draft.title,
          startsOn: draft.startsOn,
          endsOn: draft.endsOn,
          vision: draft.vision,
          checkinEveryDays: draft.checkinEveryDays,
        );
      }
      await reload(planId: created.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.isSwedish
                ? '${created.title} är skapad.'
                : '${created.title} created.',
          ),
        ),
      );
    } on TeamDevelopmentException catch (refused) {
      messenger.showSnackBar(SnackBar(content: Text(refused.message)));
    } catch (caught) {
      AppErrors.caught('team_development.createSeason', caught);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Säsongen kunde inte skapas.'))),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A section's frame: loading, the error, the first season to create, or
/// the plan, readable on wide screens.
class _TdpFrame extends StatelessWidget {
  const _TdpFrame({
    required this.controller,
    required this.builder,
    this.action,
  });
  final _TdpController controller;
  final List<Widget> Function(SeasonPlan plan) builder;

  /// The section's own add button at the end, for those who may change
  /// the plan.
  final Widget? Function(SeasonPlan plan)? action;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final data = controller.data;
      if (data == null) {
        return Center(
          child: controller.error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.of(context).feature(
                          'Planen kunde inte hämtas. Lagets plan sköts av '
                          'ledare med behörighet för lagets utveckling.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: controller.reload,
                        child: Text(
                          AppStrings.of(context).feature('Försök igen'),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      }
      final plan = data.plan;
      final add = plan == null || !data.canEdit ? null : action?.call(plan);
      final children = plan == null
          ? [_TdpFirstSeason(controller: controller)]
          : [
              ...builder(plan),
              if (add != null) ...[
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: add),
              ],
            ];
      return RefreshIndicator(
        onRefresh: controller.reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            for (final child in children)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: child,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _TdpFirstSeason extends StatelessWidget {
  const _TdpFirstSeason({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('tdp-first-season'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_note, size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              AppStrings.of(context).feature('Planera säsongen'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.of(context).feature(
                'Sätt lagets långsiktiga mål för säsongen, dela upp den i '
                'perioder med ett eget fokus och tillfälliga mål, och lägg in '
                'kortsiktiga mål inför matcher eller träningsblock.',
              ),
            ),
            const SizedBox(height: 16),
            if (controller.canEdit)
              FilledButton.icon(
                key: const Key('tdp-create-season'),
                onPressed: () => controller.createSeason(context),
                icon: const Icon(Icons.add),
                label: Text(
                  AppStrings.of(context).feature('Skapa säsongsplan'),
                ),
              )
            else
              Text(
                AppStrings.of(
                  context,
                ).feature('Klubben kan inte ändra planer i modulen just nu.'),
              ),
          ],
        ),
      ),
    );
  }
}

String _tdpDate(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatShortMonthDay(value);

String _tdpRange(BuildContext context, DateTime from, DateTime to) =>
    '${_tdpDate(context, from)} – ${_tdpDate(context, to)}';

/// Översikt: the season with its vision, the period now (or next) with its
/// focus and goals, the season's goals and the coming short-term ones.
class _TdpOverview extends StatelessWidget {
  const _TdpOverview({required this.controller});
  final _TdpController controller;

  @override
  Widget build(BuildContext context) => _TdpFrame(
    controller: controller,
    builder: (plan) {
      final today = DateUtils.dateOnly(DateTime.now());
      final period = plan.currentOrNext(today);
      final short = [
        for (final goal in plan.goalsOf(GoalHorizon.short))
          if (goal.state == GoalState.open && !goal.targetOn!.isBefore(today))
            goal,
      ]..sort((a, b) => a.targetOn!.compareTo(b.targetOn!));
      return [
        _TdpSeasonCard(controller: controller, plan: plan),
        _TdpDue(controller: controller, plan: plan),
        const SizedBox(height: 16),
        if (period != null)
          _TdpPeriodNow(controller: controller, plan: plan, period: period)
        else
          _TdpHint(
            icon: Icons.view_timeline_outlined,
            text: plan.periods.isEmpty
                ? 'Dela upp säsongen i perioder under Säsongen.'
                : 'Säsongens perioder är avslutade.',
          ),
        const SizedBox(height: 16),
        _TdpGoalGroup(
          controller: controller,
          plan: plan,
          title: AppStrings.of(context).feature('Säsongsmål'),
          goals: plan.goalsOf(GoalHorizon.season),
          empty: AppStrings.of(context).feature('Inga säsongsmål än.'),
          newGoal: (horizon: GoalHorizon.season, periodId: null),
        ),
        const SizedBox(height: 16),
        _TdpGoalGroup(
          controller: controller,
          plan: plan,
          title: AppStrings.of(context).feature('Kommande kortsiktiga mål'),
          goals: short.take(3).toList(),
          empty: AppStrings.of(context).feature('Inga kortsiktiga mål framåt.'),
          newGoal: (horizon: GoalHorizon.short, periodId: null),
        ),
      ];
    },
  );
}

/// The season up front: its name, dates, how far it has come and its vision.
class _TdpSeasonCard extends StatelessWidget {
  const _TdpSeasonCard({required this.controller, required this.plan});
  final _TdpController controller;
  final SeasonPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final total = plan.endsOn.difference(plan.startsOn).inDays + 1;
    final gone = (today.difference(plan.startsOn).inDays + 1).clamp(0, total);
    final seasons = controller.data?.seasons ?? const <SeasonSummary>[];
    const white = TextStyle(color: Colors.white);
    return DecoratedBox(
      key: const Key('tdp-season-card'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.lerp(colors.primary, Colors.black, 0.45)!,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  key: const Key('tdp-season-menu'),
                  iconColor: Colors.white,
                  tooltip: AppStrings.of(context).feature('Säsonger'),
                  onSelected: (value) => switch (value) {
                    '_new' => controller.createSeason(context),
                    _ => controller.reload(planId: value),
                  },
                  itemBuilder: (_) => [
                    for (final season in seasons)
                      CheckedPopupMenuItem(
                        value: season.id,
                        checked: season.id == plan.id,
                        child: Text(season.title),
                      ),
                    if (controller.canEdit) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: '_new',
                        child: Text(
                          AppStrings.of(context).feature('Ny säsong'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            Text(
              _tdpRange(context, plan.startsOn, plan.endsOn),
              style: white.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : gone / total,
                  minHeight: 6,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              today.isBefore(plan.startsOn)
                  ? AppStrings.of(context).formatFeature(
                      'Börjar om {days} dagar',
                      {'days': plan.startsOn.difference(today).inDays},
                    )
                  : today.isAfter(plan.endsOn)
                  ? AppStrings.of(context).feature('Säsongen är slut')
                  : AppStrings.of(context).formatFeature(
                      'Dag {day} av {total}',
                      {'day': gone, 'total': total},
                    ),
              style: white.copyWith(fontSize: 12, color: Colors.white70),
            ),
            if (plan.vision.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  plan.vision,
                  style: white.copyWith(
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TdpPeriodNow extends StatelessWidget {
  const _TdpPeriodNow({
    required this.controller,
    required this.plan,
    required this.period,
  });
  final _TdpController controller;
  final SeasonPlan plan;
  final DevelopmentPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final now = period.contains(today);
    final left = period.endsOn.difference(today).inDays;
    return Card(
      key: const Key('tdp-period-now'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TdpPhaseChip(phase: period.phase),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    now
                        ? (left == 0
                              ? AppStrings.of(context).feature('Sista dagen')
                              : AppStrings.of(context).formatFeature(
                                  '{days} dagar kvar',
                                  {'days': left},
                                ))
                        : AppStrings.of(context).formatFeature(
                            'Börjar {date}',
                            {'date': _tdpDate(context, period.startsOn)},
                          ),
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${AppStrings.of(context).feature(now ? 'Nu' : 'Nästa')}: ${period.name}',
              style: theme.textTheme.titleLarge,
            ),
            Text(_tdpRange(context, period.startsOn, period.endsOn)),
            if (period.focus.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                AppStrings.of(context).feature('Fokus'),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 2),
              Text(period.focus),
            ],
            const SizedBox(height: 12),
            _TdpGoalGroup(
              controller: controller,
              plan: plan,
              title: AppStrings.of(context).feature('Periodens mål'),
              goals: plan.goalsOf(GoalHorizon.period, periodId: period.id),
              empty: AppStrings.of(
                context,
              ).feature('Inga mål för perioden än.'),
              newGoal: (horizon: GoalHorizon.period, periodId: period.id),
              flat: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TdpHint extends StatelessWidget {
  const _TdpHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(AppStrings.of(context).feature(text)),
    ),
  );
}
