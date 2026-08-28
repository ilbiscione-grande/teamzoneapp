part of '../../app/teamzone_app.dart';

class _MatchSpaceDialog extends StatefulWidget {
  const _MatchSpaceDialog({
    required this.event,
    required this.match,
    required this.compactFallback,
  });
  final EventDetails event;
  final MatchServices match;
  final bool compactFallback;
  @override
  State<_MatchSpaceDialog> createState() => _MatchSpaceDialogState();
}

class _MatchSpaceDialogState extends State<_MatchSpaceDialog>
    with WidgetsBindingObserver {
  MatchSnapshot? _snapshot;
  bool _loading = true, _pending = false;
  String? _error;
  Future<void> Function()? _retry;
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _snapshot?.state == 'live') setState(() {});
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final value = await widget.match.getSnapshot(widget.event.id);
      if (mounted) {
        setState(() {
          _snapshot = value;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Matchen kunde inte synkroniseras.';
        });
      }
    }
  }

  Future<void> _execute(Future<void> Function(String) command) =>
      _executeWithKey(command, _newUuid());
  Future<void> _executeWithKey(
    Future<void> Function(String) command,
    String key,
  ) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _error = null;
      _retry = null;
    });
    try {
      await command(key);
      await _refresh();
    } catch (error) {
      if (mounted) {
        final permissionDenied = _isPermissionDenied(error);
        final acceptedCallupsRequired =
            error is MeasuredCommandException &&
            error.code == 'accepted_callups_required';
        setState(() {
          _pending = false;
          _error = acceptedCallupsRequired
              ? AppStrings.of(context).feature(
                  'Minst en accepterad kallelse krävs innan matchtruppen kan frysas.',
                )
              : permissionDenied
              ? AppStrings.of(
                  context,
                ).feature('Du saknar behörighet att utföra den här åtgärden.')
              : AppStrings.of(context).feature(
                  'Kommandot kunde inte bekräftas. Kontrollera anslutningen.',
                );
          _retry = permissionDenied || acceptedCallupsRequired
              ? null
              : () => _executeWithKey(command, key);
        });
      }
      return;
    }
    if (mounted) setState(() => _pending = false);
  }

  int get _minute {
    var value = _snapshot?.elapsedAt(DateTime.now()).inMinutes ?? 0;
    for (final fact in _snapshot?.facts ?? const <Map<String, dynamic>>[]) {
      final minute = (fact['minute'] as num?)?.toInt() ?? 0;
      if (minute > value) value = minute;
    }
    return value;
  }

  bool _isPermissionDenied(Object error) {
    final value = error.toString().toLowerCase();
    return value.contains('42501') ||
        value.contains('not_found') ||
        value.contains('permission denied');
  }

  String _clockLabel(MatchSnapshot snapshot) {
    final elapsed = snapshot.elapsedAt(DateTime.now());
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    if (snapshot.state == 'completed') {
      return AppStrings.of(context).matchFinishedClock('$minutes:$seconds');
    }
    if (snapshot.clock['paused_at'] != null) {
      return AppStrings.of(context).matchPausedClock('$minutes:$seconds');
    }
    return '$minutes:$seconds';
  }

  String _periodActionLabel(MatchSnapshot snapshot) {
    final paused = snapshot.clock['paused_at'] != null;
    if (snapshot.periodMinutes.length == 2) {
      return paused
          ? AppStrings.of(context).feature('Starta andra halvlek')
          : AppStrings.of(context).feature('Halvtid');
    }
    return paused
        ? AppStrings.of(context).startPeriod(snapshot.currentPeriod + 1)
        : AppStrings.of(context).endPeriod(snapshot.currentPeriod);
  }

  String _factLabel(Map<String, dynamic> fact) {
    final minute = (fact['minute'] as num? ?? 0).toInt();
    final type = fact['fact_type'] as String? ?? 'event';
    final side = fact['side'] as String?;
    final label = switch (type) {
      'goal' =>
        side == 'us'
            ? AppStrings.of(context).feature('Mål vi')
            : AppStrings.of(context).feature('Mål motståndare'),
      'period_end' => AppStrings.of(context).periodEnded(
        ((fact['detail'] as Map?)?['period'] as num?)?.toInt() ?? 0,
      ),
      'full_time' => 'Fulltime',
      'card' => AppStrings.of(context).feature('Kort'),
      'substitution' => AppStrings.of(context).feature('Byte'),
      'injury' => AppStrings.of(context).feature('Skada'),
      _ => type.replaceAll('_', ' '),
    };
    return '$minute′ · $label';
  }

  Future<void> _unlock() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Lås upp match')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: 'Orsak'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).feature('Lås upp')),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    if (accepted == true && reason.isNotEmpty) {
      await _execute(
        (key) => widget.match.unlock(key, widget.event.id, reason),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return AlertDialog(
      title: Text(
        widget.compactFallback
            ? AppStrings.of(context).feature('Matchöversikt')
            : 'Match Space',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (snapshot == null && !_loading)
                Text(
                  AppStrings.of(
                    context,
                  ).feature('Matchen är inte förberedd ännu.'),
                ),
              if (snapshot != null) ...[
                Text(
                  '${snapshot.scoreUs} – ${snapshot.scoreOpponent}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Text(
                  '${AppStrings.of(context).domainValue(snapshot.state)} · ${AppStrings.of(context).periodLabel} ${snapshot.currentPeriod}/${snapshot.periodMinutes.length}',
                  textAlign: TextAlign.center,
                ),
                Text(
                  _clockLabel(snapshot),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  'Rosterrevision ${snapshot.rosterRevision} · Synkroniserad',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(),
                Text(
                  AppStrings.of(context).feature('Matchhändelser'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (snapshot.facts
                    .where((fact) => fact['state'] != 'voided')
                    .isEmpty)
                  Text(
                    AppStrings.of(
                      context,
                    ).feature('Inga matchhändelser registrerade.'),
                  ),
                ...snapshot.facts
                    .where((fact) => fact['state'] != 'voided')
                    .map(
                      (fact) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bolt, size: 20),
                        title: Text(_factLabel(fact)),
                      ),
                    ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(_error!)),
                ),
              if (_retry != null)
                TextButton.icon(
                  onPressed: _pending ? null : _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    AppStrings.of(
                      context,
                    ).feature('Försök igen med samma kommando'),
                  ),
                ),
              if (!widget.compactFallback) ...[
                const Divider(),
                if (snapshot == null || snapshot.rosterRevision == 0)
                  FilledButton(
                    onPressed: _pending
                        ? null
                        : () => _execute(
                            (key) => widget.match.freezeRoster(
                              key,
                              widget.event.id,
                              'initial',
                            ),
                          ),
                    child: Text(
                      AppStrings.of(
                        context,
                      ).feature('Frys accepterad matchtrupp'),
                    ),
                  ),
                if (snapshot != null &&
                    snapshot.rosterRevision > 0 &&
                    snapshot.state == 'planning')
                  FilledButton.icon(
                    onPressed: _pending
                        ? null
                        : () => _execute(
                            (key) => widget.match.transition(
                              key,
                              widget.event.id,
                              'start',
                            ),
                          ),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(AppStrings.of(context).feature('Starta match')),
                  ),
                if (snapshot?.state == 'live') ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed:
                            _pending || snapshot!.clock['paused_at'] != null
                            ? null
                            : () => _execute(
                                (key) => widget.match.recordGoal(
                                  key,
                                  widget.event.id,
                                  'us',
                                  _minute,
                                ),
                              ),
                        child: Text(AppStrings.of(context).feature('Mål vi')),
                      ),
                      FilledButton.tonal(
                        onPressed:
                            _pending || snapshot!.clock['paused_at'] != null
                            ? null
                            : () => _execute(
                                (key) => widget.match.recordGoal(
                                  key,
                                  widget.event.id,
                                  'opponent',
                                  _minute,
                                ),
                              ),
                        child: Text(
                          AppStrings.of(context).feature('Mål motståndare'),
                        ),
                      ),
                      if (snapshot!.currentPeriod <
                          snapshot.periodMinutes.length)
                        OutlinedButton(
                          onPressed: _pending
                              ? null
                              : () => _execute(
                                  (key) => widget.match.transitionPeriod(
                                    key,
                                    widget.event.id,
                                    snapshot.clock['paused_at'] == null
                                        ? 'end'
                                        : 'resume',
                                  ),
                                ),
                          child: Text(_periodActionLabel(snapshot)),
                        ),
                    ],
                  ),
                  if (snapshot.currentPeriod == snapshot.periodMinutes.length)
                    FilledButton.icon(
                      onPressed: _pending || snapshot.clock['paused_at'] != null
                          ? null
                          : () => _execute(
                              (key) => widget.match.complete(
                                key,
                                widget.event.id,
                                max(
                                  snapshot.periodMinutes.fold<int>(
                                    0,
                                    (sum, value) => sum + value,
                                  ),
                                  _minute,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.flag),
                      label: const Text('Fulltime'),
                    ),
                ],
                if (snapshot?.state == 'completed')
                  OutlinedButton.icon(
                    onPressed: _pending ? null : _unlock,
                    icon: const Icon(Icons.lock_open),
                    label: Text(
                      AppStrings.of(context).feature('Lås upp med orsak'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: AppStrings.of(context).feature('Synkronisera'),
          onPressed: _pending ? null : _refresh,
          icon: const Icon(Icons.sync),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.of(context).feature('Stäng')),
        ),
      ],
    );
  }
}
