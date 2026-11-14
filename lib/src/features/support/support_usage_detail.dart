import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/support/support_clubs_tab.dart'
    show supportDate;
import 'package:teamzone_app/src/features/support/support_usage_services.dart';

/// One card in Statistik, opened: the value, what it counts, a value per
/// day in the period and the breakdowns.
class SupportUsageDetailSheet extends StatefulWidget {
  const SupportUsageDetailSheet({
    super.key,
    required this.services,
    required this.metric,
    required this.item,
    required this.title,
    required this.value,
    required this.periodDays,
  });
  final SupportUsageDetailServices services;
  final String metric;
  final String item;
  final String title;
  final int value;
  final int periodDays;

  @override
  State<SupportUsageDetailSheet> createState() =>
      _SupportUsageDetailSheetState();
}

class _SupportUsageDetailSheetState extends State<SupportUsageDetailSheet> {
  late Future<UsageDetail> _detail = _load();

  Future<UsageDetail> _load() => widget.services
      .getUsageDetail(
        metric: widget.metric,
        item: widget.item,
        periodDays: widget.periodDays,
      )
      .timeout(const Duration(seconds: 20));

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('support-usage-detail'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Text(widget.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('${widget.value}', style: theme.textTheme.headlineMedium),
        Text(
          strings.detailCounts(widget.metric, widget.item),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<UsageDetail>(
          future: _detail,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              AppErrors.caught('support_usage_detail.load', snapshot.error!);
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(strings.usageFailed),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(() => _detail = _load()),
                      child: Text(strings.retry),
                    ),
                  ],
                ),
              );
            }
            final detail = snapshot.requireData;
            final perDay = detail.daily.fold<int>(0, (sum, d) => sum + d.value);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  strings.detailDaily(widget.metric, widget.item),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                UsageBars(
                  key: const ValueKey('support-usage-detail-daily'),
                  days: detail.daily,
                  tooltip: (day) => '${supportDate(day.day)}: ${day.value}',
                ),
                if (perDay == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      strings.detailNoneInPeriod,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                for (final group in detail.groups) _GroupView(group: group),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GroupView extends StatelessWidget {
  const _GroupView({required this.group});
  final UsageGroup group;

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final peak = group.rows.fold<int>(
      0,
      (top, row) => row.value > top ? row.value : top,
    );
    return Padding(
      key: ValueKey('support-usage-group-${group.group}'),
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.detailGroup(group.group),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (group.rows.isEmpty) Text(strings.none),
          for (final row in group.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      row.label ?? strings.detailKey(group.group, row.key),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 8,
                          width: peak == 0
                              ? 0
                              : (constraints.maxWidth * row.value / peak).clamp(
                                  2,
                                  constraints.maxWidth,
                                ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${row.value}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One thin bar per day, rounded at the top and anchored to the baseline;
/// a tooltip on each day gives the number.
class UsageBars extends StatelessWidget {
  const UsageBars({super.key, required this.days, required this.tooltip});
  final List<({DateTime day, int value})> days;
  final String Function(({DateTime day, int value}) day) tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = Theme.of(context).textTheme.labelSmall;
    final peak = days.fold<int>(
      0,
      (top, day) => day.value > top ? day.value : top,
    );
    const height = 120.0;
    return SizedBox(
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
                      message: tooltip(day),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          // The whole column height is the hit target.
                          height: height,
                          alignment: Alignment.bottomCenter,
                          color: Colors.transparent,
                          child: Container(
                            height: peak == 0 || day.value == 0
                                ? 0
                                : (height * day.value / peak).clamp(2, height),
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
                  Text(supportDate(days.first.day), style: labels),
                  Text('max $peak', style: labels),
                  Text(supportDate(days.last.day), style: labels),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
