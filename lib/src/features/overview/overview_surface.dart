part of '../../app/teamzone_app.dart';

class _OverviewSurface extends StatefulWidget {
  const _OverviewSurface({
    required this.destination,
    required this.profile,
    required this.contextValue,
    required this.overview,
    required this.calendar,
    required this.messaging,
    required this.onNavigate,
  });

  final _Destination destination;
  final TeamZoneProfile profile;
  final TeamZoneContext contextValue;
  final OverviewServices overview;
  final CalendarServices calendar;
  final MessagingServices messaging;
  final ValueChanged<String> onNavigate;

  @override
  State<_OverviewSurface> createState() => _OverviewSurfaceState();
}

class _OverviewSurfaceState extends State<_OverviewSurface> {
  late final AsyncDataController<MainSurfacesProjection> _data;
  late Future<LeaderHomeProjection?> _leaderHome;
  late Future<PlayerHomeProjection?> _playerHome;
  late Future<GuardianHomeProjection?> _guardianHome;
  StreamSubscription<void>? _notificationSync;
  Timer? _homeRefreshDebounce;
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
    _subscribeHomeSignals();
  }

  void _subscribeHomeSignals() {
    unawaited(_notificationSync?.cancel());
    _notificationSync = null;
    if (widget.destination.path != '/home') return;
    _notificationSync = widget.messaging
        .watchNotificationInvalidations(includeTeamUpdatePoll: false)
        .listen((_) {
          _homeRefreshDebounce?.cancel();
          _homeRefreshDebounce = Timer(const Duration(milliseconds: 250), () {
            if (mounted && widget.destination.path == '/home') {
              unawaited(_refresh(showError: false));
            }
          });
        }, onError: (_) {});
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

  /// A background refresh keeps the shown projection if the reload fails, so
  /// a passing network hiccup never swaps Home for an error card.
  Future<T?> _orPrevious<T>(Future<T?> previous, Future<T?> next) async =>
      await next ?? await previous;

  Future<void> _refresh({bool showError = true}) async {
    final leaderHome = _orPrevious(_leaderHome, _reloadLeaderHome());
    final playerHome = _orPrevious(_playerHome, _reloadPlayerHome());
    final guardianHome = _orPrevious(_guardianHome, _reloadGuardianHome());
    if (mounted) {
      setState(() {
        _leaderHome = leaderHome;
        _playerHome = playerHome;
        _guardianHome = guardianHome;
      });
    }
    final succeeded = await _data.refresh();
    if (!succeeded && mounted && showError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).safeError)));
    }
  }

  @override
  void didUpdateWidget(covariant _OverviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination.path != widget.destination.path ||
        oldWidget.messaging != widget.messaging) {
      _homeRefreshDebounce?.cancel();
      _subscribeHomeSignals();
    }
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
    _homeRefreshDebounce?.cancel();
    unawaited(_notificationSync?.cancel());
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
              if (widget.destination.path == '/home')
                _HomeGreetingHeader(displayName: widget.profile.displayName)
              else
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
                      if (snapshot.connectionState != ConnectionState.done &&
                          !snapshot.hasData) {
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
                            onPressed: () => setState(() {
                              _leaderHome = _reloadLeaderHome();
                            }),
                            child: Text(strings.retry),
                          ),
                        );
                      }
                      return _LeaderHomeContent(
                        value: snapshot.data!,
                        calendar: widget.calendar,
                        onNavigate: widget.onNavigate,
                        onChanged: () => setState(() {
                          _leaderHome = _reloadLeaderHome();
                        }),
                      );
                    },
                  )
                else if (widget.contextValue.rolePackage == 'player')
                  FutureBuilder<PlayerHomeProjection?>(
                    future: _playerHome,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done &&
                          !snapshot.hasData) {
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
                            onPressed: () => setState(() {
                              _playerHome = _reloadPlayerHome();
                            }),
                            child: Text(strings.retry),
                          ),
                        );
                      }
                      return _PlayerHomeContent(
                        value: snapshot.data!,
                        calendar: widget.calendar,
                        onNavigate: widget.onNavigate,
                        onChanged: () => setState(() {
                          _playerHome = _reloadPlayerHome();
                        }),
                      );
                    },
                  )
                else if (widget.contextValue.rolePackage == 'guardian')
                  FutureBuilder<GuardianHomeProjection?>(
                    // A new child starts empty instead of showing the
                    // previous child's overview while loading.
                    key: ValueKey(_guardianChildId),
                    future: _guardianHome,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done &&
                          !snapshot.hasData) {
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
                            onPressed: () => setState(() {
                              _guardianHome = _reloadGuardianHome();
                            }),
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
                        onChanged: () => setState(() {
                          _guardianHome = _reloadGuardianHome();
                        }),
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

/// The Home page's personal greeting, replacing the generic page title
/// used by every other destination: "God förmiddag, {förnamn}" plus
/// today's date, matching the mockup's "Good afternoon, Thomas" header.
class _HomeGreetingHeader extends StatelessWidget {
  const _HomeGreetingHeader({required this.displayName});
  final String displayName;

  // Common Swedish time-of-day convention: morgon before 10, förmiddag
  // before noon, eftermiddag before 18, kväll after that.
  static String _greeting(int hour) => switch (hour) {
    < 10 => 'God morgon',
    < 12 => 'God förmiddag',
    < 18 => 'God eftermiddag',
    _ => 'God kväll',
  };

  @override
  Widget build(BuildContext context) {
    final firstName = displayName.trim().split(RegExp(r'\s+')).first;
    final greeting = _greeting(DateTime.now().hour);
    final material = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            firstName.isEmpty ? greeting : '$greeting, $firstName',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            material.formatFullDate(DateTime.now()),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
              onChanged: value.isStale
                  ? null
                  : (id) {
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
            todayEvents: value.todayEvents,
            upcomingEvents: value.upcomingEvents,
            isStale: value.isStale,
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

/// Shared decline-reason dialog for any surface that lets someone respond
/// "Kan inte" to a callup — the player's own home, a leader's own home,
/// and (leader-as-manager) the Deltagare tab's roster rows all funnel
/// through the same respond_callup RPC, which requires this same reason
/// shape whenever the response is 'declined'.
Future<(String, String?)?> _declineCallupReasonDialog(
  BuildContext context,
) async {
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
              onChanged: (value) => setDialogState(() => code = value ?? code),
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

class _PlayerHomeContentState extends State<_PlayerHomeContent> {
  String? _pendingCallupId;

  Future<(String, String?)?> _declineReason() =>
      _declineCallupReasonDialog(context);

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
      // The write may have landed even though this request didn't hear
      // back — re-check before telling the user their answer was lost.
      final mismatched = await callupResponseStillMismatched(
        widget.calendar,
        callup.eventId,
        callup.id,
        response,
      );
      if (mounted && mismatched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Svaret kunde inte sparas. Ladda om och försök igen.',
            ),
          ),
        );
      }
      widget.onChanged();
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
    final byEvent = {for (final callup in callups) callup.eventId: callup};
    // The day card shows the callup (own, or the child's) on its event.
    LeaderHomeEvent withCallup(LeaderHomeEvent event) {
      final callup = byEvent[event.id];
      if (callup == null) return event;
      return LeaderHomeEvent(
        id: event.id,
        title: event.title,
        type: event.type,
        state: event.state,
        startsAt: event.startsAt,
        endsAt: event.endsAt,
        locationName: event.locationName,
        address: event.address,
        myCallup: LeaderHomeCallup(
          id: callup.id,
          state: callup.state,
          revision: callup.revision,
          canRespond: callup.canRespond && !widget.value.isStale,
          expiresAt: callup.expiresAt,
          declineReasonCode: callup.declineReasonCode,
          declineReasonText: callup.declineReasonText,
        ),
      );
    }

    final day = _HomeDaySections.build(
      today: widget.value.todayEvents.map(withCallup).toList(),
      upcoming: widget.value.upcomingEvents.map(withCallup).toList(),
      next: widget.value.nextEvent == null
          ? null
          : withCallup(widget.value.nextEvent!),
      onNavigate: widget.onNavigate,
      pendingCallupId: _pendingCallupId,
      onRespond: (shown, response) {
        final callup = callups.where((c) => c.id == shown.id).firstOrNull;
        if (callup != null) _respond(callup, response);
      },
    );
    // Callups for events further ahead than the day card and lists.
    final otherCallups = callups
        .where((callup) => !day.shown.contains(callup.eventId))
        .toList();
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
    final callupSection = otherCallups.isEmpty
        ? null
        : _LeaderHomeSection(
            title: day.shown.isEmpty ? widget.callupTitle : 'Fler kallelser',
            icon: Icons.how_to_reg_outlined,
            emptyText: '',
            children: [
              for (final callup in otherCallups)
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(callup.eventTitle),
                        subtitle: Text(_playerCallupSubtitle(context, callup)),
                        isThreeLine:
                            _playerCallupDeclineReason(context, callup) != null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onNavigate(
                          ProductRouteContract.calendarEvent(callup.eventId),
                        ),
                      ),
                      if (callup.canRespond && !widget.value.isStale)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if (widget.actingAsName != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'Svarar som vårdnadshavare för ${widget.actingAsName}',
                                  ),
                                ),
                              _CallupResponseButtons(
                                busy: _pendingCallupId != null,
                                saving: _pendingCallupId == callup.id,
                                response: callup.state,
                                compact: false,
                                onRespond: (response) =>
                                    _respond(callup, response),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    final content = !wide
        ? Column(
            children: [
              day.hero,
              ?day.today,
              ?day.upcoming,
              ?callupSection,
              teamAndMessages,
            ],
          )
        : Column(
            children: [
              day.hero,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [?day.today, ?day.upcoming, ?callupSection],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: teamAndMessages),
                ],
              ),
            ],
          );
    if (!widget.value.isStale) return content;
    return Column(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_off_outlined),
            title: Text(AppStrings.of(context).offlineData),
            subtitle: Text(
              '${AppStrings.of(context).lastUpdated(widget.value.generatedAt)} '
              'Kallelsesvar är avstängda tills sidan har uppdaterats.',
            ),
          ),
        ),
        content,
      ],
    );
  }
}

String _playerCallupSubtitle(BuildContext context, PlayerHomeCallup callup) {
  final material = MaterialLocalizations.of(context);
  final starts = callup.startsAt.toLocal();
  final state = switch (callup.state) {
    'accepted' => 'Accepterat',
    'declined' => 'Avböjt',
    _ => 'Obesvarat',
  };
  final summary =
      '$state · ${material.formatCompactDate(starts)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(starts))}';
  final reason = _playerCallupDeclineReason(context, callup);
  return reason == null
      ? summary
      : '$summary\n${AppStrings.of(context).feature('Anledning')}: $reason';
}

String? _playerCallupDeclineReason(
  BuildContext context,
  PlayerHomeCallup callup,
) {
  if (callup.state != 'declined') return null;
  return _callupDeclineReason(
    AppStrings.of(context),
    callup.declineReasonCode,
    callup.declineReasonText,
  );
}

/// "Sjukdom", or "Annat – egen text" when a text was given.
String? _callupDeclineReason(AppStrings strings, String? code, String? text) {
  final label = switch (code) {
    'illness' => strings.feature('Sjukdom'),
    'injury' => strings.feature('Skada'),
    'unavailable' => strings.feature('Inte tillgänglig'),
    'transport' => strings.feature('Transport'),
    'other' => strings.feature('Annat'),
    _ => null,
  };
  if (label == null) return null;
  final detail = text?.trim();
  return detail == null || detail.isEmpty ? label : '$label – $detail';
}

class _LeaderHomeContent extends StatefulWidget {
  const _LeaderHomeContent({
    required this.value,
    required this.calendar,
    required this.onNavigate,
    required this.onChanged,
  });
  final LeaderHomeProjection value;
  final CalendarServices calendar;
  final ValueChanged<String> onNavigate;
  final VoidCallback onChanged;

  @override
  State<_LeaderHomeContent> createState() => _LeaderHomeContentState();
}

class _LeaderHomeContentState extends State<_LeaderHomeContent> {
  String? _pendingCallupId;

  // A leader can be called up like anyone else (the "kallade ledare"
  // roster bucket) — this is that same own-callup respond flow the
  // player home already has, just for the leader's own "nästa" card.
  Future<void> _respond(LeaderHomeCallup callup, String response) async {
    String? reasonCode;
    String? reasonText;
    if (response == 'declined') {
      final reason = await _declineCallupReasonDialog(context);
      if (reason == null || !mounted) return;
      reasonCode = reason.$1;
      reasonText = reason.$2;
    }
    setState(() => _pendingCallupId = callup.id);
    try {
      await widget.calendar.respondCallup(
        callupId: callup.id,
        response: response,
        declineReasonCode: reasonCode,
        declineReasonText: reasonText,
        expectedRevision: callup.revision,
        idempotencyKey: _newUuid(),
      );
      widget.onChanged();
    } catch (_) {
      // The write may have landed even though this request didn't hear
      // back — re-check before telling the user their answer was lost.
      final eventId = widget.value.nextEvent?.id;
      final mismatched = eventId == null
          ? true
          : await callupResponseStillMismatched(
              widget.calendar,
              eventId,
              callup.id,
              response,
            );
      if (mounted && mismatched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Svaret kunde inte sparas. Ladda om och försök igen.',
            ),
          ),
        );
      }
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _pendingCallupId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final onNavigate = widget.onNavigate;
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    // "Behöver din uppmärksamhet" moved to Min assistent — all of that
    // kind of information goes through the assistant now, not Home.
    final day = _HomeDaySections.build(
      today: value.todayEvents,
      upcoming: value.upcomingEvents,
      next: value.nextEvent,
      onNavigate: onNavigate,
      pendingCallupId: _pendingCallupId,
      onRespond: _respond,
    );
    final heroCard = day.hero;
    final todaySection = day.today;
    final upcomingSection = day.upcoming;
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
    final content = !wide
        ? Column(
            children: [heroCard, ?todaySection, ?upcomingSection, planning],
          )
        : Column(
            children: [
              heroCard,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(children: [?todaySection, ?upcomingSection]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: planning),
                ],
              ),
            ],
          );
    if (!value.isStale) return content;
    return Column(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_off_outlined),
            title: Text(AppStrings.of(context).offlineData),
            subtitle: Text(
              AppStrings.of(context).lastUpdated(value.generatedAt),
            ),
          ),
        ),
        content,
      ],
    );
  }
}

/// The top of every Home: one card that follows the day (what is on now,
/// otherwise next today, otherwise the next coming event), then the rest of
/// today and the coming days. Each event appears once, so "today" and
/// "next" never contradict each other. Events carry the viewer's own
/// callup (or the child's), answered right where the event is shown.
class _HomeDaySections {
  const _HomeDaySections._(this.hero, this.today, this.upcoming, this.shown);
  final Widget hero;
  final Widget? today, upcoming;

  /// Event ids shown in the card or the lists.
  final Set<String> shown;

  static _HomeDaySections build({
    required List<LeaderHomeEvent> today,
    required List<LeaderHomeEvent> upcoming,
    required LeaderHomeEvent? next,
    required ValueChanged<String> onNavigate,
    required String? pendingCallupId,
    required void Function(LeaderHomeCallup callup, String response) onRespond,
  }) {
    final now = DateTime.now();
    final active = today.where((event) => event.state != 'cancelled').toList();
    final hero =
        active
            .where(
              (event) =>
                  !event.startsAt.isAfter(now) && event.endsAt.isAfter(now),
            )
            .firstOrNull ??
        active.where((event) => event.startsAt.isAfter(now)).firstOrNull ??
        upcoming.firstOrNull ??
        next;
    final restOfToday = active.where((event) => event.id != hero?.id).toList();
    final coming = upcoming
        .where((event) => event.id != hero?.id)
        .take(4)
        .toList();
    Widget row(LeaderHomeEvent event, {required bool isToday}) => _HomeEventRow(
      event: event,
      now: now,
      isToday: isToday,
      onNavigate: onNavigate,
      pendingCallupId: pendingCallupId,
      onRespond: onRespond,
    );
    return _HomeDaySections._(
      hero == null
          ? const _LeaderHomeSection(
              title: 'Nästa aktivitet',
              icon: Icons.event_available_outlined,
              emptyText: 'Ingen kommande aktivitet är planerad',
              children: [],
            )
          : _HomeHeroEventCard(
              event: hero,
              now: now,
              onNavigate: onNavigate,
              pendingCallupId: pendingCallupId,
              onRespond: onRespond,
            ),
      restOfToday.isEmpty
          ? null
          : _LeaderHomeSection(
              title: 'Resten av idag',
              icon: Icons.today_outlined,
              emptyText: '',
              children: [
                for (final event in restOfToday) row(event, isToday: true),
              ],
            ),
      coming.isEmpty
          ? null
          : _LeaderHomeSection(
              title: 'Kommande',
              icon: Icons.date_range_outlined,
              emptyText: '',
              children: [
                for (final event in coming) row(event, isToday: false),
              ],
            ),
      {?hero?.id, ...restOfToday.map((e) => e.id), ...coming.map((e) => e.id)},
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

/// The answer to a callup as shown on Home.
String _callupStateLabel(String state) => switch (state) {
  'accepted' => 'Accepterat',
  'declined' => 'Avböjt',
  _ => 'Obesvarat',
};

/// Acceptera/Avböj for one callup, shared by Home and the Deltagare tab.
/// Unanswered: both are neutral outlines. Answered: the chosen one is
/// filled in its colour and reads "Accepterat"/"Avböjt" with a check; the
/// other stays an outline so the answer can still be changed.
class _CallupResponseButtons extends StatelessWidget {
  const _CallupResponseButtons({
    required this.busy,
    required this.saving,
    required this.response,
    required this.compact,
    required this.onRespond,
    this.onDark = false,
  });
  final bool busy;
  final bool saving;
  final String? response;
  final bool compact;
  final ValueChanged<String> onRespond;

  /// On the coloured hero card: outlines and text in white.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final disabled = busy || saving;
    Widget button({
      required String value,
      required String label,
      required String chosenLabel,
      required IconData icon,
      required Color selectedColor,
    }) {
      final selected = response == value;
      // Choosing the current answer again changes nothing.
      final onPressed = disabled
          ? null
          : selected
          ? () {}
          : () => onRespond(value);
      final text = selected ? chosenLabel : label;
      if (compact) {
        return Tooltip(
          message: text,
          child: Semantics(
            selected: selected,
            child: selected
                ? IconButton.filled(
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: selectedColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onPressed,
                    icon: Icon(icon),
                  )
                : IconButton.outlined(
                    visualDensity: VisualDensity.compact,
                    onPressed: onPressed,
                    icon: Icon(icon),
                  ),
          ),
        );
      }
      final side = BorderSide(
        color: onDark ? Colors.white70 : Theme.of(context).colorScheme.outline,
      );
      const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
      return Semantics(
        selected: selected,
        child: selected
            ? FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: selectedColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: selectedColor.withValues(alpha: .6),
                  disabledForegroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: padding,
                ),
                onPressed: onPressed,
                icon: const Icon(Icons.check_circle, size: 18),
                label: Text(text),
              )
            : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: onDark ? Colors.white : null,
                  side: side,
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: padding,
                ),
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(text),
              ),
      );
    }

    final buttons = [
      button(
        value: 'accepted',
        label: saving
            ? strings.feature('Sparar…')
            : strings.feature('Acceptera'),
        chosenLabel: strings.feature('Accepterat'),
        icon: Icons.check,
        selectedColor: Colors.green.shade700,
      ),
      button(
        value: 'declined',
        label: strings.feature('Avböj'),
        chosenLabel: strings.feature('Avböjt'),
        icon: Icons.close,
        selectedColor: Colors.red.shade700,
      ),
    ];
    // Full-width buttons wrap on narrow screens instead of overflowing.
    return compact
        ? Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: buttons)
        : Wrap(spacing: 8, runSpacing: 6, children: buttons);
  }
}

/// The own (or child's) callup: an icon in the answer's colour and
/// "Din kallelse: Obesvarat – svara gärna", "Accepterat" or
/// "Avböjt – Sjukdom".
class _CallupStatus extends StatelessWidget {
  const _CallupStatus({required this.callup, this.onDark = false});
  final LeaderHomeCallup callup;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (callup.state) {
      'accepted' => (Icons.check_circle, Colors.green.shade600),
      'declined' => (Icons.cancel, Colors.red.shade600),
      _ => (Icons.help, Colors.amber.shade700),
    };
    final reason = callup.state == 'declined'
        ? _callupDeclineReason(
            strings,
            callup.declineReasonCode,
            callup.declineReasonText,
          )
        : null;
    final answer = [
      strings.feature(_callupStateLabel(callup.state)),
      if (callup.state == 'pending' && callup.canRespond)
        strings.feature('svara gärna'),
      ?reason,
    ].join(' – ');
    final text = onDark ? Colors.white : colors.onSurface;
    return Row(
      key: ValueKey('callup-status-${callup.state}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: onDark ? Colors.white : null,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${strings.feature('Din kallelse')}: '),
                TextSpan(
                  text: answer,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: text),
          ),
        ),
      ],
    );
  }
}

/// The Home page's hero card: what is on now, later today, tomorrow or
/// next, on the current color theme's accent gradient (see
/// AppColorTheme.menuGradient) with light text. Full width, matching the
/// cards below it.
class _HomeHeroEventCard extends StatelessWidget {
  const _HomeHeroEventCard({
    required this.event,
    required this.now,
    required this.onNavigate,
    required this.pendingCallupId,
    required this.onRespond,
  });
  final LeaderHomeEvent event;
  final DateTime now;
  final ValueChanged<String> onNavigate;
  final String? pendingCallupId;
  final void Function(LeaderHomeCallup callup, String response) onRespond;

  String _moment(MaterialLocalizations material) {
    final start = event.startsAt.toLocal();
    final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(start));
    final today = DateUtils.dateOnly(now);
    final day = DateUtils.dateOnly(start);
    if (!event.startsAt.isAfter(now) && event.endsAt.isAfter(now)) {
      final end = material.formatTimeOfDay(
        TimeOfDay.fromDateTime(event.endsAt.toLocal()),
      );
      return 'PÅGÅR NU · SLUTAR $end';
    }
    if (day == today) return 'SENARE IDAG · $time';
    if (day == today.add(const Duration(days: 1))) return 'IMORGON · $time';
    return 'NÄSTA · ${material.formatMediumDate(start).toUpperCase()} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final local = event.startsAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final place = [
      event.locationName,
      event.address,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    final gradient = AppColorThemeScope.of(context).colorTheme.menuGradient;
    final callup = event.myCallup;
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Card(
      key: const Key('home-hero-event'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onNavigate(ProductRouteContract.calendarEvent(event.id)),
        child: Ink(
          decoration: BoxDecoration(gradient: gradient),
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _moment(material),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${material.formatFullDate(local)} · '
                  '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
                  style: textStyle?.copyWith(color: Colors.white),
                ),
                if (place.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      place,
                      style: textStyle?.copyWith(color: Colors.white70),
                    ),
                  ),
                if (callup != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _CallupStatus(callup: callup, onDark: true),
                  ),
                  if (callup.canRespond)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _CallupResponseButtons(
                        busy: pendingCallupId != null,
                        saving: pendingCallupId == callup.id,
                        response: callup.state,
                        compact: false,
                        onDark: true,
                        onRespond: (response) => onRespond(callup, response),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row under "Resten av idag" or "Kommande": a date badge, title and
/// time, whether it is on now or finished, and the own callup with
/// Acceptera/Avböj while it can still be answered.
class _HomeEventRow extends StatelessWidget {
  const _HomeEventRow({
    required this.event,
    required this.now,
    required this.isToday,
    required this.onNavigate,
    required this.pendingCallupId,
    required this.onRespond,
  });
  final LeaderHomeEvent event;
  final DateTime now;
  final bool isToday;
  final ValueChanged<String> onNavigate;
  final String? pendingCallupId;
  final void Function(LeaderHomeCallup callup, String response) onRespond;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final local = event.startsAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final finished = !event.endsAt.isAfter(now);
    final ongoing = !finished && !event.startsAt.isAfter(now);
    final callup = event.myCallup;
    final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    final details = [
      if (isToday) time else '${material.formatShortDate(local)} · $time',
      if (finished) strings.feature('Avslutad'),
      if (ongoing) strings.feature('Pågår'),
    ];
    return Opacity(
      opacity: finished ? .55 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    material.narrowWeekdays[local.weekday % 7].toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                  Text(
                    '${local.day}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            title: Text(event.title),
            subtitle: Text(details.join(' · ')),
            trailing: finished
                ? Icon(Icons.check, color: colors.onSurfaceVariant)
                : const Icon(Icons.chevron_right),
            onTap: () =>
                onNavigate(ProductRouteContract.calendarEvent(event.id)),
          ),
          if (callup != null && !finished)
            Padding(
              padding: EdgeInsets.fromLTRB(
                72,
                0,
                16,
                callup.canRespond ? 6 : 10,
              ),
              child: _CallupStatus(callup: callup),
            ),
          if (callup != null && callup.canRespond && !finished)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _CallupResponseButtons(
                  busy: pendingCallupId != null,
                  saving: pendingCallupId == callup.id,
                  response: callup.state,
                  compact: false,
                  onRespond: (response) => onRespond(callup, response),
                ),
              ),
            ),
        ],
      ),
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
