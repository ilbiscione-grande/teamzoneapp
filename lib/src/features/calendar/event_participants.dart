part of '../../app/teamzone_app.dart';

class _ParticipantsTab extends StatefulWidget {
  const _ParticipantsTab({
    required this.event,
    required this.squad,
    required this.calendar,
    required this.roster,
    required this.clubId,
    required this.onReload,
    required this.allowManage,
    required this.allowAttendance,
  });
  final EventDetails event;
  final SquadDetails squad;
  final CalendarServices calendar;
  final RosterServices roster;
  final String clubId;
  final Future<void> Function() onReload;
  final bool allowManage, allowAttendance;
  @override
  State<_ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends State<_ParticipantsTab> {
  final _searchController = TextEditingController();
  final _reasonController = TextEditingController();
  final Set<String> _selectedIds = {};
  final Map<String, String> _stagedStatus = {};
  final Map<String, int> _stagedMinutes = {};
  final Map<String, int> _stagedRevisions = {};
  final Map<String, Future<(RosterPersonDetails?, PersonAttendanceSummary?)>>
  _details = {};
  List<SquadCandidate> _candidates = const [];
  AttendancePermissions? _resolvedPermissions;
  String _query = '';
  String? _expandedId;
  bool _busy = false;
  bool _reviewingReminders = false;
  bool _permissionsFailed = false;
  String? _saveKey, _lockKey, _sendKey;
  String? _attendanceKey, _attendancePayload;
  final Map<String, String> _reminderKeys = {};
  SquadDetails? _preparedSquad;
  bool _locked = false;
  DateTime? _expiry;
  String _selectionSource = 'manual';
  Map<String, dynamic> _selectionContext = {};
  List<String>? _bulkMemberIds;
  Timer? _endTimer;

  bool get _readOnly =>
      widget.event.archivedAt != null || widget.event.state == 'cancelled';
  bool get _canManage =>
      !_readOnly && widget.allowManage && widget.squad.can('save_squad');
  bool get _eventEnded =>
      widget.event.state == 'completed' ||
      !widget.event.endsAt.isAfter(DateTime.now());
  bool get _canRecordAttendance =>
      !_readOnly &&
      widget.allowAttendance &&
      widget.squad.can('record_attendance') &&
      _resolvedPermissions?.canRecord == true &&
      (_resolvedPermissions?.lateWindow != true ||
          _resolvedPermissions?.canCorrectLate == true);
  bool get _working => _busy || _reviewingReminders;
  bool get _selectionFrozen =>
      _saveKey != null || widget.squad.state == 'locked';
  Set<String> get _draftMemberIds => _selectedIds;
  List<EventRosterPerson> get _people {
    final people = <String, EventRosterPerson>{
      for (final p in widget.squad.roster) p.personId: p,
      for (final p in _guestRosterFor(widget.squad)) p.personId: p,
    };
    for (final candidate in _candidates) {
      if (!_eventEnded &&
          (_selectedIds.contains(candidate.personId) || _query.isNotEmpty)) {
        people.putIfAbsent(
          candidate.personId,
          () => EventRosterPerson(
            personId: candidate.personId,
            name: candidate.name,
            teamId: candidate.teamId ?? '',
            teamName: candidate.teamName ?? '',
            rolePackage: candidate.rolePackage ?? 'player',
            inDraft: false,
            isGuest: candidate.eligibilityKind != 'team_assignment',
          ),
        );
      }
    }
    final result = people.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll([
      ...widget.squad.roster
          .where((p) => p.inDraft && !p.isCalled)
          .map((p) => p.personId),
      ..._guestRosterFor(
        widget.squad,
      ).where((p) => p.inDraft && !p.isCalled).map((p) => p.personId),
    ]);
    if (_canManage) unawaited(_loadCandidates());
    _loadPermissions();
    unawaited(_loadLeaderTitles());
    _scheduleEnd();
    if (widget.squad.state == 'locked') {
      _preparedSquad = widget.squad;
      _locked = true;
    }
  }

  // Leader titles ("Huvudtränare") shown after the name. Optional: without
  // roster access for a team the names simply show alone.
  Map<String, String> _leaderTitles = const {};

  Future<void> _loadLeaderTitles() async {
    final teamIds = {
      for (final p in widget.squad.roster)
        if (p.teamId.isNotEmpty &&
            (p.rolePackage == 'leader' || p.rolePackage == 'club_functionary'))
          p.teamId,
    };
    final titles = <String, String>{};
    for (final teamId in teamIds) {
      try {
        final roles = await widget.roster
            .listTeamRoles(clubId: widget.clubId, teamId: teamId)
            .timeout(const Duration(seconds: 15));
        if (!mounted) return;
        final strings = AppStrings.of(context);
        for (final role in roles.roles) {
          if (!_isLeaderRole(role.role)) continue;
          final summary = _titlesSummary(strings, role);
          if (summary.isNotEmpty) {
            titles.putIfAbsent(role.personId, () => summary);
          }
        }
      } catch (_) {}
    }
    if (mounted && titles.isNotEmpty) setState(() => _leaderTitles = titles);
  }

  void _scheduleEnd() {
    _endTimer?.cancel();
    final remaining = widget.event.endsAt.difference(DateTime.now());
    if (remaining > Duration.zero && !_eventEnded) {
      _endTimer = Timer(remaining, () {
        if (!mounted) return;
        setState(() {});
        _loadPermissions();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ParticipantsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedIds.removeAll(
      _people.where((p) => p.isCalled).map((p) => p.personId),
    );
    if (oldWidget.event.endsAt != widget.event.endsAt ||
        oldWidget.event.state != widget.event.state) {
      _scheduleEnd();
      _loadPermissions();
    }
  }

  @override
  void dispose() {
    _endTimer?.cancel();
    _searchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    try {
      final candidates = await widget.calendar.listSquadCandidates(
        widget.event.id,
      );
      if (mounted) setState(() => _candidates = candidates);
    } catch (_) {
      if (mounted) {
        _showError(
          'Sökningen kunde inte laddas. Lagets deltagare visas fortfarande.',
        );
      }
    }
  }

  Future<void> _loadPermissions() async {
    if (!_eventEnded || !widget.allowAttendance || _readOnly) return;
    try {
      final permissions = await widget.calendar.getAttendancePermissions(
        widget.event.id,
      );
      if (mounted) {
        setState(() {
          _resolvedPermissions = permissions;
          _permissionsFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _permissionsFailed = true);
    }
  }

  AppStrings get _s => AppStrings.of(context);

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).feature(text))),
    );
  }

  void _resetDispatch() {
    _saveKey = null;
    _lockKey = null;
    _sendKey = null;
    _preparedSquad = null;
    _locked = false;
    _expiry = null;
  }

  void _toggleSelection(EventRosterPerson person) {
    if (!_canManage ||
        _working ||
        _selectionFrozen ||
        person.isCalled ||
        _eventEnded) {
      return;
    }
    setState(() {
      _selectedIds.contains(person.personId)
          ? _selectedIds.remove(person.personId)
          : _selectedIds.add(person.personId);
      _selectionSource = 'manual';
      _selectionContext = {};
      _bulkMemberIds = null;
      _resetDispatch();
    });
  }

  void _selectGroup(List<EventRosterPerson> people) {
    if (!_canManage || _working || _selectionFrozen) return;
    final ids = people.where((p) => !p.isCalled).map((p) => p.personId).toSet();
    setState(() {
      if (ids.every(_selectedIds.contains)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
      _selectionSource = 'manual';
      _selectionContext = {};
      _resetDispatch();
    });
  }

  Future<void> _saveBulkDraft({
    required List<String> memberIds,
    required String source,
    Map<String, dynamic> selectionContext = const {},
  }) async {
    if (!_canManage || _working || _selectionFrozen) return;
    final called = _people
        .where((p) => p.isCalled)
        .map((p) => p.personId)
        .toSet();
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(memberIds.where((id) => !called.contains(id)));
      _selectionSource = source;
      _selectionContext = selectionContext;
      _bulkMemberIds = List.of(memberIds);
      _resetDispatch();
    });
  }

  Future<void> _sendSelected() async {
    if (!_canManage ||
        _working ||
        _selectedIds.isEmpty ||
        !widget.squad.can('send_callups')) {
      return;
    }
    setState(() => _busy = true);
    var sent = false;
    try {
      _saveKey ??= _newUuid();
      _lockKey ??= _newUuid();
      _sendKey ??= _newUuid();
      _expiry ??= DateTime.now().toUtc().add(const Duration(days: 7));
      if (_preparedSquad == null) {
        await widget.calendar.saveSquadDraft(
          eventId: widget.event.id,
          memberIds: _selectionSource != 'manual' && _bulkMemberIds != null
              ? _bulkMemberIds!
              : {
                  ..._selectedIds,
                  ..._people.where((p) => p.isCalled).map((p) => p.personId),
                }.toList(),
          source: _selectionSource,
          selectionContext: _selectionContext,
          expectedRevision: widget.squad.state == 'draft'
              ? widget.squad.revision
              : null,
          idempotencyKey: _saveKey!,
        );
        _preparedSquad = await widget.calendar.getEventSquad(widget.event.id);
      }
      final prepared = _preparedSquad!;
      if (!_locked && prepared.state == 'draft') {
        await widget.calendar.lockSquad(
          eventId: widget.event.id,
          expectedRevision: prepared.revision!,
          idempotencyKey: _lockKey!,
        );
        _locked = true;
      }
      await widget.calendar.sendCallups(
        squadRevisionId: prepared.squadRevisionId!,
        expiry: _expiry!,
        idempotencyKey: _sendKey!,
      );
      sent = true;
      _selectedIds.clear();
      _resetDispatch();
      await widget.onReload();
      if (mounted) _showError('Kallelserna är skickade.');
    } catch (_) {
      if (mounted) {
        _showError(
          sent
              ? 'Kallelserna är skickade, men listan kunde inte uppdateras. Öppna eventet igen.'
              : 'Kallelserna kunde inte bekräftas. Försök igen med samma urval.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _attendance(EventRosterPerson p) =>
      _stagedStatus[p.personId] ?? p.attendanceStatus ?? 'unknown';
  bool _present(EventRosterPerson p) =>
      const ['present', 'late', 'partial'].contains(_attendance(p));

  /// Only someone who got a callup is expected to come (and so can be
  /// actively absent). Without any callups on the event, everyone is.
  bool _expected(EventRosterPerson p) =>
      p.isCalled || !_people.any((person) => person.isCalled);

  Future<void> _setAttendance(EventRosterPerson person, String status) async {
    if (!_canRecordAttendance || _working) return;
    int? minutes;
    if (status == 'late' || status == 'partial') {
      final controller = TextEditingController(
        text:
            (_stagedMinutes[person.personId] ?? person.attendanceMinutes)
                ?.toString() ??
            '',
      );
      minutes = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _s.feature(
              status == 'late'
                  ? 'Antal minuter sen'
                  : 'Antal minuter närvarande',
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: _s.feature('Minuter (1–1440)'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_s.feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text);
                if (value != null && value >= 1 && value <= 1440) {
                  Navigator.pop(context, value);
                }
              },
              child: Text(_s.feature('Spara')),
            ),
          ],
        ),
      );
      // The dialog may still animate out; its controller is disposed after that frame.
      Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
      if (minutes == null || !mounted) return;
    }
    setState(() {
      _stagedStatus[person.personId] = status;
      _stagedRevisions.putIfAbsent(
        person.personId,
        () => person.attendanceRevision,
      );
      if (minutes != null) {
        _stagedMinutes[person.personId] = minutes;
      } else {
        _stagedMinutes.remove(person.personId);
      }
    });
    if (_resolvedPermissions?.lateWindow != true) await _saveAttendance();
  }

  Future<void> _markRemainingAbsent() async {
    if (!_canRecordAttendance || _working) return;
    final remaining = _people
        .where((p) => _expected(p) && _attendance(p) == 'unknown')
        .toList();
    if (remaining.isEmpty) return;
    if (remaining.length + _stagedStatus.length > 100) {
      _showError('Registrera högst 100 personer åt gången.');
      return;
    }
    setState(() {
      for (final p in remaining) {
        _stagedStatus[p.personId] = 'absent';
        _stagedRevisions.putIfAbsent(p.personId, () => p.attendanceRevision);
      }
    });
    if (_resolvedPermissions?.lateWindow != true) await _saveAttendance();
  }

  Future<void> _saveAttendance() async {
    if (!_canRecordAttendance || _working || _stagedStatus.isEmpty) return;
    final late = _resolvedPermissions?.lateWindow == true;
    final reason = _reasonController.text.trim();
    if (late && (reason.length < 3 || reason.length > 500)) {
      _showError('Ange en orsak till den sena ändringen (3–500 tecken).');
      return;
    }
    setState(() => _busy = true);
    var saved = false;
    try {
      final changes = [
        for (final entry in _stagedStatus.entries)
          {
            'person_id': entry.key,
            'status': entry.value,
            'expected_revision': _stagedRevisions[entry.key],
            if (_stagedMinutes.containsKey(entry.key))
              'minutes': _stagedMinutes[entry.key],
          },
      ];
      final payload = jsonEncode([changes, late ? reason : null]);
      if (_attendancePayload != payload) {
        _attendancePayload = payload;
        _attendanceKey = _newUuid();
      }
      await widget.calendar.recordAttendance(
        eventId: widget.event.id,
        changes: changes,
        correctionReason: late ? reason : null,
        idempotencyKey: _attendanceKey!,
      );
      saved = true;
      for (final id in _stagedStatus.keys) {
        _details.remove(id);
      }
      _stagedStatus.clear();
      _stagedMinutes.clear();
      _stagedRevisions.clear();
      _attendanceKey = null;
      _attendancePayload = null;
      await widget.onReload();
    } catch (_) {
      if (mounted) {
        _showError(
          saved
              ? 'Närvaron är sparad, men listan kunde inte uppdateras. Öppna eventet igen.'
              : 'Närvaron kunde inte sparas. Listan kan ha ändrats. Ladda om innan du försöker igen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _canRespond(EventRosterPerson p) =>
      !_readOnly && p.canRespond && (p.responseRole != 'manager' || _canManage);

  void _expand(EventRosterPerson p) {
    setState(() => _expandedId = _expandedId == p.personId ? null : p.personId);
    if (_expandedId != null) {
      _details.putIfAbsent(p.personId, () => _loadDetails(p));
    }
  }

  Future<(RosterPersonDetails?, PersonAttendanceSummary?)> _loadDetails(
    EventRosterPerson p,
  ) async {
    if (p.teamId.isEmpty) return (null, null);
    Future<RosterPersonDetails?> profile() async {
      try {
        return await widget.roster.getPersonDetails(
          clubId: widget.clubId,
          teamId: p.teamId,
          personId: p.personId,
        );
      } catch (_) {
        return null;
      }
    }

    Future<PersonAttendanceSummary?> attendance() async {
      try {
        return await widget.roster.getPersonAttendanceSummary(
          clubId: widget.clubId,
          teamId: p.teamId,
          personId: p.personId,
        );
      } catch (_) {
        return null;
      }
    }

    final a = profile();
    final b = attendance();
    return (await a, await b);
  }

  Future<void> _manageCallup(EventRosterPerson person, String action) async {
    if (action == 'remind') {
      await _reviewReminders([person]);
      return;
    }
    final callupId = person.callupId;
    if (callupId == null) return;
    setState(() => _busy = true);
    try {
      await widget.calendar.manageCallup(
        callupId: callupId,
        action: action,
        expectedRevision:
            widget.squad.callups
                .where((callup) => callup.id == callupId)
                .map((callup) => callup.revision)
                .firstOrNull ??
            0,
        idempotencyKey: _newUuid(),
      );
      await widget.onReload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature(
                action == 'remind'
                    ? 'Påminnelsen är skickad.'
                    : 'Kallelsen är återkallad.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _showError('Åtgärden kunde inte utföras. Ladda om och försök igen.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Responds to a callup — the person's own ('self'), or, for whoever
  /// can already manage the squad, anyone else's on the roster too
  /// ('manager' — same capability that already gates remind/cancel,
  /// covering both spelare and ledare buckets uniformly).
  Future<void> _respondToCallup(
    EventRosterPerson person,
    String response,
  ) async {
    final callupId = person.callupId;
    if (callupId == null) return;
    String? reasonCode;
    String? reasonText;
    if (response == 'declined') {
      final reason = await _declineCallupReasonDialog(context);
      if (reason == null || !mounted) return;
      reasonCode = reason.$1;
      reasonText = reason.$2;
    }
    setState(() => _busy = true);
    try {
      await widget.calendar.respondCallup(
        callupId: callupId,
        response: response,
        actingAsPersonId: person.responseRole == 'self'
            ? null
            : person.personId,
        declineReasonCode: reasonCode,
        declineReasonText: reasonText,
        expectedRevision:
            widget.squad.callups
                .where((callup) => callup.id == callupId)
                .map((callup) => callup.revision)
                .firstOrNull ??
            0,
        idempotencyKey: _newUuid(),
      );
      await widget.onReload();
    } catch (_) {
      // The write may have landed even though this request didn't hear
      // back — re-check before telling the user their answer was lost.
      final mismatched = await callupResponseStillMismatched(
        widget.calendar,
        widget.event.id,
        callupId,
        response,
      );
      if (mounted && mismatched) {
        _showError('Svaret kunde inte sparas. Ladda om och försök igen.');
      }
      await widget.onReload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remindAllUnanswered() async {
    if (_working || !_canManage || !widget.squad.can('remind_callup')) return;
    final now = DateTime.now();
    final eligible = [
      ...widget.squad.roster,
      ..._guestRosterFor(widget.squad),
    ].where((person) => person.canRemindAt(now)).toList();
    await _reviewReminders(eligible);
  }

  Future<void> _reviewReminders(List<EventRosterPerson> candidates) async {
    if (_working || !_canManage || !widget.squad.can('remind_callup')) return;
    final eligible = {
      for (final person in candidates)
        if (person.callupId != null && person.canRemindAt(DateTime.now()))
          person.callupId!: person,
    }.values.toList();
    if (eligible.isEmpty) return;
    final selected = eligible.map((p) => p.callupId!).toSet();
    setState(() => _reviewingReminders = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Granska påminnelser'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Endast obesvarade, giltiga kallelser visas. '
                    'Minst sex timmar måste ha gått sedan senaste påminnelsen.',
                  ),
                  for (final person in eligible)
                    CheckboxListTile(
                      value: selected.contains(person.callupId),
                      title: Text(person.name),
                      subtitle: Text(
                        person.callupLastRemindedAt == null
                            ? 'Ingen tidigare påminnelse'
                            : 'Senast: ${MaterialLocalizations.of(context).formatShortDate(person.callupLastRemindedAt!.toLocal())} '
                                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(person.callupLastRemindedAt!.toLocal()))}',
                      ),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected.add(person.callupId!);
                        } else {
                          selected.remove(person.callupId);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text('Skicka ${selected.length} påminnelser'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _reviewingReminders = false);
    if (confirmed != true) {
      return;
    }
    setState(() => _busy = true);
    var sent = 0;
    var failed = 0;
    try {
      for (final person in eligible.where(
        (p) => selected.contains(p.callupId),
      )) {
        try {
          await widget.calendar.manageCallup(
            callupId: person.callupId!,
            action: 'remind',
            expectedRevision:
                widget.squad.callups
                    .where((callup) => callup.id == person.callupId)
                    .map((callup) => callup.revision)
                    .firstOrNull ??
                0,
            idempotencyKey: _reminderKeys.putIfAbsent(
              '${person.callupId}:${widget.squad.callups.where((c) => c.id == person.callupId).firstOrNull?.revision}',
              _newUuid,
            ),
          );
          sent++;
        } catch (_) {
          failed++;
        }
      }
      await widget.onReload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed > 0
                  ? '$sent påminnelser skickade. $failed kunde inte skickas. Granska de uppdaterade kallelserna innan du försöker igen.'
                  : sent == 1
                  ? 'Påminnelsen är skickad.'
                  : '$sent påminnelser är skickade.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _showError(
          'Några påminnelser kunde inte skickas. Ladda om och försök igen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markAcceptedPresent() async {
    if (!_canRecordAttendance || _working) return;
    final eligible = _people
        .where(
          (p) => p.callupState == 'accepted' && _attendance(p) == 'unknown',
        )
        .toList();
    if (eligible.isEmpty) return;
    if (eligible.length + _stagedStatus.length > 100) {
      _showError('Registrera högst 100 personer åt gången.');
      return;
    }
    setState(() {
      for (final p in eligible) {
        _stagedStatus[p.personId] = 'present';
        _stagedRevisions.putIfAbsent(p.personId, () => p.attendanceRevision);
      }
    });
    if (_resolvedPermissions?.lateWindow != true) await _saveAttendance();
  }

  Future<void> _selectEligibilityGroup() async {
    final strings = AppStrings.of(context);
    final groups =
        _candidates
            .map((candidate) => candidate.eligibilityKind)
            .toSet()
            .toList()
          ..sort();
    if (groups.isEmpty) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(strings.feature('Välj behörighetsgrupp')),
        children: [
          for (final group in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, group),
              child: Text(
                '${strings.eligibilityKind(group)} (${_candidates.where((candidate) => candidate.eligibilityKind == group).length})',
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await _saveBulkDraft(
      memberIds: _candidates
          .where((candidate) => candidate.eligibilityKind == selected)
          .map((candidate) => candidate.personId)
          .toList(),
      source: 'group',
      selectionContext: {'eligibility_kind': selected},
    );
  }

  Future<void> _selectGeneratedDraft() async {
    final strings = AppStrings.of(context);
    if (_candidates.isEmpty) return;
    var count =
        (_draftMemberIds.isEmpty
                ? _candidates.length.clamp(1, 18)
                : _draftMemberIds.length.clamp(1, _candidates.length))
            .toInt();
    final selectedCount = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings.feature('Generera deltagarurval')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.feature(
                  'Ordinarie spelare prioriteras och urvalet blir alltid reproducerbart.',
                ),
              ),
              const SizedBox(height: 16),
              Text(strings.participantCount(count)),
              Slider(
                value: count.toDouble(),
                min: 1,
                max: _candidates.length.toDouble(),
                divisions: _candidates.length > 1
                    ? _candidates.length - 1
                    : null,
                label: '$count',
                onChanged: (value) =>
                    setDialogState(() => count = value.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.feature('Avbryt')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, count),
              child: Text(strings.feature('Använd urval')),
            ),
          ],
        ),
      ),
    );
    if (selectedCount == null || !mounted) return;
    final generated = List<SquadCandidate>.of(_candidates)
      ..sort((left, right) {
        final leftPriority = left.eligibilityKind == 'team_assignment' ? 0 : 1;
        final rightPriority = right.eligibilityKind == 'team_assignment'
            ? 0
            : 1;
        final priority = leftPriority.compareTo(rightPriority);
        if (priority != 0) return priority;
        final name = left.name.compareTo(right.name);
        return name != 0 ? name : left.personId.compareTo(right.personId);
      });
    await _saveBulkDraft(
      memberIds: generated
          .take(selectedCount)
          .map((candidate) => candidate.personId)
          .toList(),
      source: 'generator',
      selectionContext: {
        'generator': 'balanced_v1',
        'target_count': selectedCount,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final filtered = people
        .where(
          (p) =>
              _query.isEmpty ||
              p.name.toLowerCase().contains(_query.toLowerCase()) ||
              p.teamName.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final players = filtered.where((p) => p.rolePackage == 'player').toList();
    final leaders = filtered.where((p) => p.rolePackage != 'player').toList();
    return Column(
      children: [
        if (_canManage || _canRecordAttendance)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value.trim()),
                    decoration: InputDecoration(
                      hintText: _s.feature('Sök deltagare i klubben'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: _s.feature('Fler åtgärder'),
                  enabled: !_working && !_selectionFrozen,
                  onSelected: (value) {
                    if (value == 'group') _selectEligibilityGroup();
                    if (value == 'generate') _selectGeneratedDraft();
                    if (value == 'players') {
                      _saveBulkDraft(
                        memberIds: {
                          ..._selectedIds,
                          ...people
                              .where(
                                (p) => p.rolePackage == 'player' && !p.isCalled,
                              )
                              .map((p) => p.personId),
                        }.toList(),
                        source: 'manual',
                      );
                    }
                    if (value == 'remind') _remindAllUnanswered();
                    if (value == 'present') _markAcceptedPresent();
                    if (value == 'all') {
                      _saveBulkDraft(
                        memberIds: _candidates.map((p) => p.personId).toList(),
                        source: 'manual',
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    if (!_eventEnded)
                      PopupMenuItem(
                        value: 'players',
                        child: Text(_s.feature('Välj alla spelare')),
                      ),
                    if (!_eventEnded)
                      PopupMenuItem(
                        value: 'all',
                        child: Text(_s.feature('Alla behöriga')),
                      ),
                    if (!_eventEnded)
                      PopupMenuItem(
                        value: 'group',
                        child: Text(_s.feature('Behörighetsgrupp')),
                      ),
                    if (!_eventEnded)
                      PopupMenuItem(
                        value: 'generate',
                        child: Text(_s.feature('Generator')),
                      ),
                    if (!_eventEnded && widget.squad.can('remind_callup'))
                      PopupMenuItem(
                        value: 'remind',
                        enabled: people.any(
                          (p) => p.canRemindAt(DateTime.now()),
                        ),
                        child: Text(_s.feature('Påminn alla obesvarade')),
                      ),
                    if (_eventEnded && _canRecordAttendance)
                      PopupMenuItem(
                        value: 'present',
                        enabled: people.any(
                          (p) =>
                              p.callupState == 'accepted' &&
                              _attendance(p) == 'unknown',
                        ),
                        child: Text(
                          _s.feature('Markera accepterade som närvarande'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (_permissionsFailed)
          TextButton(
            onPressed: _loadPermissions,
            child: Text(
              _s.feature('Behörighet kunde inte hämtas. Försök igen'),
            ),
          ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: CustomScrollView(
            slivers: [
              for (final group in [
                (_s.feature('Spelare').toUpperCase(), players),
                (_s.feature('Ledare').toUpperCase(), leaders),
              ]) ...[
                SliverToBoxAdapter(child: _groupHeader(group.$1, group.$2)),
                SliverList.builder(
                  itemCount: group.$2.length,
                  itemBuilder: (context, index) => _personRow(group.$2[index]),
                ),
              ],
              if (_eventEnded && _canRecordAttendance)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextButton.icon(
                      onPressed:
                          _working ||
                              !people.any(
                                (p) =>
                                    _expected(p) && _attendance(p) == 'unknown',
                              )
                          ? null
                          : _markRemainingAbsent,
                      icon: const Icon(Icons.group_off_outlined, size: 18),
                      label: Text(
                        _s.feature('Markera återstående som frånvarande'),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(height: _assistantUsesFab(context) ? 88 : 12),
              ),
            ],
          ),
        ),
        if (!_eventEnded && _canManage && _selectedIds.isNotEmpty)
          _bottomBar(
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedIds.length} ${_s.feature('valda')}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _working || !widget.squad.can('send_callups')
                      ? null
                      : _sendSelected,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text('${_s.feature('Kalla')} ${_selectedIds.length}'),
                ),
              ],
            ),
          ),
        if (_eventEnded && _stagedStatus.isNotEmpty && _canRecordAttendance)
          _bottomBar(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_resolvedPermissions?.lateWindow == true)
                  TextField(
                    controller: _reasonController,
                    maxLength: 500,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _s.feature('Orsak till sen ändring'),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_stagedStatus.length} ${_s.feature('ändringar')}',
                      ),
                    ),
                    FilledButton(
                      onPressed: _working ? null : _saveAttendance,
                      child: Text(_s.feature('Spara närvaro')),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bottomBar(Widget child) => Material(
    elevation: 6,
    color: Theme.of(context).colorScheme.primaryContainer,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          _assistantUsesFab(context) ? 88 : 16,
          8,
        ),
        child: child,
      ),
    ),
  );

  Widget _groupHeader(String label, List<EventRosterPerson> people) {
    final called = people.where((p) => p.isCalled).length;
    final answered = people
        .where(
          (p) => p.callupState == 'accepted' || p.callupState == 'declined',
        )
        .length;
    final selectable =
        !_eventEnded && _canManage && people.any((p) => !p.isCalled);
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.only(left: 16, right: 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Text(
            '$label (${people.length})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          if (_eventEnded)
            Text(
              '${_s.feature('Närvaro')} ${people.where(_present).length}/${people.length}',
              style: const TextStyle(fontSize: 12),
            )
          else if (called > 0)
            Flexible(
              child: Text(
                '$called ${_s.feature('kallade')} · $answered ${_s.feature('svarat')}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (selectable)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _working || _selectionFrozen
                  ? null
                  : () => _selectGroup(people),
              child: Text(
                people
                        .where((p) => !p.isCalled)
                        .every((p) => _selectedIds.contains(p.personId))
                    ? _s.feature('Avmarkera alla')
                    : _s.feature('Markera alla'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _smallAction(
    IconData icon,
    Color color,
    String label,
    VoidCallback? action,
  ) => SizedBox(
    width: 30,
    height: 36,
    child: IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: label,
      onPressed: action,
      icon: Icon(icon, size: 20, color: color),
    ),
  );

  Widget _personRow(EventRosterPerson p) {
    final selected = !_eventEnded && _selectedIds.contains(p.personId);
    final expanded = _expandedId == p.personId;
    final colors = Theme.of(context).colorScheme;
    final initials = p.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty)
        .take(2)
        .map((v) => v.characters.first)
        .join()
        .toUpperCase();
    final status = _attendance(p);
    final expected = _expected(p);
    final canRespond = !_working && _canRespond(p);
    final attendanceLabel = switch (status) {
      'present' => _s.feature('Närvarande'),
      'absent' when expected => _s.feature('Frånvarande'),
      'late' => _s.feature('Sen'),
      'partial' => _s.feature('Delvis närvarande'),
      _ when !expected => _s.feature('Ej kallad'),
      _ => _s.feature('Ej registrerad'),
    };
    VoidCallback? primary;
    if (_eventEnded) {
      if (_canRecordAttendance && !_working) {
        // Without a callup nobody is expected: tapping again clears the
        // walk-in instead of marking an absence.
        primary = () => _setAttendance(
          p,
          _present(p) ? (expected ? 'absent' : 'unknown') : 'present',
        );
      }
    } else if (!p.isCalled) {
      if (_canManage && !_working && !_selectionFrozen) {
        primary = () => _toggleSelection(p);
      }
    } else if (p.callupState == 'pending' && canRespond) {
      primary = () => _respondToCallup(p, 'accepted');
    } else {
      primary = () => _expand(p);
    }
    return Material(
      color: selected || expanded
          ? colors.primary.withValues(alpha: .07)
          : colors.surface,
      child: Column(
        children: [
          Semantics(
            label: p.name,
            selected: selected,
            child: InkWell(
              key: ValueKey('participant-row-${p.personId}'),
              onTap: primary,
              onLongPress: () => _expand(p),
              child: SizedBox(
                height:
                    38 +
                    (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                      0,
                      42,
                    ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: colors.primary.withValues(alpha: .18),
                        child: Text(
                          initials,
                          style: TextStyle(fontSize: 11, color: colors.primary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: p.name,
                            children: [
                              if (_leaderTitles[p.personId] case final title?)
                                TextSpan(
                                  text: ' · $title',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      SizedBox(
                        width: 112,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_eventEnded)
                              _smallAction(
                                _present(p)
                                    ? Icons.check_circle
                                    : !expected
                                    ? Icons.remove_circle_outline
                                    : status == 'absent'
                                    ? Icons.cancel
                                    : Icons.remove_circle,
                                _present(p)
                                    ? Colors.green
                                    : !expected
                                    ? Colors.blueGrey.shade300
                                    : status == 'absent'
                                    ? Colors.red
                                    : Colors.blueGrey,
                                attendanceLabel,
                                primary,
                              )
                            else if (!p.isCalled)
                              _smallAction(
                                selected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                selected
                                    ? colors.primary
                                    : Colors.blueGrey.shade300,
                                selected
                                    ? '${_s.feature('Avmarkera')} ${p.name}'
                                    : '${_s.feature('Välj')} ${p.name}',
                                primary,
                              )
                            else if (p.callupState == 'pending') ...[
                              _smallAction(
                                Icons.notifications,
                                p.callupLastRemindedAt == null
                                    ? Colors.blueGrey
                                    : colors.primary,
                                p.callupLastRemindedAt == null
                                    ? _s.feature('Påminn')
                                    : '${_s.feature('Påminn · senast')} ${MaterialLocalizations.of(context).formatShortDate(p.callupLastRemindedAt!.toLocal())}',
                                _canManage &&
                                        widget.squad.can('remind_callup') &&
                                        !_working &&
                                        p.canRemindAt(DateTime.now())
                                    ? () => _manageCallup(p, 'remind')
                                    : null,
                              ),
                              if (_canRespond(p)) ...[
                                _smallAction(
                                  Icons.check,
                                  Colors.green,
                                  _s.feature('Acceptera'),
                                  canRespond
                                      ? () => _respondToCallup(p, 'accepted')
                                      : null,
                                ),
                                _smallAction(
                                  Icons.close,
                                  Colors.red,
                                  _s.feature('Avböj'),
                                  canRespond
                                      ? () => _respondToCallup(p, 'declined')
                                      : null,
                                ),
                              ] else
                                Tooltip(
                                  message: _s.feature('Ej svarat'),
                                  child: const Icon(
                                    Icons.schedule,
                                    size: 20,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                            ] else
                              Tooltip(
                                message: p.callupState == 'accepted'
                                    ? _s.feature('Accepterat')
                                    : p.callupState == 'declined'
                                    ? _s.feature('Avböjt')
                                    : '${_s.feature('Kallelse')}: ${_s.domainValue(p.callupState ?? '')}',
                                child: Icon(
                                  p.callupState == 'accepted'
                                      ? Icons.check_circle
                                      : p.callupState == 'declined'
                                      ? Icons.cancel
                                      : Icons.schedule,
                                  color: p.callupState == 'accepted'
                                      ? Colors.green
                                      : p.callupState == 'declined'
                                      ? Colors.red
                                      : Colors.blueGrey,
                                  size: 24,
                                ),
                              ),
                            SizedBox(
                              width: 22,
                              height: 36,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: expanded
                                    ? '${_s.feature('Dölj information om')} ${p.name}'
                                    : '${_s.feature('Visa information om')} ${p.name}',
                                onPressed: () => _expand(p),
                                icon: Icon(
                                  expanded
                                      ? Icons.expand_less
                                      : Icons.chevron_right,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: expanded
                ? _expandedPerson(p)
                : const SizedBox(width: double.infinity),
          ),
          Divider(
            height: 1,
            thickness: .5,
            indent: 56,
            color: colors.outlineVariant.withValues(alpha: .5),
          ),
        ],
      ),
    );
  }

  Widget _expandedPerson(EventRosterPerson p) => Padding(
    key: ValueKey('participant-details-${p.personId}'),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<(RosterPersonDetails?, PersonAttendanceSummary?)>(
          future: _details[p.personId],
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator(minHeight: 2);
            }
            final profile = snapshot.data?.$1;
            final stats = snapshot.data?.$2;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stats != null)
                  Row(
                    children: [
                      Expanded(
                        child: _stat(
                          _s.feature('Träningsnärvaro'),
                          stats.trainingsAttended,
                          stats.trainingsTotal,
                        ),
                      ),
                      Expanded(
                        child: _stat(
                          _s.feature('Matcher'),
                          stats.matchesPlayed,
                          stats.matchesTotal,
                        ),
                      ),
                    ],
                  ),
                if (stats == null)
                  Text(
                    _s.feature('Närvarostatistik är inte tillgänglig.'),
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: [
                    if (p.teamName.isNotEmpty) Text(p.teamName),
                    if (p.isGuest) Text(_s.feature('Gäst')),
                    if (profile?.birthYear != null)
                      Text('${_s.feature('Född')} ${profile!.birthYear}'),
                    if (profile?.ageClass != null) Text(profile!.ageClass!),
                  ],
                ),
              ],
            );
          },
        ),
        if (_localizedDeclineReason(AppStrings.of(context), p)
            case final String reason)
          Text(reason, style: const TextStyle(fontSize: 12)),
        if (p.responseRole == 'guardian')
          Text(
            _s.feature('Du svarar som vårdnadshavare'),
            style: const TextStyle(fontSize: 12),
          ),
        if (p.callupLastRemindedAt != null)
          Text(
            '${_s.feature('Senaste påminnelse')}: ${MaterialLocalizations.of(context).formatShortDate(p.callupLastRemindedAt!.toLocal())}',
            style: const TextStyle(fontSize: 12),
          ),
        if (_eventEnded && _canRecordAttendance)
          Wrap(
            spacing: 8,
            children: [
              for (final entry in {
                'present': _s.feature('Närvarande'),
                'absent': _s.feature('Frånvarande'),
                'unknown': _s.feature('Ej registrerad'),
                'late': _s.feature('Sen'),
                'partial': _s.feature('Delvis närvarande'),
              }.entries)
                TextButton(
                  onPressed: _working
                      ? null
                      : () => _setAttendance(p, entry.key),
                  child: Text(entry.value),
                ),
            ],
          )
        else if (!_eventEnded && p.isCalled)
          Wrap(
            spacing: 8,
            children: [
              if (_canRespond(p)) ...[
                TextButton(
                  onPressed: _working
                      ? null
                      : () => _respondToCallup(p, 'accepted'),
                  child: Text(_s.feature('Acceptera')),
                ),
                TextButton(
                  onPressed: _working
                      ? null
                      : () => _respondToCallup(p, 'declined'),
                  child: Text(_s.feature('Avböj')),
                ),
              ],
              if (_canManage && widget.squad.can('cancel_callup'))
                TextButton(
                  onPressed: _working ? null : () => _manageCallup(p, 'cancel'),
                  child: Text(_s.feature('Återkalla kallelse')),
                ),
            ],
          ),
      ],
    ),
  );

  Widget _stat(String title, int attended, int total) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 12)),
      Text(
        total == 0
            ? '– · 0/0'
            : '${(attended * 100 / total).round()} % · $attended/$total',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ],
  );
}
