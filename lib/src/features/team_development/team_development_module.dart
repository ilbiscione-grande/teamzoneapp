part of '../../app/teamzone_app.dart';

/// Team Development Plan (decision package 11, MFD-10; the new design of
/// 2026-11-01) as its own app: Översikt, the team's development page with
/// the block now, the season and the goals; Planera, the season planned on
/// a timeline of periods and blocks; Spelidé, the way of playing.
abstract final class _TeamDevelopmentModule {
  static const _key = 'module.team_development';

  static Future<void> open(
    BuildContext context, {
    required TeamZoneContext team,
    required TeamDevelopmentServices services,
    required CalendarServices calendar,
    required ValueChanged<String> onNavigate,
  }) {
    final controller = _TdpController(
      services,
      team.teamId!,
      calendar: calendar,
      contextId: team.id,
      // An activity opens on its own page: the module closes first.
      onOpenEvent: (eventId) {
        Navigator.of(context, rootNavigator: true).pop();
        onNavigate(ProductRouteContract.calendarEvent(eventId));
      },
    );
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
            builder: (_) => _TdpHome(controller: controller),
          ),
          _ModuleSection(
            label: 'Planera',
            icon: Icons.view_timeline_outlined,
            selectedIcon: Icons.view_timeline,
            builder: (_) => _TdpPlanner(controller: controller),
          ),
          _ModuleSection(
            label: 'Spelidé',
            icon: Icons.lightbulb_outline,
            selectedIcon: Icons.lightbulb,
            builder: (_) => _TdpPlay(controller: controller),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

/// The plan shared by the module's sections: loaded once, and replaced by
/// the plan each change returns.
class _TdpController extends ChangeNotifier {
  _TdpController(
    this.services,
    this.teamId, {
    required this.calendar,
    required this.contextId,
    required this.onOpenEvent,
  }) {
    unawaited(reload());
  }
  final TeamDevelopmentServices services;
  final String teamId;

  /// The team's calendar, for the activities beside the plan; [contextId]
  /// is the leader's assignment in the team.
  final CalendarServices calendar;
  final String contextId;
  final ValueChanged<String> onOpenEvent;
  DateTime? _from, _to;
  Future<List<CalendarEventSummary>>? _activities;

  /// The team's activities from [from] to [to], not cancelled, by start.
  /// Read once for a stretch and again only for days outside it.
  Future<List<CalendarEventSummary>> activities(DateTime from, DateTime to) {
    final cached = _activities;
    if (cached != null && !from.isBefore(_from!) && !to.isAfter(_to!)) {
      return cached;
    }
    final start = _from == null || from.isBefore(_from!) ? from : _from!;
    final end = _to == null || to.isAfter(_to!) ? to : _to!;
    _from = start;
    _to = end;
    return _activities = _readActivities(start, end);
  }

  Future<List<CalendarEventSummary>> _readActivities(
    DateTime from,
    DateTime to,
  ) async {
    try {
      final events = await calendar.listCalendar(
        contextIds: [contextId],
        from: from,
        to: to.add(const Duration(days: 1)),
      );
      return [
        for (final event in events)
          if (event.state != 'cancelled') event,
      ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    } catch (caught) {
      AppErrors.caught('team_development.activities', caught);
      _activities = _from = _to = null;
      rethrow;
    }
  }

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
      final created = await services.createPlan(
        teamId: teamId,
        title: draft.title,
        startsOn: draft.startsOn,
        endsOn: draft.endsOn,
        vision: draft.vision,
      );
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
    this.maxWidth = 820,
  });
  final _TdpController controller;
  final List<Widget> Function(SeasonPlan plan) builder;

  /// How wide the content grows: readable text, or the whole screen for
  /// the overview and the planning.
  final double maxWidth;

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
      final children = plan == null
          ? [_TdpFirstSeason(controller: controller)]
          : builder(plan);
      return RefreshIndicator(
        onRefresh: controller.reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            for (final child in children)
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
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

/// [day] moved [days] calendar days, at midnight: a day across a change to
/// or from summer time is not 24 hours.
DateTime _tdpShift(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// The calendar days from [from] to [to].
int _tdpDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String _tdpRange(BuildContext context, DateTime from, DateTime to) =>
    '${_tdpDate(context, from)} – ${_tdpDate(context, to)}';

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
