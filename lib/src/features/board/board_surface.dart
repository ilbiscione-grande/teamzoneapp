part of '../../app/teamzone_app.dart';

bool _hasBoardCapability(TeamZoneContext value) =>
    const ['board.read', 'board.manage', 'board.approve'].any(value.can);

class _BoardSurface extends StatefulWidget {
  const _BoardSurface({required this.contextValue, required this.board});
  final TeamZoneContext contextValue;
  final BoardServices board;
  @override
  State<_BoardSurface> createState() => _BoardSurfaceState();
}

class _BoardSurfaceState extends State<_BoardSurface> {
  late Future<BoardOverview> _load = _reload();
  bool _busy = false;
  Future<BoardOverview> _reload() =>
      widget.board.getOverview(widget.contextValue.clubId);
  void _refresh() => setState(() => _load = _reload());

  @override
  void didUpdateWidget(covariant _BoardSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.clubId != widget.contextValue.clubId) {
      _load = _reload();
    }
  }

  Future<String?> _reason(String title) async {
    final controller = TextEditingController();
    final strings = AppStrings.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: 500,
          decoration: InputDecoration(labelText: strings.reason),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(strings.continueAction),
          ),
        ],
      ),
    );
    controller.dispose();
    return result == null || result.length < 3 ? null : result;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(BoardStrings.of(context).error(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGrant(List<BoardAssignment> assignments) async {
    if (assignments.isEmpty) return;
    final copy = BoardStrings.of(context);
    final reason = TextEditingController();
    var assignmentId = assignments.first.id;
    var office = 'member';
    final value = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(copy.proposeMandate),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: assignmentId,
                  decoration: InputDecoration(labelText: copy.person),
                  items: [
                    for (final item in assignments)
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                  ],
                  onChanged: (v) => setDialogState(() => assignmentId = v!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: office,
                  decoration: InputDecoration(labelText: copy.officeLabel),
                  items: [
                    for (final item in const [
                      'chair',
                      'treasurer',
                      'secretary',
                      'member',
                      'auditor',
                    ])
                      DropdownMenuItem(
                        value: item,
                        child: Text(copy.office(item)),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => office = v!),
                ),
                TextField(
                  controller: reason,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).reason,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).cancel),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length >= 3) {
                  Navigator.pop(context, {
                    'assignment': assignmentId,
                    'office': office,
                    'reason': reason.text.trim(),
                  });
                }
              },
              child: Text(copy.next),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (value == null || !mounted) return;
    final today = DateTime.now();
    final start = await showDatePicker(
      context: context,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: DateTime(today.year + 5),
      initialDate: today,
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      firstDate: start.add(const Duration(days: 1)),
      lastDate: DateTime(start.year + 6),
      initialDate: DateTime(start.year + 1, start.month, start.day),
    );
    if (end == null) return;
    await _run(
      () => widget.board.createChange(
        clubId: widget.contextValue.clubId,
        assignmentId: value['assignment']!,
        action: 'grant',
        office: value['office']!,
        startsAt: start,
        endsAt: end.add(const Duration(days: 1)),
        reason: value['reason']!,
        idempotencyKey: _newUuid(),
      ),
    );
  }

  Future<void> _revoke(BoardMandate mandate) async {
    final reason = await _reason(BoardStrings.of(context).proposeRevocation);
    if (reason == null) return;
    await _run(
      () => widget.board.createChange(
        clubId: widget.contextValue.clubId,
        assignmentId: mandate.assignmentId,
        mandateId: mandate.id,
        action: 'revoke',
        office: mandate.office,
        reason: reason,
        idempotencyKey: _newUuid(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = BoardStrings.of(context);
    if (!widget.contextValue.can('board.read')) {
      return _StateCard(
        icon: Icons.lock_outline,
        title: copy.title,
        message: copy.noAccess,
      );
    }
    return FutureBuilder<BoardOverview>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(label: AppStrings.of(context).loading);
        }
        if (snapshot.hasError) {
          return _StateCard(
            icon: Icons.lock_outline,
            title: copy.inactiveTitle,
            message: copy.inactiveMessage,
          );
        }
        final data = snapshot.requireData;
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      copy.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (widget.contextValue.can('board.manage'))
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _createGrant(data.assignments),
                      icon: const Icon(Icons.add),
                      label: Text(copy.newMandate),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                copy.mandatesHeading,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.mandates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(copy.noMandates),
                ),
              for (final mandate in data.mandates)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(
                      '${mandate.name} · ${copy.office(mandate.office)}',
                    ),
                    subtitle: Text(
                      '${copy.state(mandate.state)} · ${_date(mandate.startsAt)}–${_date(mandate.endsAt)}',
                    ),
                    trailing:
                        mandate.state == 'active' &&
                            widget.contextValue.can('board.manage')
                        ? IconButton(
                            tooltip: copy.proposeRevocation,
                            onPressed: _busy ? null : () => _revoke(mandate),
                            icon: const Icon(Icons.person_remove_outlined),
                          )
                        : null,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                copy.changesHeading,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (data.changes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(copy.noChanges),
                ),
              for (final change in data.changes)
                Card(
                  child: ListTile(
                    leading: Icon(
                      change.action == 'grant'
                          ? Icons.person_add_alt
                          : Icons.person_remove_outlined,
                    ),
                    title: Text(
                      '${change.action == 'grant' ? copy.assign : copy.revoke} ${copy.office(change.office)} · ${change.name}',
                    ),
                    subtitle: Text(
                      [
                        '${copy.state(change.state)} · ${copy.approvals(change.approvalCount)}',
                        if (change.approvers.isNotEmpty)
                          change.approvers
                              .map((item) => item.displayName)
                              .join(', '),
                      ].join(' · '),
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        if (change.state == 'pending' &&
                            widget.contextValue.can('board.approve'))
                          IconButton(
                            tooltip: change.currentActorApproved
                                ? copy.alreadyApproved
                                : copy.approve,
                            onPressed: _busy || change.currentActorApproved
                                ? null
                                : () async {
                                    final reason = await _reason(
                                      copy.approveChange,
                                    );
                                    if (reason != null) {
                                      await _run(
                                        () => widget.board.approve(
                                          changeId: change.id,
                                          decision: 'approved',
                                          reason: reason,
                                          idempotencyKey: _newUuid(),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.approval_outlined),
                          ),
                        if (change.state == 'pending' &&
                            widget.contextValue.can('board.manage'))
                          IconButton(
                            tooltip: copy.applyAfterApprovals,
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => widget.board.apply(
                                      changeId: change.id,
                                      idempotencyKey: _newUuid(),
                                    ),
                                  ),
                            icon: const Icon(Icons.check_circle_outline),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
