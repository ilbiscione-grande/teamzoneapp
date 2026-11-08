import 'package:flutter/material.dart';
import 'booking_management_services.dart';
import 'calendar_models.dart';

String _when(Object? iso) {
  final date = DateTime.tryParse('$iso');
  if (date == null) return '$iso';
  // Virtual slots have no UTC offset: these are already the series' wall time.
  final d = date.isUtc ? date.toLocal() : date;
  String two(int n) => '$n'.padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

class EventBookingManagement extends StatefulWidget {
  const EventBookingManagement({
    super.key,
    required this.services,
    required this.bookings,
    required this.startsAt,
    required this.endsAt,
    required this.recurring,
    required this.onChanged,
  });
  final BookingManagementServices services;
  final List<EventBooking> bookings;
  final DateTime startsAt, endsAt;
  final bool recurring;
  final Future<void> Function() onChanged;
  @override
  State<EventBookingManagement> createState() => _EventBookingManagementState();
}

class _EventBookingManagementState extends State<EventBookingManagement> {
  BookingData? _data;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.recurring) _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.services.getSeriesPlan(
        widget.bookings.first.id,
      );
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) setState(() => _error = bookingManagementError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _control(String action) async {
    final plan = bookingMap(_data!['plan']);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.controlSeriesPlan(plan, action);
      await _load();
      await widget.onChanged();
    } catch (error) {
      // Keep the reviewed revision on an uncertain response, so retry uses the
      // same command key. A known stale revision requires explicit reload.
      if (mounted) setState(() => _error = bookingManagementError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => EventBookingChangeSheet(
        services: widget.services,
        bookings: widget.bookings
            .where(
              (b) =>
                  b.active && b.canCancel && b.startsAt.isAfter(DateTime.now()),
            )
            .toList(),
        startsAt: widget.startsAt,
        endsAt: widget.endsAt,
        recurring: widget.recurring,
      ),
    );
    if (saved == true && mounted) {
      await widget.onChanged();
      if (mounted && widget.recurring) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _data?['plan'] == null ? null : bookingMap(_data!['plan']);
    final slots = bookingRows(_data?['slots']);
    final blocked = slots.where((s) => s['state'] == 'blocked').toList();
    final editable =
        widget.bookings.any(
          (b) => b.active && b.canCancel && b.startsAt.isAfter(DateTime.now()),
        ) &&
        widget.startsAt.isAfter(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editable)
          FilledButton.tonalIcon(
            key: const Key('event-booking-change'),
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Ändra tid och resurser'),
          ),
        if (widget.recurring) ...[
          const SizedBox(height: 12),
          const Text(
            'Seriegrund och framtida tillfällen',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (plan != null) ...[
            Text(
              '${plan['state'] == 'active' ? 'Automatik aktiv' : 'Automatik pausad'} · till och med ${bookingMap(plan['configuration'])['ends_on']}',
            ),
            Text(
              '${slots.where((s) => s['state'] == 'created').length} skapade, ${slots.where((s) => s['state'] == 'queued').length} väntande och ${blocked.length} blockerade tillfällen.',
            ),
            const Text(
              'Automatiken skapar tillfällen 90 dagar framåt. Manuella ändringar och avbokningar bevaras. En paus avbokar inget.',
            ),
            if (plan['last_error'] != null)
              Text(
                bookingManagementError(plan['last_error']),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('event-series-toggle'),
                  onPressed: _busy
                      ? null
                      : () => _control(
                          plan['state'] == 'active' ? 'pause' : 'resume',
                        ),
                  child: Text(
                    plan['state'] == 'active'
                        ? 'Pausa automatiken'
                        : 'Återuppta automatiken',
                  ),
                ),
                if (blocked.isNotEmpty)
                  OutlinedButton(
                    key: const Key('event-series-retry'),
                    onPressed: _busy ? null : () => _control('retry'),
                    child: const Text('Försök igen med blockerade tillfällen'),
                  ),
              ],
            ),
            if (blocked.isNotEmpty)
              ExpansionTile(
                title: Text('Blockerade tillfällen (${blocked.length})'),
                children: [
                  for (final slot in blocked)
                    ListTile(
                      title: Text(_when(slot['local_start'])),
                      subtitle: Text(bookingSlotReason(slot['reason'])),
                    ),
                ],
              ),
          ] else if (_data != null)
            const Text(
              'Ingen seriegrund är aktiverad. Aktivera den från en återkommande bokning i Bokningshanteraren.',
            ),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Uppdatera seriegrund'),
          ),
        ],
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class EventBookingChangeSheet extends StatefulWidget {
  const EventBookingChangeSheet({
    super.key,
    required this.services,
    required this.bookings,
    required this.startsAt,
    required this.endsAt,
    required this.recurring,
  });
  final BookingManagementServices services;
  final List<EventBooking> bookings;
  final DateTime startsAt, endsAt;
  final bool recurring;
  @override
  State<EventBookingChangeSheet> createState() =>
      _EventBookingChangeSheetState();
}

class _EventBookingChangeSheetState extends State<EventBookingChangeSheet> {
  late String _anchor = widget.bookings.first.id;
  late DateTime _start = widget.startsAt.toLocal(),
      _end = widget.endsAt.toLocal();
  String _scope = 'booking';
  final _add = <String>{}, _remove = <String>{};
  List<BookingData> _existing = [];
  List<ResourceAvailability> _resources = [];
  BookingData? _preview, _reviewedParameters;
  bool _busy = false, _loaded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  BookingData _parameters() => {
    'target_booking_id': _anchor,
    'change_scope': _scope,
    'new_starts_at': _start.toUtc().toIso8601String(),
    'new_ends_at': _end.toUtc().toIso8601String(),
    'add_resource_ids': _add.toList()..sort(),
    'remove_resource_ids': _remove.toList()..sort(),
  };
  void _changed(VoidCallback action) => setState(() {
    action();
    _preview = null;
    _reviewedParameters = null;
    _error = null;
  });
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _loaded = false;
      _error = null;
      _preview = null;
    });
    try {
      // Always load the anchor's original occurrence, not the edited draft.
      final base = await widget.services.previewBookingChange({
        'target_booking_id': _anchor,
        'change_scope': 'booking',
        'new_starts_at': widget.startsAt.toUtc().toIso8601String(),
        'new_ends_at': widget.endsAt.toUtc().toIso8601String(),
        'add_resource_ids': <String>[],
        'remove_resource_ids': <String>[],
      });
      final resources = await widget.services.changeResources(base);
      if (mounted) {
        setState(() {
          _existing = bookingRows(
            bookingRows(base['contexts']).first['existing'],
          );
          _resources = resources;
          _loaded = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = bookingManagementError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool start) async {
    final old = start ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: old,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 732)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (value.year != date.year ||
        value.month != date.month ||
        value.day != date.day ||
        value.hour != time.hour ||
        value.minute != time.minute) {
      setState(
        () => _error =
            'Klocktiden finns inte vid tidsomställningen. Välj en annan tid.',
      );
      return;
    }
    _changed(() {
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
    });
  }

  Future<void> _review() async {
    if (!_end.isAfter(_start) || !_start.isAfter(DateTime.now())) {
      setState(() => _error = bookingManagementError('invalid_time'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    final parameters = _parameters();
    try {
      final preview = await widget.services.previewBookingChange(parameters);
      if (mounted) {
        setState(() {
          _preview = preview;
          _reviewedParameters = parameters;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = bookingManagementError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.saveBookingChange(_reviewedParameters!, _preview!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = bookingManagementError(error);
          if (error.toString().contains('stale_revision') ||
              error.toString().contains('booking_change_conflicts')) {
            _preview = null;
            _reviewedParameters = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        _preview != null &&
        bookingRows(_preview!['conflicts']).isEmpty &&
        ((_preview!['change_count'] as num?) ?? 0) > 0;
    return PopScope(
      canPop: !_busy,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ändra tid och resurser',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Alla berörda aktiviteter och resurser sparas tillsammans. Resursernas individuella tidsmarginaler bevaras.',
              ),
              if (_busy) const LinearProgressIndicator(),
              DropdownButtonFormField<String>(
                key: ValueKey('booking-anchor-$_anchor'),
                initialValue: _anchor,
                decoration: const InputDecoration(
                  labelText: 'Utgå från resurs',
                ),
                isExpanded: true,
                items: [
                  for (final b in widget.bookings)
                    DropdownMenuItem(
                      value: b.id,
                      child: Text('${b.resourceName} · ${b.organizationName}'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) {
                        if (id == null) return;
                        _changed(() {
                          _anchor = id;
                          _add.clear();
                          _remove.clear();
                        });
                        _load();
                      },
              ),
              if (widget.recurring)
                DropdownButtonFormField<String>(
                  initialValue: _scope,
                  decoration: const InputDecoration(
                    labelText: 'Ändringens omfattning',
                  ),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'booking',
                      child: Text('Bara detta tillfälle'),
                    ),
                    DropdownMenuItem(
                      value: 'event_forward',
                      child: Text('Detta och följande i aktivitetsserien'),
                    ),
                    DropdownMenuItem(
                      value: 'event_all',
                      child: Text('Hela den kommande aktivitetsserien'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => _changed(() => _scope = value!),
                ),
              if (_scope != 'booking')
                const Text(
                  'Tiderna ändras för kommande tillfällen i vald omfattning. Resursval ändras där utgångsresursen fortfarande är bokad. Andra manuella resursval behålls. Tidigare avbokade resurser återbokas inte.',
                ),
              OutlinedButton(
                key: const Key('booking-new-start'),
                onPressed: _busy ? null : () => _pick(true),
                child: Text('Ny start: ${_when(_start.toIso8601String())}'),
              ),
              OutlinedButton(
                key: const Key('booking-new-end'),
                onPressed: _busy ? null : () => _pick(false),
                child: Text('Nytt slut: ${_when(_end.toIso8601String())}'),
              ),
              const Text(
                'Tiderna ovan visas i enhetens tidszon. Serien följer aktivitetens lokala tidszon över sommar- och vintertid. Nya resurser får utgångsresursens tidsmarginaler.',
              ),
              if (_loaded) ...[
                const Text(
                  'Ta bort från bokningen',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final row in _existing)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${row['resource_name']}'),
                    subtitle: Text(
                      '${_when(row['starts_at'])}–${_when(row['ends_at'])}',
                    ),
                    value: _remove.contains(row['resource_id']),
                    onChanged: _busy
                        ? null
                        : (v) => _changed(() {
                            v!
                                ? _remove.add(row['resource_id'] as String)
                                : _remove.remove(row['resource_id']);
                          }),
                  ),
                const Text(
                  'Lägg till i bokningen',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final row in _resources.where(
                  (r) =>
                      !_existing.any((b) => b['resource_id'] == r.resourceId),
                ))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row.name),
                    subtitle: Text(
                      row.requiresApproval
                          ? 'Kräver godkännande'
                          : 'Bokas direkt',
                    ),
                    value: _add.contains(row.resourceId),
                    onChanged: _busy
                        ? null
                        : (v) => _changed(() {
                            v!
                                ? _add.add(row.resourceId)
                                : _add.remove(row.resourceId);
                          }),
                  ),
              ],
              if (_preview != null)
                BookingChangeConsequences(preview: _preview!),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                key: const Key('booking-change-submit'),
                onPressed: _busy || !_loaded
                    ? null
                    : ready
                    ? _save
                    : _review,
                child: Text(
                  ready
                      ? 'Bekräfta tid och resurser'
                      : 'Förhandsvisa ändringen',
                ),
              ),
              if (!_loaded && !_busy)
                TextButton(
                  onPressed: _load,
                  child: const Text('Hämta resurser igen'),
                ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Avbryt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookingChangeConsequences extends StatelessWidget {
  const BookingChangeConsequences({super.key, required this.preview});
  final BookingData preview;
  String _time(BookingData r) =>
      '${_when(r['starts_at'])}–${_when(r['ends_at'])}';
  String _status(BookingData r) =>
      r['status'] == 'pending' ? 'Väntar på godkännande' : 'Bokad';
  @override
  Widget build(BuildContext context) {
    final future = preview['future_plan'] == null
        ? null
        : bookingMap(preview['future_plan']);
    final timing = bookingMap(preview['timing']);
    final conflicts = bookingRows(preview['conflicts']);
    final unchanged = bookingRows(
      bookingMap(preview['selection'])['unchanged_contexts'],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const Text(
          'Kontrollera hela ändringen',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (future != null) ...[
          const Text(
            'Seriegrunden följer också ändringen',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${bookingRows(future['slots']).length} ännu inte skapade tillfällen följer ändringen.',
          ),
          Text(
            'Framtida resurser: ${bookingRows(bookingMap(future['configuration'])['resources']).map((r) => r['resource_name']).join(', ')}',
          ),
          Text(
            future['state'] == 'paused'
                ? 'Automatiken är pausad.'
                : 'Lediga tillfällen inom 90 dagar skapas när ändringen sparas.',
          ),
          for (final slot in bookingRows(future['slots']))
            Text(
              'Väntande: ${_when(slot['local_start'])}–${_when(slot['local_end'])}',
            ),
        ],
        for (final e in bookingRows(timing['events']))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${e['title']}'),
            subtitle: Text(
              '${_when(e['old_starts_at'])}–${_when(e['old_ends_at'])} → ${_time(e)}',
            ),
          ),
        for (final r in bookingRows(
          preview['final_bookings'],
        ).where((r) => r['id'] != null))
          Text(
            '${r['resource_name']}: ${_when(r['old_starts_at'])}–${_when(r['old_ends_at'])} → ${_time(r)} · ${_status(r)}',
          ),
        for (final c in bookingRows(preview['contexts'])) ...[
          Text(
            'Tillfälle ${_when(c['starts_at'])}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final r in bookingRows(c['add']))
            Text(
              'Läggs till: ${r['resource_name']} · ${_time(r)} · ${_status(r)}',
            ),
          for (final r in bookingRows(c['remove']))
            Text(
              'Tas bort: ${r['resource_name']} · ${_time(r)}. Avbokningen finns kvar i historiken.',
            ),
          for (final r in bookingRows(c['keep']))
            Text(
              'Behålls: ${r['resource_name']} · ${_time(r)} · ${_status(r)}',
            ),
          if (bookingRows(c['keep']).isEmpty && bookingRows(c['add']).isEmpty)
            const Text(
              'Inga aktiva resurser blir kvar på tillfället. Själva aktiviteten finns kvar.',
            ),
          for (final r in bookingRows(c['unchanged_resources']))
            Text(
              '${r['resource_name']}: ${r['reason'] == 'previously_cancelled' ? 'tidigare avbokad eller nekad – återbokas inte' : 'redan bokad – ingen dubblett'}',
            ),
        ],
        if (unchanged.isNotEmpty)
          Text(
            '${unchanged.length} tillfällen behåller andra manuella resursval; tiderna följer ändringen.',
          ),
        if (conflicts.isNotEmpty) ...[
          const Text(
            'Konflikter måste lösas före bekräftelse. Ingen ändring har sparats.',
          ),
          for (final c in conflicts)
            Text(
              '${_when(c['starts_at'])} · ${c['resource_name'] ?? 'Tillfället'}: ${bookingManagementError(c['reason'] ?? '')}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
        if (preview['change_count'] == 0)
          const Text('Ingen tid eller resurs behöver ändras med dina val.'),
        const Text(
          'Alla ändringar sparas tillsammans. Om en resurs hinner bli upptagen stoppas hela ändringen.',
        ),
        const Divider(),
      ],
    );
  }
}
