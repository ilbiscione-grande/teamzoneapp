part of '../../app/teamzone_app.dart';

class _OverviewSurface extends StatefulWidget {
  const _OverviewSurface({
    required this.destination,
    required this.contextValue,
    required this.overview,
    required this.calendar,
    required this.onNavigate,
  });

  final _Destination destination;
  final TeamZoneContext contextValue;
  final OverviewServices overview;
  final CalendarServices calendar;
  final ValueChanged<String> onNavigate;

  @override
  State<_OverviewSurface> createState() => _OverviewSurfaceState();
}

class _OverviewSurfaceState extends State<_OverviewSurface> {
  late final AsyncDataController<MainSurfacesProjection> _data;
  late Future<LeaderHomeProjection?> _leaderHome;
  late Future<PlayerHomeProjection?> _playerHome;
  late Future<GuardianHomeProjection?> _guardianHome;
  String? _guardianChildId;
  Future<MainSurfacesProjection> _reload() =>
      widget.overview.load(contextIds: [widget.contextValue.id]);

  @override
  void initState() {
    super.initState();
    _data = AsyncDataController<MainSurfacesProjection>(
      scopeKey: '${widget.contextValue.id}:${widget.destination.path}',
      loader: _reload,
      isEmpty: (_) => false,
    );
    _leaderHome = _reloadLeaderHome();
    _playerHome = _reloadPlayerHome();
    _guardianHome = _reloadGuardianHome();
    unawaited(_data.load());
  }

  Future<LeaderHomeProjection?> _reloadLeaderHome() async {
    if (widget.destination.path != '/home' ||
        widget.contextValue.rolePackage != 'leader') {
      return null;
    }
    try {
      return await widget.overview.loadLeaderHome(widget.contextValue.id);
    } catch (_) {
      return null;
    }
  }

  Future<PlayerHomeProjection?> _reloadPlayerHome() async {
    if (widget.destination.path != '/home' ||
        widget.contextValue.rolePackage != 'player') {
      return null;
    }
    try {
      return await widget.overview.loadPlayerHome(widget.contextValue.id);
    } catch (_) {
      return null;
    }
  }

  Future<GuardianHomeProjection?> _reloadGuardianHome() async {
    if (widget.destination.path != '/home' ||
        widget.contextValue.rolePackage != 'guardian') {
      return null;
    }
    try {
      return await widget.overview.loadGuardianHome(
        widget.contextValue.id,
        childPersonId: _guardianChildId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    final leaderHome = _reloadLeaderHome();
    final playerHome = _reloadPlayerHome();
    final guardianHome = _reloadGuardianHome();
    if (mounted) {
      setState(() {
        _leaderHome = leaderHome;
        _playerHome = playerHome;
        _guardianHome = guardianHome;
      });
    }
    final succeeded = await _data.refresh();
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).safeError)));
    }
  }

  @override
  void didUpdateWidget(covariant _OverviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id ||
        oldWidget.destination.path != widget.destination.path) {
      _data.replaceScope(
        scopeKey: '${widget.contextValue.id}:${widget.destination.path}',
        loader: _reload,
      );
      _leaderHome = _reloadLeaderHome();
      _playerHome = _reloadPlayerHome();
      _guardianChildId = null;
      _guardianHome = _reloadGuardianHome();
    }
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ListenableBuilder(
      listenable: _data,
      builder: (context, _) {
        final state = _data.state;
        if (state.phase == AsyncDataPhase.loading) {
          return AppLoadingIndicator(label: AppStrings.of(context).loading);
        }
        if (state.phase == AsyncDataPhase.failed) {
          return Center(
            child: _StateCard(
              icon: Icons.sync_problem,
              title: strings.couldNotLoad,
              message: strings.safeError,
              action: FilledButton(
                onPressed: _data.load,
                child: Text(strings.retry),
              ),
            ),
          );
        }
        final data = state.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                strings.destination(widget.destination.path),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (data.isStale || state.isStale)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off),
                    title: Text(strings.offlineData),
                    subtitle: Text(
                      strings.lastUpdated(
                        state.lastUpdated ?? data.generatedAt,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (widget.destination.path == '/home') ...[
                if (widget.contextValue.rolePackage == 'leader')
                  FutureBuilder<LeaderHomeProjection?>(
                    future: _leaderHome,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const AppLoadingIndicator(
                          label: 'Laddar dagens lagarbete',
                        );
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return _StateCard(
                          icon: Icons.sync_problem,
                          title: strings.couldNotLoad,
                          message: strings.safeError,
                          action: FilledButton(
                            onPressed: () => setState(
                              () => _leaderHome = _reloadLeaderHome(),
                            ),
                            child: Text(strings.retry),
                          ),
                        );
                      }
                      return _LeaderHomeContent(
                        value: snapshot.data!,
                        onNavigate: widget.onNavigate,
                      );
                    },
                  )
                else if (widget.contextValue.rolePackage == 'player')
                  FutureBuilder<PlayerHomeProjection?>(
                    future: _playerHome,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const AppLoadingIndicator(
                          label: 'Laddar din lagöversikt',
                        );
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return _StateCard(
                          icon: Icons.sync_problem,
                          title: strings.couldNotLoad,
                          message: strings.safeError,
                          action: FilledButton(
                            onPressed: () => setState(
                              () => _playerHome = _reloadPlayerHome(),
                            ),
                            child: Text(strings.retry),
                          ),
                        );
                      }
                      return _PlayerHomeContent(
                        value: snapshot.data!,
                        calendar: widget.calendar,
                        onNavigate: widget.onNavigate,
                        onChanged: () =>
                            setState(() => _playerHome = _reloadPlayerHome()),
                      );
                    },
                  )
                else if (widget.contextValue.rolePackage == 'guardian')
                  FutureBuilder<GuardianHomeProjection?>(
                    future: _guardianHome,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const AppLoadingIndicator(
                          label: 'Laddar barnets lagöversikt',
                        );
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return _StateCard(
                          icon: Icons.sync_problem,
                          title: strings.couldNotLoad,
                          message: strings.safeError,
                          action: FilledButton(
                            onPressed: () => setState(
                              () => _guardianHome = _reloadGuardianHome(),
                            ),
                            child: Text(strings.retry),
                          ),
                        );
                      }
                      return _GuardianHomeContent(
                        value: snapshot.data!,
                        calendar: widget.calendar,
                        onNavigate: widget.onNavigate,
                        onChildChanged: (childId) => setState(() {
                          _guardianChildId = childId;
                          _guardianHome = _reloadGuardianHome();
                        }),
                        onChanged: () => setState(
                          () => _guardianHome = _reloadGuardianHome(),
                        ),
                      );
                    },
                  )
                else ...[
                  _MetricCard(
                    label: strings.upcomingEvents,
                    value: '${data.home.upcomingCount}',
                    icon: Icons.event,
                  ),
                  _MetricCard(
                    label: strings.pendingCallups,
                    value: '${data.home.pendingCallupCount}',
                    icon: Icons.mark_email_unread_outlined,
                  ),
                  if (data.home.nextEvent case final event?)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_available),
                        title: Text(event.title),
                        subtitle: Text(strings.nextEventAt(event.startsAt)),
                        onTap: () => widget.onNavigate('/calendar'),
                      ),
                    ),
                ],
              ] else if (widget.destination.path == '/inbox') ...[
                _MetricCard(
                  label: strings.pendingNotifications,
                  value: '${data.inbox.pendingNotificationCount}',
                  icon: Icons.notifications_outlined,
                ),
                _StateCard(
                  icon: Icons.inbox_outlined,
                  title: strings.inboxEmpty,
                  message: strings.messagesLater,
                ),
              ] else ...[
                if (data.statistics.total == 0)
                  _StateCard(
                    icon: Icons.query_stats,
                    title: strings.noStatistics,
                    message: strings.statisticsEmpty,
                  )
                else ...[
                  _MetricCard(
                    label: strings.present,
                    value: '${data.statistics.present}',
                    icon: Icons.check_circle_outline,
                  ),
                  _MetricCard(
                    label: strings.late,
                    value: '${data.statistics.late}',
                    icon: Icons.schedule,
                  ),
                  _MetricCard(
                    label: strings.partial,
                    value: '${data.statistics.partial}',
                    icon: Icons.timelapse,
                  ),
                  _MetricCard(
                    label: strings.absent,
                    value: '${data.statistics.absent}',
                    icon: Icons.cancel_outlined,
                  ),
                  _MetricCard(
                    label: strings.unknown,
                    value: '${data.statistics.unknown}',
                    icon: Icons.help_outline,
                  ),
                ],
              ],
              const SizedBox(height: 48),
            ],
          ),
        );
      },
    );
  }
}

class _GuardianHomeContent extends StatelessWidget {
  const _GuardianHomeContent({
    required this.value,
    required this.calendar,
    required this.onNavigate,
    required this.onChildChanged,
    required this.onChanged,
  });
  final GuardianHomeProjection value;
  final CalendarServices calendar;
  final ValueChanged<String> onNavigate, onChildChanged;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final child = value.selectedChild;
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              initialValue: value.selectedChildId,
              decoration: const InputDecoration(
                labelText: 'Visa för barn',
                prefixIcon: Icon(Icons.child_care_outlined),
              ),
              items: [
                for (final item in value.children)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(item.displayName),
                  ),
              ],
              onChanged: (id) {
                if (id != null && id != value.selectedChildId) {
                  onChildChanged(id);
                }
              },
            ),
          ),
        ),
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.supervisor_account_outlined),
            title: Text('Du agerar för ${child.displayName}'),
            subtitle: const Text(
              'Barnets identitet följer med när du svarar på en kallelse.',
            ),
          ),
        ),
        _PlayerHomeContent(
          value: PlayerHomeProjection(
            generatedAt: value.generatedAt,
            team: value.team,
            callups: value.callups,
            unreadMessageCount: value.unreadMessageCount,
            nextEvent: value.nextEvent,
          ),
          calendar: calendar,
          onNavigate: onNavigate,
          onChanged: onChanged,
          callupTitle: '${child.displayName}s kallelser',
          actingAsName: child.displayName,
        ),
      ],
    );
  }
}

class _PlayerHomeContent extends StatefulWidget {
  const _PlayerHomeContent({
    required this.value,
    required this.calendar,
    required this.onNavigate,
    required this.onChanged,
    this.callupTitle = 'Dina kallelser',
    this.actingAsName,
  });
  final PlayerHomeProjection value;
  final CalendarServices calendar;
  final ValueChanged<String> onNavigate;
  final VoidCallback onChanged;
  final String callupTitle;
  final String? actingAsName;
  @override
  State<_PlayerHomeContent> createState() => _PlayerHomeContentState();
}

class _PlayerHomeContentState extends State<_PlayerHomeContent> {
  String? _pendingCallupId;

  Future<(String, String?)?> _declineReason() async {
    final text = TextEditingController();
    var code = 'illness';
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            AppStrings.of(context).feature('Varför kan du inte delta?'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: code,
                decoration: const InputDecoration(labelText: 'Anledning'),
                items:
                    const [
                          ('illness', 'Sjukdom'),
                          ('injury', 'Skada'),
                          ('unavailable', 'Inte tillgänglig'),
                          ('transport', 'Transport'),
                          ('other', 'Annat'),
                        ]
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.$1,
                            child: Text(item.$2),
                          ),
                        )
                        .toList(),
                onChanged: (value) =>
                    setDialogState(() => code = value ?? code),
              ),
              if (code == 'other')
                TextField(
                  controller: text,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Beskriv anledning',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: code == 'other' && text.text.trim().length < 2
                  ? null
                  : () => Navigator.pop(dialogContext, (
                      code,
                      code == 'other' ? text.text.trim() : null,
                    )),
              child: Text(AppStrings.of(context).feature('Fortsätt')),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    return result;
  }

  Future<void> _respond(PlayerHomeCallup callup, String response) async {
    String? reasonCode;
    String? reasonText;
    if (response == 'declined') {
      final reason = await _declineReason();
      if (reason == null || !mounted) return;
      reasonCode = reason.$1;
      reasonText = reason.$2;
    }
    setState(() => _pendingCallupId = callup.id);
    try {
      await widget.calendar.respondCallup(
        callupId: callup.id,
        response: response,
        actingAsPersonId: callup.actingAsPersonId,
        declineReasonCode: reasonCode,
        declineReasonText: reasonText,
        expectedRevision: callup.revision,
        idempotencyKey: _newUuid(),
      );
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Svaret kunde inte sparas. Ladda om och försök igen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingCallupId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final callups = uniqueHomeAttention<PlayerHomeCallup>(
      widget.value.callups,
      canonicalKey: (callup) => 'event:${callup.eventId}',
      priority: (_) => homeAttentionPriority('callup'),
    );
    final next =
        callups.any((callup) => callup.eventId == widget.value.nextEvent?.id)
        ? null
        : widget.value.nextEvent;
    final teamAndMessages = Column(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(widget.value.team.teamName),
            subtitle: Text(
              '${widget.value.team.clubName} · ${widget.value.team.memberCount} lagmedlemmar',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.onNavigate('/team'),
          ),
        ),
        if (widget.value.unreadMessageCount > 0)
          Card(
            child: ListTile(
              leading: Badge(
                label: Text('${widget.value.unreadMessageCount}'),
                child: const Icon(Icons.forum_outlined),
              ),
              title: Text(AppStrings.of(context).feature('Olästa meddelanden')),
              subtitle: Text(
                AppStrings.of(context).feature('Öppna inkorgen för att läsa'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.onNavigate('/inbox'),
            ),
          ),
      ],
    );
    final callupSection = _LeaderHomeSection(
      title: widget.callupTitle,
      icon: Icons.how_to_reg_outlined,
      emptyText: 'Du har inga aktuella kallelser',
      children: [
        for (final callup in callups)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  title: Text(callup.eventTitle),
                  subtitle: Text(_playerCallupSubtitle(context, callup)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onNavigate(
                    ProductRouteContract.calendarEvent(callup.eventId),
                  ),
                ),
                if (callup.canRespond)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (widget.actingAsName != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Svarar som vårdnadshavare för ${widget.actingAsName}',
                            ),
                          ),
                        OutlinedButton(
                          onPressed: _pendingCallupId == null
                              ? () => _respond(callup, 'declined')
                              : null,
                          child: Text(
                            AppStrings.of(context).feature('Kan inte'),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _pendingCallupId == null
                              ? () => _respond(callup, 'tentative')
                              : null,
                          child: Text(AppStrings.of(context).feature('Kanske')),
                        ),
                        FilledButton(
                          onPressed: _pendingCallupId == null
                              ? () => _respond(callup, 'accepted')
                              : null,
                          child: Text(
                            _pendingCallupId == callup.id
                                ? 'Sparar…'
                                : 'Kommer',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    final nextSection = next == null
        ? const SizedBox.shrink()
        : _LeaderHomeSection(
            title: 'Nästa aktivitet',
            icon: Icons.event_available_outlined,
            emptyText: '',
            children: [
              _LeaderEventTile(event: next, onNavigate: widget.onNavigate),
            ],
          );
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    if (!wide) {
      return Column(children: [callupSection, teamAndMessages, nextSection]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: callupSection),
        const SizedBox(width: 12),
        Expanded(child: Column(children: [teamAndMessages, nextSection])),
      ],
    );
  }
}

String _playerCallupSubtitle(BuildContext context, PlayerHomeCallup callup) {
  final material = MaterialLocalizations.of(context);
  final starts = callup.startsAt.toLocal();
  final state = switch (callup.state) {
    'accepted' => 'Kommer',
    'declined' => 'Kan inte',
    _ => 'Obesvarad',
  };
  return '$state · ${material.formatCompactDate(starts)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(starts))}';
}

class _LeaderHomeContent extends StatelessWidget {
  const _LeaderHomeContent({required this.value, required this.onNavigate});
  final LeaderHomeProjection value;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    final attentionTasks = uniqueHomeAttention<LeaderHomeTask>(
      value.tasks,
      canonicalKey: (task) => task.route,
      priority: (task) => homeAttentionPriority(task.kind),
    );
    final today = _LeaderHomeSection(
      title: 'Idag',
      icon: Icons.today_outlined,
      emptyText: 'Inga aktiviteter idag',
      children: [
        for (final event in value.todayEvents)
          _LeaderEventTile(event: event, onNavigate: onNavigate),
      ],
    );
    final tasks = _LeaderHomeSection(
      title: 'Behöver din uppmärksamhet',
      icon: Icons.task_alt_outlined,
      emptyText: 'Inga åtgärder väntar',
      children: [
        for (final task in attentionTasks)
          ListTile(
            leading: Badge(label: Text('${task.count}')),
            title: Text(task.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onNavigate(task.route),
          ),
      ],
    );
    final planning = _LeaderHomeSection(
      title: wide ? 'Planering och administration' : 'Snabbåtgärder',
      icon: Icons.dashboard_customize_outlined,
      emptyText: '',
      children: [
        for (final action in value.planningActions)
          ListTile(
            leading: Icon(switch (action.kind) {
              'create_event' => Icons.add_circle_outline,
              'manage_team' => Icons.groups_outlined,
              _ => Icons.inbox_outlined,
            }),
            title: Text(action.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onNavigate(action.route),
          ),
      ],
    );
    final uniqueNext =
        value.todayEvents.any((event) => event.id == value.nextEvent?.id)
        ? null
        : value.nextEvent;
    final next = uniqueNext == null
        ? const _LeaderHomeSection(
            title: 'Nästa aktivitet',
            icon: Icons.event_available_outlined,
            emptyText: 'Ingen kommande aktivitet är planerad',
            children: [],
          )
        : _LeaderHomeSection(
            title: 'Nästa aktivitet',
            icon: Icons.event_available_outlined,
            emptyText: '',
            children: [
              _LeaderEventTile(event: uniqueNext, onNavigate: onNavigate),
            ],
          );
    if (!wide) {
      return Column(children: [tasks, today, next, planning]);
    }
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: tasks),
            const SizedBox(width: 12),
            Expanded(child: today),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: next),
            const SizedBox(width: 12),
            Expanded(child: planning),
          ],
        ),
      ],
    );
  }
}

class _LeaderHomeSection extends StatelessWidget {
  const _LeaderHomeSection({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.children,
  });
  final String title, emptyText;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(leading: Icon(icon), title: Text(title)),
          if (children.isEmpty && emptyText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(emptyText),
            )
          else
            ...children,
        ],
      ),
    ),
  );
}

class _LeaderEventTile extends StatelessWidget {
  const _LeaderEventTile({required this.event, required this.onNavigate});
  final LeaderHomeEvent event;
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) {
    final local = event.startsAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final place = [
      event.locationName,
      event.address,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    return ListTile(
      title: Text(event.title),
      subtitle: Text(
        '${material.formatCompactDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}'
        '${place.isEmpty ? '' : '\n$place'}',
      ),
      isThreeLine: place.isNotEmpty,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onNavigate(ProductRouteContract.calendarEvent(event.id)),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Semantics(
        label: '$label: $value',
        child: Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ),
    ),
  );
}
