import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/support/support_clubs_tab.dart'
    show supportDate;
import 'package:teamzone_app/src/features/support/support_usage_detail.dart';
import 'package:teamzone_app/src/features/support/support_usage_services.dart';

/// Statistik on the support admin page: accounts, active accounts, apps,
/// clubs and use per area for a chosen period. Counts only. A card opens
/// to a value per day and breakdowns, when the services can give them.
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
            final details = widget.services is SupportUsageDetailServices
                ? widget.services as SupportUsageDetailServices
                : null;
            return _UsageBody(
              usage: snapshot.requireData,
              onOpen: details == null
                  ? null
                  : (tile) => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (_) => SupportUsageDetailSheet(
                        services: details,
                        metric: tile.metric,
                        item: tile.item,
                        title: tile.label,
                        value: tile.value,
                        periodDays: _period,
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({required this.usage, this.onOpen});
  final PlatformUsage usage;
  final ValueChanged<UsageTile>? onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final theme = Theme.of(context);
    final since = usage.activitySince;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UsageSection(
          title: strings.accountsHeading,
          onOpen: onOpen,
          tiles: [
            UsageTile(strings.total, usage.accounts, 'accounts', 'total'),
            UsageTile(
              strings.newInPeriod,
              usage.newAccounts,
              'accounts',
              'new',
            ),
            UsageTile(
              strings.linkedToClub,
              usage.linkedAccounts,
              'accounts',
              'linked',
            ),
            for (final entry in usage.accountTypes.entries)
              UsageTile(
                strings.accountType(entry.key),
                entry.value,
                'account_type',
                entry.key,
              ),
          ],
        ),
        UsageSection(
          title: strings.activeHeading,
          onOpen: onOpen,
          tiles: [
            UsageTile(strings.today, usage.activeToday, 'active', 'today'),
            UsageTile(strings.last7, usage.active7, 'active', 'last_7_days'),
            UsageTile(strings.last30, usage.active30, 'active', 'last_30_days'),
            UsageTile(
              strings.inPeriod,
              usage.activeInPeriod,
              'active',
              'in_period',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(strings.dailyHeading, style: theme.textTheme.titleSmall),
        ),
        UsageBars(
          key: const ValueKey('support-usage-daily'),
          days: [
            for (final day in usage.daily) (day: day.day, value: day.active),
          ],
          tooltip: (bar) {
            final day = usage.daily.firstWhere((d) => d.day == bar.day);
            return strings.dayTooltip(
              supportDate(day.day),
              day.active,
              day.newAccounts,
            );
          },
        ),
        UsageSection(
          title: strings.appsHeading,
          empty: strings.noApps,
          onOpen: onOpen,
          tiles: [
            for (final entry in usage.apps.entries)
              UsageTile(strings.app(entry.key), entry.value, 'app', entry.key),
          ],
        ),
        UsageSection(
          title: strings.clubsHeading,
          onOpen: onOpen,
          tiles: [
            for (final entry in usage.clubs.entries)
              UsageTile(
                strings.club(entry.key),
                entry.value,
                'clubs',
                entry.key,
              ),
          ],
        ),
        UsageSection(
          title: strings.areasHeading,
          onOpen: onOpen,
          tiles: [
            for (final entry in usage.areas.entries)
              UsageTile(
                strings.area(entry.key),
                entry.value,
                'area',
                entry.key,
              ),
          ],
        ),
        UsageSection(
          title: strings.productsHeading,
          onOpen: onOpen,
          tiles: [
            for (final entry in usage.subscriptions.entries)
              UsageTile(
                strings.subscription(entry.key),
                entry.value,
                'subscription',
                entry.key,
              ),
            for (final entry in usage.pushDevices.entries)
              UsageTile(
                strings.pushDevices(entry.key),
                entry.value,
                'push',
                entry.key,
              ),
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

/// One card: a count and what it is. Also used by the Tacticsboard tab.
class UsageTile {
  const UsageTile(this.label, this.value, this.metric, this.item);
  final String label;
  final int value;

  /// What the server calls the card, for its details.
  final String metric;
  final String item;
}

/// A heading and its cards; a card opens with [onOpen] when given.
class UsageSection extends StatelessWidget {
  const UsageSection({
    super.key,
    required this.title,
    required this.tiles,
    this.empty,
    this.onOpen,
  });
  final String title;
  final List<UsageTile> tiles;
  final String? empty;
  final ValueChanged<UsageTile>? onOpen;

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
                    key: ValueKey('support-usage-${tile.metric}-${tile.item}'),
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onOpen == null ? null : () => onOpen!(tile),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${tile.value}',
                                    style: theme.textTheme.headlineSmall,
                                  ),
                                ),
                                if (onOpen != null)
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                              ],
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
                ),
            ],
          ),
        ],
      ),
    );
  }
}
