part of '../../app/teamzone_app.dart';

class _AssistantEventTimeDialog extends StatefulWidget {
  const _AssistantEventTimeDialog({
    required this.event,
    required this.calendar,
    required this.teamLabel,
  });
  final EventDetails event;
  final CalendarServices calendar;
  final String teamLabel;
  @override
  State<_AssistantEventTimeDialog> createState() =>
      _AssistantEventTimeDialogState();
}

class _AssistantEventTimeDialogState extends State<_AssistantEventTimeDialog> {
  late DateTime _start = widget.event.startsAt.toLocal();
  late DateTime _end = widget.event.endsAt.toLocal();
  bool _busy = false;
  String? _error, _payload, _command;

  Future<void> _pick(bool start) async {
    final initial = start ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5),
    );
    if (date == null || !mounted) return;
    TimeOfDay? time;
    if (!widget.event.allDay) {
      time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (time == null || !mounted) return;
    }
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    setState(() {
      if (start) {
        final duration = _end.difference(_start);
        _start = value;
        _end = value.add(duration);
      } else {
        _end = value;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'Sluttiden måste vara efter starttiden.');
      return;
    }
    final payload = '${_start.toUtc()}/${_end.toUtc()}';
    if (_payload != payload) {
      _payload = payload;
      _command = _newUuid();
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.calendar.reviseEvent(
        eventId: widget.event.id,
        scope: 'one',
        patch: {
          'starts_at': _start.toUtc().toIso8601String(),
          'ends_at': _end.toUtc().toIso8601String(),
        },
        expectedRevision: widget.event.revision,
        idempotencyKey: _command!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Kunde inte bekräfta sparandet. Försök igen. Om aktiviteten har ändrats, stäng och öppna kortet igen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    String stamp(DateTime time) =>
        '${material.formatMediumDate(time)}${widget.event.allDay ? '' : ' · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(time))}'}';
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Ändra tid'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.event.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(widget.teamLabel),
                const SizedBox(height: 12),
                const Text(
                  'Tiderna visas i din lokala tidszon. Ändringen gäller bara detta tillfälle.',
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start'),
                  subtitle: Text(stamp(_start)),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: _busy ? null : () => _pick(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.event.allDay
                        ? 'Slut (första dagen efter aktiviteten)'
                        : 'Slut',
                  ),
                  subtitle: Text(stamp(_end)),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: _busy ? null : () => _pick(false),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Sparar…' : 'Spara tid'),
          ),
        ],
      ),
    );
  }
}
