part of '../../app/teamzone_app.dart';

/// A leader group's coming meetings on its card. A meeting is an activity in every member's calendar.
class _LeaderGroupMeetings extends StatelessWidget {
  const _LeaderGroupMeetings({required this.group, required this.onOpen});
  final LeaderGroup group;
  final ValueChanged<LeaderGroupMeeting> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final meeting in group.meetings.take(3))
        ListTile(
          key: ValueKey('leader-group-meeting-${meeting.id}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(meeting.title),
          subtitle: Text(
            [
              _meetingWhen(context, meeting.startsAt, meeting.endsAt),
              if (meeting.location case final place? when place.isNotEmpty)
                place,
            ].join(' · '),
          ),
          onTap: () => onOpen(meeting),
        ),
      if (group.meetings.length > 3)
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 4),
          child: Text(
            'och ${group.meetings.length - 3} till i kalendern',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
}

String _meetingWhen(BuildContext context, DateTime start, DateTime end) {
  final material = MaterialLocalizations.of(context);
  String time(DateTime value) => material.formatTimeOfDay(
    TimeOfDay.fromDateTime(value),
    alwaysUse24HourFormat: true,
  );
  return '${material.formatMediumDate(start)} ${time(start)}–${time(end)}';
}

/// Title, day, time, place and agenda of a new group meeting.
class _LeaderGroupMeetingDialog extends StatefulWidget {
  const _LeaderGroupMeetingDialog({
    required this.group,
    required this.services,
  });
  final LeaderGroup group;
  final LeaderGroupServices services;

  @override
  State<_LeaderGroupMeetingDialog> createState() =>
      _LeaderGroupMeetingDialogState();
}

class _LeaderGroupMeetingDialogState extends State<_LeaderGroupMeetingDialog> {
  late final _title = TextEditingController(
    text: 'Möte i ${widget.group.name}',
  );
  final _place = TextEditingController();
  final _agenda = TextEditingController();
  late DateTime _day = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 7)),
  );
  TimeOfDay _start = const TimeOfDay(hour: 18, minute: 30);
  TimeOfDay _end = const TimeOfDay(hour: 20, minute: 0);
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _agenda.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay time) =>
      DateTime(_day.year, _day.month, _day.day, time.hour, time.minute);

  bool get _valid =>
      _title.text.trim().isNotEmpty && _at(_end).isAfter(_at(_start));

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: today.add(const Duration(days: 400)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        final length =
            (_end.hour * 60 + _end.minute) - (_start.hour * 60 + _start.minute);
        _start = picked;
        final endMinutes =
            picked.hour * 60 + picked.minute + (length > 0 ? length : 90);
        _end = endMinutes < 24 * 60
            ? TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60)
            : const TimeOfDay(hour: 23, minute: 59);
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final id = await widget.services.createMeeting(
        groupId: widget.group.id,
        title: _title.text.trim(),
        startsAt: _at(_start),
        endsAt: _at(_end),
        location: _place.text.trim().isEmpty ? null : _place.text.trim(),
        agenda: _agenda.text.trim().isEmpty ? null : _agenda.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(id);
    } catch (error) {
      final code = error is LeaderGroupException ? error.code : null;
      if (code == null) {
        AppErrors.caught('leader_group_meetings._save', error);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            code == 'no_team'
                ? 'Klubben behöver minst ett lag för att boka möten.'
                : 'Mötet kunde inte bokas. Försök igen.',
          ),
        ),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    String time(TimeOfDay value) =>
        material.formatTimeOfDay(value, alwaysUse24HourFormat: true);
    return AlertDialog(
      key: const ValueKey('leader-group-meeting-dialog'),
      title: const Text('Nytt möte'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alla ${widget.group.memberCount} i gruppen får en kallelse och '
                'mötet hamnar i deras kalender. Fler kan bjudas in under '
                'Deltagare på mötet.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('leader-group-meeting-title'),
                controller: _title,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Rubrik'),
                onChanged: (_) => setState(() {}),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('leader-group-meeting-day'),
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(material.formatMediumDate(_day)),
                  ),
                  OutlinedButton(
                    key: const ValueKey('leader-group-meeting-start'),
                    onPressed: () => _pickTime(true),
                    child: Text('Från ${time(_start)}'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('leader-group-meeting-end'),
                    onPressed: () => _pickTime(false),
                    child: Text('Till ${time(_end)}'),
                  ),
                ],
              ),
              if (!_at(_end).isAfter(_at(_start)))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Mötet måste sluta efter att det börjar.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('leader-group-meeting-place'),
                controller: _place,
                decoration: const InputDecoration(
                  labelText: 'Plats',
                  hintText: 'Till exempel klubbstugan',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('leader-group-meeting-agenda'),
                controller: _agenda,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Dagordning'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          key: const ValueKey('leader-group-meeting-save'),
          onPressed: _saving || !_valid ? null : _save,
          child: const Text('Boka mötet'),
        ),
      ],
    );
  }
}
