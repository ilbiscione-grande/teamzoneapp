import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/calendar/referee_services.dart';

/// REF-01: the home page for referees and referee assigners. Requests to
/// answer, offers waiting for the team, confirmed assignments, and a search
/// among scheduled matches to offer to referee.
class RefereeHome extends StatefulWidget {
  const RefereeHome({
    super.key,
    required this.services,
    this.showMatchSearch = true,
  });
  final RefereeServices services;

  /// The search among all clubs' matches is for federation referees; club
  /// referees find their own club's open places on their own page.
  final bool showMatchSearch;

  @override
  State<RefereeHome> createState() => _RefereeHomeState();
}

class _RefereeHomeState extends State<RefereeHome> {
  late Future<List<RefereeAssignment>> _items = widget.services.myAssignments();
  bool _busy = false;

  void _reload() {
    final next = widget.services.myAssignments();
    setState(() {
      _items = next;
    });
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
        _reload();
      }
    } catch (error) {
      AppErrors.caught('referee_home._run', error);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(refereeErrorText(error))));
        _reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RefereeMatchSearchPage(services: widget.services),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<RefereeAssignment>>(
      future: _items,
      builder: (context, snapshot) {
        final items = snapshot.data;
        final toAnswer = items?.where((item) => item.awaitingMe).toList() ?? [];
        final waiting =
            items
                ?.where(
                  (item) =>
                      item.referee.state == 'awaiting_team' ||
                      item.referee.state == 'awaiting_coordinator',
                )
                .toList() ??
            [];
        final confirmed =
            items
                ?.where(
                  (item) =>
                      item.referee.state == 'confirmed' &&
                      item.match.endsAt.isAfter(DateTime.now()),
                )
                .toList() ??
            [];
        return Column(
          key: const ValueKey('referee-home'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showMatchSearch)
              Card(
                child: ListTile(
                  key: const ValueKey('referee-search-matches'),
                  leading: const Icon(Icons.search),
                  title: const Text('Sök matcher att döma'),
                  subtitle: const Text(
                    'Alla schemalagda matcher. Anmäl dig, så bekräftar laget.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openSearch,
                ),
              ),
            if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Domaruppdragen kunde inte hämtas.'),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Försök igen'),
                    ),
                  ],
                ),
              )
            else if (items == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _section(
                theme,
                'Att svara på',
                toAnswer,
                empty: 'Inga förfrågningar från lag just nu.',
              ),
              _section(theme, 'Väntar på svar', waiting),
              _section(
                theme,
                'Bekräftade uppdrag',
                confirmed,
                empty: 'Inga bekräftade uppdrag ännu.',
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _section(
    ThemeData theme,
    String title,
    List<RefereeAssignment> items, {
    String? empty,
  }) {
    if (items.isEmpty && empty == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Text(empty!, style: theme.textTheme.bodySmall)
          else
            for (final item in items) _assignment(item),
        ],
      ),
    );
  }

  Widget _assignment(RefereeAssignment item) {
    final material = MaterialLocalizations.of(context);
    final start = item.match.startsAt.toLocal();
    return Card(
      key: ValueKey('referee-assignment-${item.referee.id}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.match.matchup,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              [
                '${material.formatMediumDate(start)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(start))}',
                ?item.match.location,
              ].join(' · '),
            ),
            Text(
              '${refereeSlotLabel(item.referee.slot)} · ${item.referee.name}',
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (item.awaitingMe) ...[
                  OutlinedButton(
                    key: ValueKey('referee-decline-${item.referee.id}'),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () =>
                                widget.services.respond(item.referee.id, false),
                            'Förfrågan är nekad.',
                          ),
                    child: const Text('Neka'),
                  ),
                  FilledButton(
                    key: ValueKey('referee-accept-${item.referee.id}'),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () =>
                                widget.services.respond(item.referee.id, true),
                            'Uppdraget är bekräftat.',
                          ),
                    child: const Text('Acceptera'),
                  ),
                ] else
                  TextButton(
                    key: ValueKey('referee-withdraw-${item.referee.id}'),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.services.withdraw(item.referee.id),
                            item.referee.state == 'confirmed'
                                ? 'Uppdraget är lämnat. Laget får besked.'
                                : 'Anmälan är återtagen.',
                          ),
                    child: Text(
                      item.referee.state == 'confirmed'
                          ? 'Lämna uppdraget'
                          : 'Ta tillbaka anmälan',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Scheduled matches in the coming weeks; pick an open place to offer.
class RefereeMatchSearchPage extends StatefulWidget {
  const RefereeMatchSearchPage({super.key, required this.services});
  final RefereeServices services;

  @override
  State<RefereeMatchSearchPage> createState() => _RefereeMatchSearchPageState();
}

class _RefereeMatchSearchPageState extends State<RefereeMatchSearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  late DateTimeRange _range = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now().add(const Duration(days: 30)),
  );
  late Future<List<RefereeMatch>> _matches = _load();
  late final Future<List<RefereePerson>> _people = widget.services
      .myRefereePeople();

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<List<RefereeMatch>> _load() => widget.services.searchMatches(
    _query.text.trim(),
    _range.start,
    _range.end,
  );

  void _reload() {
    final next = _load();
    setState(() {
      _matches = next;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    // At most two months at a time, like the server.
    final end = picked.end.difference(picked.start).inDays > 62
        ? picked.start.add(const Duration(days: 62))
        : picked.end;
    _range = DateTimeRange(start: picked.start, end: end);
    _reload();
  }

  Future<void> _offer(RefereeMatch match) async {
    final people = await _people.catchError((_) => const <RefereePerson>[]);
    if (!mounted) return;
    if (people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Du har ingen domarroll just nu.')),
      );
      return;
    }
    final open = match.openSlots;
    if (open.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alla domarplatser är tillsatta.')),
      );
      return;
    }
    var slot = open.first;
    var person = people.firstWhere(
      (item) => item.self,
      orElse: () => people.first,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Anmäl till matchen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(match.matchup),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('referee-offer-slot'),
                initialValue: slot,
                decoration: const InputDecoration(labelText: 'Plats'),
                items: [
                  for (final item in open)
                    DropdownMenuItem(
                      value: item,
                      child: Text(refereeSlotLabel(item)),
                    ),
                ],
                onChanged: (value) => setDialog(() => slot = value ?? slot),
              ),
              if (people.length > 1)
                DropdownButtonFormField<String>(
                  key: const ValueKey('referee-offer-person'),
                  initialValue: person.personId,
                  decoration: const InputDecoration(labelText: 'Domare'),
                  items: [
                    for (final item in people)
                      DropdownMenuItem(
                        value: item.personId,
                        child: Text(
                          item.self ? '${item.name} (du)' : item.name,
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialog(
                    () => person = people.firstWhere(
                      (item) => item.personId == value,
                      orElse: () => person,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Text('Lagets ledare bekräftar anmälan.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              key: const ValueKey('referee-offer-send'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Anmäl'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.services.request(match.eventId, slot, person.personId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anmälan är skickad. Laget får en notis.'),
        ),
      );
      _reload();
    } catch (error) {
      AppErrors.caught('referee_home._offer', error);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(refereeErrorText(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sök matcher')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SearchBar(
              key: const ValueKey('referee-match-query'),
              controller: _query,
              leading: const Icon(Icons.search),
              hintText: 'Lag, klubb, motståndare eller plats',
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _reload);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  '${material.formatShortDate(_range.start)} – ${material.formatShortDate(_range.end)}',
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RefereeMatch>>(
              future: _matches,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: _reload,
                      child: const Text(
                        'Matcherna kunde inte hämtas. Försök igen.',
                      ),
                    ),
                  );
                }
                final matches = snapshot.data;
                if (matches == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (matches.isEmpty) {
                  return const Center(child: Text('Inga matcher i perioden.'));
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final match in matches)
                      Card(
                        key: ValueKey('referee-match-${match.eventId}'),
                        child: ListTile(
                          title: Text(match.matchup),
                          subtitle: Text(
                            [
                              '${material.formatMediumDate(match.startsAt.toLocal())} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(match.startsAt.toLocal()))}',
                              ?match.location,
                              match.openSlots.isEmpty
                                  ? 'Domare tillsatta'
                                  : match.slotCount == 0
                                  ? 'Söker domare'
                                  : '${match.openSlots.length} av ${match.slotCount} platser lediga',
                            ].join(' · '),
                          ),
                          trailing: match.openSlots.isEmpty
                              ? null
                              : const Icon(Icons.add_circle_outline),
                          onTap: match.openSlots.isEmpty
                              ? null
                              : () => _offer(match),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
