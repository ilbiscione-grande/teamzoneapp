import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/calendar/referee_services.dart';

/// REF-01: the match's referees on EventDetails → Info. Everyone who sees
/// the match sees who referees; the team's event managers choose how many
/// (1–3), propose referees from TeamZone or write one in, and answer
/// referees who offer to referee.
class EventRefereesSection extends StatefulWidget {
  const EventRefereesSection({
    super.key,
    required this.eventId,
    required this.services,
  });
  final String eventId;

  /// Null when the calendar has no referee service (then nothing shows).
  final RefereeServices? services;

  @override
  State<EventRefereesSection> createState() => _EventRefereesSectionState();
}

class _EventRefereesSectionState extends State<EventRefereesSection> {
  late Future<EventRefereeView?> _view = _load();
  bool _busy = false;

  Future<EventRefereeView?> _load() async {
    final services = widget.services;
    if (services == null) return null;
    try {
      return await services
          .getEventReferees(widget.eventId)
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      AppErrors.caught('event_referees._load', error);
      return null;
    }
  }

  void _reload() {
    final next = _load();
    setState(() {
      _view = next;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _reload();
    } catch (error) {
      AppErrors.caught('event_referees._run', error);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(refereeErrorText(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(String slot) async {
    final services = widget.services;
    if (services == null) return;
    final choice = await showModalBottomSheet<_RefereeChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RefereePicker(services: services, slot: slot),
    );
    if (choice == null || !mounted) return;
    await _run(
      () => services.propose(
        widget.eventId,
        slot,
        personId: choice.personId,
        writtenName: choice.writtenName,
      ),
    );
  }

  String _stateLabel(EventReferee referee) => switch (referee.state) {
    'awaiting_referee' => 'Väntar på svar från domaren',
    'awaiting_team' => 'Vill döma matchen',
    _ => referee.external ? 'Inskriven av laget' : 'Bekräftad',
  };

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    if (services == null) return const SizedBox.shrink();
    return FutureBuilder<EventRefereeView?>(
      future: _view,
      builder: (context, snapshot) {
        final view = snapshot.data;
        if (view == null) return const SizedBox.shrink();
        if (view.slots == 0 && view.referees.isEmpty && !view.canManage) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        return Card(
          key: const ValueKey('event-referees'),
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sports),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Domare', style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
                if (view.canManage) ...[
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    key: const ValueKey('event-referee-count'),
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Ingen')),
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                    ],
                    selected: {view.slots},
                    onSelectionChanged: _busy
                        ? null
                        : (value) => _run(
                            () =>
                                services.setSlots(widget.eventId, value.first),
                          ),
                  ),
                ],
                for (final slot in refereeSlots.take(view.slots))
                  _slot(context, view, slot),
                if (view.slots == 0 && view.canManage)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Välj hur många domare matchen ska ha. Domare kan också anmäla sig själva till matchen.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _slot(BuildContext context, EventRefereeView view, String slot) {
    final services = widget.services!;
    final referee = view.inSlot(slot);
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('event-referee-slot-$slot'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(refereeSlotLabel(slot)),
            subtitle: Text(
              referee == null
                  ? 'Ledig'
                  : [
                      referee.name,
                      ?referee.clubName,
                      _stateLabel(referee),
                    ].join(' · '),
            ),
            trailing: view.canManage
                ? referee == null
                      ? TextButton(
                          key: ValueKey('event-referee-add-$slot'),
                          onPressed: _busy ? null : () => _add(slot),
                          child: const Text('Lägg till'),
                        )
                      : IconButton(
                          key: ValueKey('event-referee-remove-$slot'),
                          tooltip: 'Ta bort domaren',
                          onPressed: _busy
                              ? null
                              : () => _run(() => services.withdraw(referee.id)),
                          icon: const Icon(Icons.close),
                        )
                : null,
          ),
          if (view.canManage && referee?.state == 'awaiting_team')
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton(
                  key: ValueKey('event-referee-decline-$slot'),
                  onPressed: _busy
                      ? null
                      : () => _run(() => services.respond(referee!.id, false)),
                  child: const Text('Neka'),
                ),
                FilledButton(
                  key: ValueKey('event-referee-accept-$slot'),
                  onPressed: _busy
                      ? null
                      : () => _run(() => services.respond(referee!.id, true)),
                  child: const Text('Godkänn'),
                ),
              ],
            ),
          if (referee?.state == 'awaiting_referee')
            Text(
              'Domaren eller domarklubbens tillsättare bekräftar.',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _RefereeChoice {
  const _RefereeChoice({this.personId, this.writtenName});
  final String? personId, writtenName;
}

/// Search referees in TeamZone, or write in one who is not.
class _RefereePicker extends StatefulWidget {
  const _RefereePicker({required this.services, required this.slot});
  final RefereeServices services;
  final String slot;

  @override
  State<_RefereePicker> createState() => _RefereePickerState();
}

class _RefereePickerState extends State<_RefereePicker> {
  final _query = TextEditingController();
  final _written = TextEditingController();
  Timer? _debounce;
  List<RefereeCandidate>? _results;
  bool _writeIn = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _written.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final text = value.trim();
      if (text.length < 2) {
        if (mounted) setState(() => _results = null);
        return;
      }
      try {
        final results = await widget.services.searchReferees(text);
        if (mounted && _query.text.trim() == text) {
          setState(() => _results = results);
        }
      } catch (error) {
        AppErrors.caught('event_referees._search', error);
        if (mounted) setState(() => _results = const []);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            refereeSlotLabel(widget.slot),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Sök i TeamZone')),
              ButtonSegment(value: true, label: Text('Skriv in namn')),
            ],
            selected: {_writeIn},
            onSelectionChanged: (value) =>
                setState(() => _writeIn = value.first),
          ),
          const SizedBox(height: 12),
          if (_writeIn) ...[
            TextField(
              key: const ValueKey('referee-written-name'),
              controller: _written,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Domarens namn',
                helperText:
                    'För en domare som inte finns i TeamZone. Sparas direkt som bekräftad.',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('referee-written-save'),
                onPressed: () {
                  final name = _written.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(context, _RefereeChoice(writtenName: name));
                },
                child: const Text('Spara'),
              ),
            ),
          ] else ...[
            TextField(
              key: const ValueKey('referee-search'),
              controller: _query,
              autofocus: true,
              onChanged: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Sök domare eller domarklubb',
              ),
            ),
            const SizedBox(height: 8),
            if (_results == null)
              Text(
                'Skriv minst två bokstäver.',
                style: theme.textTheme.bodySmall,
              )
            else if (_results!.isEmpty)
              Text(
                'Ingen träff. Du kan skriva in domaren i stället.',
                style: theme.textTheme.bodySmall,
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final candidate in _results!)
                      ListTile(
                        key: ValueKey(
                          'referee-candidate-${candidate.personId}',
                        ),
                        leading: const Icon(Icons.sports),
                        title: Text(candidate.name),
                        subtitle: Text(
                          [
                            candidate.clubName,
                            candidate.confirmable
                                ? 'bekräftar förfrågan'
                                : 'läggs till direkt',
                          ].join(' · '),
                        ),
                        onTap: () => Navigator.pop(
                          context,
                          _RefereeChoice(personId: candidate.personId),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
