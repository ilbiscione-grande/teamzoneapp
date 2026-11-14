import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/core/localization/support_tacticsboard_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/support/support_clubs_tab.dart'
    show supportDate;
import 'package:teamzone_app/src/features/support/support_tacticsboard_services.dart';
import 'package:teamzone_app/src/features/support/support_usage_detail.dart'
    show UsageBars;
import 'package:teamzone_app/src/features/support/support_usage_tab.dart'
    show UsageSection, UsageTile;

/// Tacticsboard on the support admin page (2026-11-14): accounts, trials,
/// subscriptions, projects, live lessons and sharing from Tacticsboard's own
/// database, for a chosen period. Counts only. A card opens to what it
/// counts and, where there is one, a value per day.
class SupportTacticsboardTab extends StatefulWidget {
  const SupportTacticsboardTab({super.key, required this.services});
  final SupportTacticsboardServices services;

  @override
  State<SupportTacticsboardTab> createState() => _SupportTacticsboardTabState();
}

class _SupportTacticsboardTabState extends State<SupportTacticsboardTab> {
  static const _periods = [7, 30, 90, 365];
  int _period = 30;
  late Future<TacticsboardUsage> _usage = _load();

  Future<TacticsboardUsage> _load() => widget.services
      .getTacticsboardUsage(periodDays: _period)
      .timeout(const Duration(seconds: 20));

  void _choose(int days) => setState(() {
    _period = days;
    _usage = _load();
  });

  void _open(TacticsboardUsage usage, UsageTile tile) {
    final section = tile.metric.substring('tacticsboard_'.length);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CardSheet(usage: usage, section: section, tile: tile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final tb = SupportTacticsboardStrings.of(context);
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('support-tacticsboard'),
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in _periods)
              ChoiceChip(
                key: ValueKey('support-tacticsboard-period-$days'),
                label: Text(strings.periodDays(days)),
                selected: _period == days,
                onSelected: (_) => _choose(days),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<TacticsboardUsage>(
          future: _usage,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.error is TacticsboardUsageNotConfigured) {
              return Padding(
                key: const ValueKey('support-tacticsboard-not-configured'),
                padding: const EdgeInsets.all(24),
                child: Text(tb.notConfigured),
              );
            }
            if (snapshot.hasError) {
              AppErrors.caught(
                'support_tacticsboard_tab.load',
                snapshot.error!,
              );
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
            final usage = snapshot.requireData;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in usage.sections.entries)
                  UsageSection(
                    title: tb.section(entry.key),
                    onOpen: (tile) => _open(usage, tile),
                    tiles: [
                      for (final count in entry.value.entries)
                        // Not recorded in this database (e.g. withdrawals).
                        if (count.value != null)
                          UsageTile(
                            tb.label(entry.key, count.key),
                            count.value!,
                            'tacticsboard_${entry.key}',
                            count.key,
                          ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    tb.sourceNote(usage.source),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CardSheet extends StatelessWidget {
  const _CardSheet({
    required this.usage,
    required this.section,
    required this.tile,
  });
  final TacticsboardUsage usage;
  final String section;
  final UsageTile tile;

  @override
  Widget build(BuildContext context) {
    final tb = SupportTacticsboardStrings.of(context);
    final theme = Theme.of(context);
    final series = tacticsboardSeries(section, tile.item);
    return ListView(
      key: const ValueKey('support-tacticsboard-detail'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Text(tile.label, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('${tile.value}', style: theme.textTheme.headlineMedium),
        Text(
          tb.counts(section, tile.item),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (series != null) ...[
          const SizedBox(height: 16),
          Text(tb.series(series), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          UsageBars(
            key: const ValueKey('support-tacticsboard-detail-daily'),
            days: usage.series(series),
            tooltip: (day) => '${supportDate(day.day)}: ${day.value}',
          ),
        ],
      ],
    );
  }
}
