import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/support_log_strings.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/support/support_clubs_tab.dart'
    show supportDate;
import 'package:teamzone_app/src/features/support/support_log_services.dart';

/// Logg on the support admin page (part 5): what support has done, newest
/// first, per day, with who did it and the reason. Filters on area, and
/// opened clubs only when asked for.
class SupportLogTab extends StatefulWidget {
  const SupportLogTab({super.key, required this.services});
  final SupportLogServices services;

  @override
  State<SupportLogTab> createState() => _SupportLogTabState();
}

class _SupportLogTabState extends State<SupportLogTab> {
  static const _areas = <String?>[null, 'clubs', 'admins', 'cases'];
  String? _area;
  bool _includeViews = false;
  final _entries = <SupportLogEntry>[];
  bool _more = false;
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) {
        _entries.clear();
        _more = false;
      }
    });
    try {
      final page = await widget.services
          .listSupportActions(
            area: _area,
            includeViews: _includeViews,
            before: reset || _entries.isEmpty ? null : _entries.last.occurredAt,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries.addAll(page.entries);
        _more = page.more;
        _loading = false;
      });
    } catch (error) {
      AppErrors.caught('support_log_tab.load', error);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final log = SupportLogStrings.of(context);
    final theme = Theme.of(context);
    String? lastDay;
    return ListView(
      key: const ValueKey('support-log'),
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final area in _areas)
              ChoiceChip(
                key: ValueKey('support-log-area-${area ?? 'all'}'),
                label: Text(log.area(area)),
                selected: _area == area,
                onSelected: (_) {
                  _area = area;
                  _load(reset: true);
                },
              ),
            FilterChip(
              key: const ValueKey('support-log-views'),
              label: Text(log.includeViews),
              selected: _includeViews,
              onSelected: (value) {
                _includeViews = value;
                _load(reset: true);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!_loading && !_failed && _entries.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text(log.empty)),
        for (final entry in _entries) ...[
          if (supportDate(entry.occurredAt) != lastDay)
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                lastDay = supportDate(entry.occurredAt),
                style: theme.textTheme.titleSmall,
              ),
            ),
          _EntryCard(entry: entry),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_failed)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(log.failed),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _load(reset: _entries.isEmpty),
                  child: Text(strings.retry),
                ),
              ],
            ),
          )
        else if (_more)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: OutlinedButton(
                key: const ValueKey('support-log-more'),
                onPressed: () => _load(reset: false),
                child: Text(log.more),
              ),
            ),
          ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});
  final SupportLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final log = SupportLogStrings.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final time = TimeOfDay.fromDateTime(entry.occurredAt).format(context);
    final actor = entry.actor.isEmpty ? log.noName : entry.actor;
    final about = [?entry.club, ?entry.target].join(' · ');
    final reason = entry.reason?.trim() ?? '';
    return Card(
      key: ValueKey('support-log-entry-${entry.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    log.action(entry.type),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(time, style: muted),
              ],
            ),
            if (about.isNotEmpty) Text(about),
            Text(entry.actorIsMe ? '$actor (${log.you})' : actor, style: muted),
            if (reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(log.reason(reason)),
              ),
            for (final note in log.notes(entry.details))
              Text(note, style: muted),
          ],
        ),
      ),
    );
  }
}
