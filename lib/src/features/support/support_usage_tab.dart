import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/support/support_clubs_tab.dart'
    show supportDate;
import 'package:teamzone_app/src/features/support/support_usage_services.dart';

/// Statistik on the support admin page: accounts, active accounts, apps,
/// clubs and use per area for a chosen period. Counts only.
class SupportUsageTab extends StatefulWidget {
  const SupportUsageTab({super.key, required this.services});
  final SupportUsageServices services;

  @override
  State<SupportUsageTab> createState() => _SupportUsageTabState();
}

class _SupportUsageTabState extends State<SupportUsageTab> {
  static const _periods = [7, 30, 90, 365];
  int _period = 30;
  late Future<PlatformUsage> _usage = _load();

  Future<PlatformUsage> _load() => widget.services
      .getPlatformUsage(periodDays: _period)
      .timeout(const Duration(seconds: 20));

  void _choose(int days) => setState(() {
    _period = days;
    _usage = _load();
  });

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    return ListView(
      key: const ValueKey('support-usage'),
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in _periods)
              ChoiceChip(
                key: ValueKey('support-usage-period-$days'),
                label: Text(strings.periodDays(days)),
                selected: _period == days,
                onSelected: (_) => _choose(days),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<PlatformUsage>(
          future: _usage,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              AppErrors.caught('support_usage_tab.load', snapshot.error!);
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(strings.usageFailed),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(() => _usage = _load()),
                      child: Text(strings.retry),
                    ),
                  ],
                ),
              );
            }
            return _UsageBody(usage: snapshot.requireData);
          },
        ),
      ],
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({required this.usage});
  final PlatformUsage usage;

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final theme = Theme.of(context);
    final since = usage.activitySince;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: strings.accountsHeading,
          tiles: [
            _Tile(strings.total, usage.accounts),
            _Tile(strings.newInPeriod, usage.newAccounts),
            _Tile(strings.linkedToClub, usage.linkedAccounts),
            for (final entry in usage.accountTypes.entries)
              _Tile(strings.accountType(entry.key), entry.value),
          ],
        ),
        _Section(
          title: strings.activeHeading,
          tiles: [
            _Tile(strings.today, usage.activeToday),
            _Tile(strings.last7, usage.active7),
            _Tile(strings.last30, usage.active30),
            _Tile(strings.inPeriod, usage.activeInPeriod),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(strings.dailyHeading, style: theme.textTheme.titleSmall),
        ),
        _DailyBars(days: usage.daily),
        _Section(
          title: strings.appsHeading,
          empty: strings.noApps,
          tiles: [
            for (final entry in usage.apps.entries)
              _Tile(strings.app(entry.key), entry.value),
          ],
        ),
        _Section(
          title: strings.clubsHeading,
          tiles: [
            for (final entry in usage.clubs.entries)
              _Tile(strings.club(entry.key), entry.value),
          ],
        ),
        _Section(
          title: strings.areasHeading,
          tiles: [
            for (final entry in usage.areas.entries)
              _Tile(strings.area(entry.key), entry.value),
          ],
        ),
        _Section(
          title: strings.productsHeading,
          tiles: [
            for (final entry in usage.subscriptions.entries)
              _Tile(strings.subscription(entry.key), entry.value),
            for (final entry in usage.pushDevices.entries)
              _Tile(strings.pushDevices(entry.key), entry.value),
          ],
        ),
        if (since != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              strings.sinceNote(
                supportDate(since),
                usage.appsSince == null ? null : supportDate(usage.appsSince!),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Tile {
  const _Tile(this.label, this.value);
  final String label;
  final int value;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.tiles, this.empty});
  final String title;
  final List<_Tile> tiles;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (tiles.isEmpty && empty == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (tiles.isEmpty) Text(empty!),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tile in tiles)
                SizedBox(
                  width: 160,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tile.value}',
                            style: theme.textTheme.headlineSmall,
                          ),
                          Text(
                            tile.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One thin bar per day, rounded at the top and anchored to the baseline;
/// a tooltip on each day gives the numbers.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});
  final List<UsageDay> days;

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final peak = days.fold<int>(
      0,
      (top, day) => day.active > top ? day.active : top,
    );
    const height = 120.0;
    return SizedBox(
      key: const ValueKey('support-usage-daily'),
      height: height + 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Tooltip(
                      message: strings.dayTooltip(
                        supportDate(day.day),
                        day.active,
                        day.newAccounts,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          // The whole column height is the hit target.
                          height: height,
                          alignment: Alignment.bottomCenter,
                          color: Colors.transparent,
                          child: Container(
                            height: peak == 0
                                ? 0
                                : (height * day.active / peak).clamp(2, height),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: scheme.outlineVariant),
          if (days.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    supportDate(days.first.day),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    'max $peak',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    supportDate(days.last.day),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
