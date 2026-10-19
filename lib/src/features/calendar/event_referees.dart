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

  Future<void> _assignClub(String slot) async {
    final services = widget.services;
    if (services == null) return;
    final candidates = await services
        .candidates(widget.eventId)
        .catchError((_) => const <ClubRefereeInfo>[]);
    if (!mounted) return;
    final picked = await showModalBottomSheet<ClubRefereeInfo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            refereeSlotLabel(slot),
            style: Theme.of(sheetContext).textTheme.titleMedium,
          ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Inga föreningsdomare att välja.'),
            ),
          for (final candidate in candidates)
            ListTile(
              key: ValueKey('event-club-candidate-${candidate.personId}'),
              leading: Icon(
                candidate.clash || candidate.ageOk == false
                    ? Icons.warning_amber_outlined
                    : Icons.sports,
              ),
              title: Text(candidate.name),
              subtitle: Text(
                [
                  '${candidate.seasonCount} uppdrag i år',
                  if (candidate.clash) 'krockar med annat',
                  if (candidate.ageOk == false) 'för ung för laget',
                ].join(' · '),
              ),
              onTap: () => Navigator.pop(sheetContext, candidate),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _run(
      () => services.propose(widget.eventId, slot, personId: picked.personId),
    );
  }

  /// REF-02: the domaransvarig asks whether a club referee refereed.
  Future<void> _answerControl(String reportId, bool confirmed) async {
    final services = widget.services;
    if (services == null) return;
    String? note;
    if (!confirmed) {
      var text = '';
      note = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Domaren dömde inte'),
          content: TextField(
            key: const ValueKey('referee-control-note'),
            autofocus: true,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Vad hände? (frivilligt)',
            ),
            onChanged: (value) => text = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              key: const ValueKey('referee-control-note-send'),
              onPressed: () => Navigator.pop(dialogContext, text.trim()),
              child: const Text('Skicka'),
            ),
          ],
        ),
      );
      if (note == null || !mounted) return;
    }
    await _run(() => services.answerControl(reportId, confirmed, note: note));
  }

  Widget _controlQuestion(
    BuildContext context,
    ({String id, String slot, String name}) question,
  ) => Container(
    key: ValueKey('event-referee-control-${question.id}'),
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Kontrollfråga från domaransvarig: dömde ${question.name} matchen som ${refereeSlotLabel(question.slot).toLowerCase()}?',
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            OutlinedButton(
              key: ValueKey('event-referee-control-no-${question.id}'),
              onPressed: _busy
                  ? null
                  : () => _answerControl(question.id, false),
              child: const Text('Nej'),
            ),
            FilledButton(
              key: ValueKey('event-referee-control-yes-${question.id}'),
              onPressed: _busy ? null : () => _answerControl(question.id, true),
              child: const Text('Ja'),
            ),
          ],
        ),
      ],
    ),
  );

  String _stateLabel(EventReferee referee) => switch (referee.state) {
    'awaiting_referee' => 'Väntar på svar från domaren',
    'awaiting_team' => 'Vill döma matchen',
    'awaiting_coordinator' => 'Anmäld – väntar på domaransvarig',
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
        final organiser = view.canManage || view.canManageClubReferees;
        if (view.slots == 0 &&
            view.referees.isEmpty &&
            view.controlQuestions.isEmpty &&
            !organiser) {
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
                // REF-02: förbundsdomare, föreningsdomare or none.
                if (organiser)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('event-referee-kind'),
                      initialValue: view.refereeKind,
                      decoration: const InputDecoration(
                        labelText: 'Typ av domare',
                      ),
                      items: [
                        for (final kind in const ['federation', 'club', 'none'])
                          DropdownMenuItem(
                            value: kind,
                            child: Text(refereeKindLabel(kind)),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (kind) {
                              if (kind == null) return;
                              _run(
                                () => services.setKind(widget.eventId, kind),
                              );
                            },
                    ),
                  )
                else if (view.refereeKind != null)
                  Text(refereeKindLabel(view.refereeKind)),
                if (view.canManage && view.refereeKind != 'none') ...[
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
                for (final question in view.controlQuestions)
                  _controlQuestion(context, question),
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
            trailing:
                view.refereeKind == 'club' &&
                    referee == null &&
                    view.canManageClubReferees
                ? TextButton(
                    key: ValueKey('event-referee-assign-club-$slot'),
                    onPressed: _busy ? null : () => _assignClub(slot),
                    child: const Text('Tillsätt'),
                  )
                : view.canManage && view.refereeKind != 'club'
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
          if (view.canManageClubReferees &&
              referee?.state == 'awaiting_coordinator')
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => services.respond(referee!.id, false)),
                  child: const Text('Neka'),
                ),
                FilledButton(
                  key: ValueKey('event-referee-approve-$slot'),
                  onPressed: _busy
                      ? null
                      : () => _run(() => services.respond(referee!.id, true)),
                  child: const Text('Godkänn'),
                ),
              ],
            ),
          if (view.refereeKind == 'club' &&
              referee == null &&
              !view.canManageClubReferees)
            Text(
              'Klubbens domaransvarige tillsätter föreningsdomare.',
              style: theme.textTheme.bodySmall,
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

/// One search field: referees in TeamZone as you type, and when the one
/// you look for is not there, adding them by the name you wrote.
class _RefereePicker extends StatefulWidget {
  const _RefereePicker({required this.services, required this.slot});
  final RefereeServices services;
  final String slot;

  @override
  State<_RefereePicker> createState() => _RefereePickerState();
}

class _RefereePickerState extends State<_RefereePicker> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<RefereeCandidate>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final text = value.trim();
    if (text.length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
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
    final text = _query.text.trim();
    final results = _results;
    // Offered once a search is done and no hit has exactly that name.
    final canAdd =
        results != null &&
        text.length >= 2 &&
        !results.any(
          (candidate) => candidate.name.toLowerCase() == text.toLowerCase(),
        );
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
          TextField(
            key: const ValueKey('referee-search'),
            controller: _query,
            autofocus: true,
            maxLength: 120,
            onChanged: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Sök domare',
              counterText: '',
              suffixIcon: text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Rensa',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _query.clear();
                        _search('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          if (results == null)
            Text(
              'Skriv domarens namn eller domarklubb.',
              style: theme.textTheme.bodySmall,
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final candidate in results)
                    ListTile(
                      key: ValueKey('referee-candidate-${candidate.personId}'),
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
                  if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Ingen domare i TeamZone heter så.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (canAdd)
                    ListTile(
                      key: const ValueKey('referee-add-written'),
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: Text('Lägg till "$text"'),
                      subtitle: const Text(
                        'För en domare som inte finns i TeamZone. Sparas direkt som bekräftad.',
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        _RefereeChoice(writtenName: text),
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
