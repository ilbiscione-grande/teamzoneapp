part of '../../app/teamzone_app.dart';

class _InboxSurface extends StatefulWidget {
  const _InboxSurface({
    required this.contextValue,
    required this.contexts,
    required this.messaging,
    required this.membership,
    this.initialThreadId,
    this.initialAction,
    required this.onNavigate,
  });
  final TeamZoneContext contextValue;
  final List<TeamZoneContext> contexts;
  final MessagingServices messaging;
  final MembershipServices membership;
  final String? initialThreadId;
  // Set by the swipe-up quick actions sheet's "Skicka meddelande" shortcut
  // (ProductRouteContract.inboxCompose) to open the compose dialog
  // immediately on arrival — see _openInitialAction.
  final String? initialAction;
  final ValueChanged<String> onNavigate;
  @override
  State<_InboxSurface> createState() => _InboxSurfaceState();
}

class _InboxSurfaceState extends State<_InboxSurface>
    with WidgetsBindingObserver {
  late final AsyncDataController<List<MessageThreadSummary>> _data;
  late final AppListController<MessageThreadSummary> _list;
  StreamSubscription<void>? _inboxSync;
  StreamSubscription<void>? _notificationSync;
  VoidCallback? _refreshOpenNotifications;
  StreamSubscription<void>? _browserOnlineSync;
  Timer? _supportRefreshTimer;
  Timer? _resyncDebounce;
  Timer? _staleResync;
  int _staleResyncAttempt = 0;
  String _filter = 'all';
  List<MessageThreadSummary>? _syncedThreads;
  bool _initialThreadOpened = false;
  // The thread id currently showing in _ThreadDialog (or being opened for
  // it), separate from _initialThreadOpened: this dedupes against the
  // dialog we already have open, independent of whether widget's route
  // props have caught up yet.
  String? _openThreadId;
  // Closing a deep-linked thread and clearing `?thread=` are two separate
  // asynchronous operations. Remember the dismissed id until the route has
  // caught up, otherwise a list refresh can immediately reopen the dialog and
  // make the close button appear to do nothing.
  String? _dismissedThreadId;
  bool _settingsPending = false;
  bool _announcementArchiveExpanded = false;
  int _notificationUnread = 0;
  late Future<List<ProtectedNameSupportCase>> _supportCases;
  // Defaults to just the active team/club; the filter dialog lets the user
  // widen this to other connections. Reset to the (new) active context
  // whenever it changes -- see didUpdateWidget.
  late Set<String> _selectedContextIds = {widget.contextValue.id};

  // A team context can merge several of your assignments (e.g. leader and
  // club functionary); their threads all belong to that one team.
  List<String> get _contextIds => {
    for (final id in _selectedContextIds) ...[
      id,
      ...?widget.contexts.where((item) => item.id == id).firstOrNull?.aliasIds,
      if (id == widget.contextValue.id) ...widget.contextValue.aliasIds,
    ],
  }.toList(growable: false)..sort();

  String get _scopeKey => _contextIds.join('|');

  Future<List<MessageThreadSummary>> _reload() =>
      widget.messaging.listThreads(_contextIds);

  String get _activeScopeLabel => widget.contextValue.teamName == null
      ? widget.contextValue.clubName
      : '${widget.contextValue.teamName} · ${widget.contextValue.clubName}';

  static const _otherConversations = 'Övriga konversationer';
  static const _severalClubs = 'Flera klubbar';

  // Clubs opened or closed by hand. Otherwise the active club (or the only
  // one) starts open and the others show just their name.
  final Map<String, bool> _clubExpanded = {};

  /// The club a conversation belongs to, from its server-derived labels
  /// ("Lag · Klubb" or "Klubb").
  String _clubOf(MessageThreadSummary thread) {
    final clubs = {
      for (final label in thread.scopeLabels) label.split(' · ').last,
    };
    if (clubs.isEmpty) return _otherConversations;
    return clubs.length == 1 ? clubs.single : _severalClubs;
  }

  List<({String club, List<MessageThreadSummary> threads})> _groupByClub(
    List<MessageThreadSummary> threads,
  ) {
    final grouped = <String, List<MessageThreadSummary>>{};
    for (final thread in threads) {
      (grouped[_clubOf(thread)] ??= []).add(thread);
    }
    int rank(String club) => club == widget.contextValue.clubName
        ? 0
        : club == _severalClubs
        ? 2
        : club == _otherConversations
        ? 3
        : 1;
    return [
      for (final entry in grouped.entries)
        (club: entry.key, threads: entry.value),
    ]..sort((a, b) {
      final byRank = rank(a.club).compareTo(rank(b.club));
      return byRank != 0
          ? byRank
          : a.club.toLowerCase().compareTo(b.club.toLowerCase());
    });
  }

  bool _isClubExpanded(String club, int clubCount) =>
      // A search shows every hit.
      _list.query.isNotEmpty ||
      (_clubExpanded[club] ??
          (clubCount == 1 || club == widget.contextValue.clubName));

  List<({String title, String? subtitle, List<MessageThreadSummary> threads})>
  _groupThreads(List<MessageThreadSummary> threads) {
    final grouped = <String, List<MessageThreadSummary>>{};
    for (final thread in threads) {
      final key = thread.scopeLabels.isEmpty
          ? ''
          : thread.scopeLabels.length == 1
          ? thread.scopeLabels.single
          : thread.scopeLabels.join('|');
      (grouped[key] ??= []).add(thread);
    }
    final result = grouped.entries
        .map((entry) {
          if (entry.key.isEmpty) {
            return (
              title: 'Övriga konversationer',
              subtitle: null,
              threads: entry.value,
            );
          }
          final labels = entry.key.split('|');
          if (labels.length > 1) {
            return (
              title: 'Flera lag',
              subtitle: labels.join(', '),
              threads: entry.value,
            );
          }
          final parts = labels.single.split(' · ');
          return (
            title: parts.first,
            subtitle: parts.length > 1 ? parts.sublist(1).join(' · ') : 'Klubb',
            threads: entry.value,
          );
        })
        .toList(growable: false);
    result.sort((left, right) {
      final leftActive = left.threads.any(
        (thread) => thread.scopeLabels.contains(_activeScopeLabel),
      );
      final rightActive = right.threads.any(
        (thread) => thread.scopeLabels.contains(_activeScopeLabel),
      );
      if (leftActive != rightActive) return leftActive ? -1 : 1;
      return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    });
    return result;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = AsyncDataController<List<MessageThreadSummary>>(
      scopeKey: _scopeKey,
      loader: _reload,
      isEmpty: (threads) => threads.isEmpty,
    );
    _list = AppListController<MessageThreadSummary>(
      searchText: (thread) => [
        thread.subject,
        thread.preview,
        thread.senderName,
        thread.type,
      ].whereType<String>().join(' '),
    );
    _supportCases = _loadSupportCases();
    _data.addListener(_syncList);
    _subscribeToInbox();
    _subscribeToNotifications();
    _browserOnlineSync = browserOnlineSignals().listen(
      (_) => unawaited(_resyncFromSignal()),
    );
    _supportRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _supportCases = _loadSupportCases());
    });
    unawaited(_data.load());
    unawaited(_refreshNotificationBadge());
    _openInitialAction();
  }

  bool _openedInitialAction = false;

  /// Handles ?action=compose from the swipe-up quick actions sheet
  /// (ProductRouteContract.inboxCompose): opens the compose dialog
  /// immediately, same dialog as the page's own FAB.
  void _openInitialAction() {
    if (widget.initialAction != 'compose' || _openedInitialAction) return;
    _openedInitialAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_compose());
    });
  }

  void _subscribeToInbox() {
    unawaited(_inboxSync?.cancel());
    _inboxSync = widget.messaging.watchInboxInvalidations().listen((_) {
      _resyncDebounce?.cancel();
      _resyncDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) unawaited(_resyncFromSignal());
      });
    }, onError: (_) {});
  }

  Future<void> _resyncFromSignal() async {
    final succeeded = await _data.refresh();
    if (succeeded) {
      _clearStaleResync();
    } else if (_data.state.isStale) {
      _scheduleStaleResync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_resyncFromSignal());
      setState(() => _supportCases = _loadSupportCases());
    }
  }

  void _subscribeToNotifications() {
    unawaited(_notificationSync?.cancel());
    _notificationSync = widget.messaging
        .watchNotificationInvalidations()
        .listen((_) {
          unawaited(_refreshNotificationBadge());
          _refreshOpenNotifications?.call();
        }, onError: (_) {});
  }

  void _setFilter(String value) {
    setState(() => _filter = value);
    _list.setFilter(
      key: value == 'all' ? null : value,
      predicate: switch (value) {
        'unread' => (MessageThreadSummary thread) => thread.unreadCount > 0,
        'muted' => (MessageThreadSummary thread) => thread.muted,
        'pinned' => (MessageThreadSummary thread) => thread.pinned,
        'team' => (MessageThreadSummary thread) => thread.type == 'team',
        'leader' => (MessageThreadSummary thread) => thread.type == 'leader',
        _ => null,
      },
    );
  }

  void _setSelectedContextIds(Set<String> value) {
    if (value.isEmpty || setEquals(value, _selectedContextIds)) return;
    setState(() => _selectedContextIds = value);
    _data.replaceScope(scopeKey: _scopeKey, loader: _reload);
  }

  Future<void> _showFilterSheet() {
    // Dedup by context id (a guardian can otherwise appear once per child).
    final uniqueContexts = {
      for (final item in widget.contexts) item.id: item,
    }.values.toList(growable: false);
    // Teams listed under their club; a club opens to show its teams.
    final byClub = <String, List<TeamZoneContext>>{};
    for (final item in uniqueContexts) {
      (byClub[item.clubName] ??= []).add(item);
    }
    final clubNames = byClub.keys.toList()
      ..sort((a, b) {
        if (a == widget.contextValue.clubName) return -1;
        if (b == widget.contextValue.clubName) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // Never full height, so there is always a backdrop to tap as well.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (sheetContext) {
        var localFilter = _filter;
        var localSelected = Set<String>.of(_selectedContextIds);
        final openClubs = <String>{
          for (final club in clubNames)
            if (byClub[club]!.any((item) => localSelected.contains(item.id)))
              club,
        };
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final strings = AppStrings.of(sheetContext);
            void apply(Set<String> next) {
              // At least one connection stays selected.
              if (next.isEmpty) return;
              setSheetState(() => localSelected = next);
              _setSelectedContextIds(next);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title and close stay put while the options scroll.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.feature('Filtrera inkorgen'),
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('inbox-filter-close'),
                          tooltip: strings.feature('Stäng'),
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  // Scrolls when there are many teams, instead of overflowing.
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            strings.feature('Typ'),
                            style: Theme.of(sheetContext).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final entry in const [
                                ('all', 'Alla'),
                                ('unread', 'Olästa'),
                                ('team', 'Lag'),
                                ('leader', 'Ledare'),
                                ('muted', 'Tystade'),
                                ('pinned', 'Fästa'),
                              ])
                                ChoiceChip(
                                  label: Text(strings.feature(entry.$2)),
                                  selected: localFilter == entry.$1,
                                  onSelected: (_) {
                                    setSheetState(() => localFilter = entry.$1);
                                    _setFilter(entry.$1);
                                  },
                                ),
                            ],
                          ),
                          if (uniqueContexts.length > 1) ...[
                            const SizedBox(height: 20),
                            Text(
                              strings.feature('Lag och klubbar'),
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.titleSmall,
                            ),
                            Text(
                              strings.feature(
                                'Visar aktivt lag som standard. Välj fler för att '
                                'se deras konversationer också.',
                              ),
                              style: Theme.of(sheetContext).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            for (final club in clubNames) ...[
                              Builder(
                                builder: (_) {
                                  final items = byClub[club]!;
                                  final picked = items
                                      .where(
                                        (item) =>
                                            localSelected.contains(item.id),
                                      )
                                      .length;
                                  final open = openClubs.contains(club);
                                  return ListTile(
                                    key: ValueKey('inbox-filter-club-$club'),
                                    contentPadding: EdgeInsets.zero,
                                    leading: Checkbox(
                                      tristate: true,
                                      value: picked == 0
                                          ? false
                                          : picked == items.length
                                          ? true
                                          : null,
                                      onChanged: (_) => apply(
                                        picked == items.length
                                            ? (Set<String>.of(localSelected)
                                                ..removeAll(
                                                  items.map((item) => item.id),
                                                ))
                                            : (Set<String>.of(localSelected)
                                                ..addAll(
                                                  items.map((item) => item.id),
                                                )),
                                      ),
                                    ),
                                    title: Text(
                                      club,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: picked == 0
                                        ? null
                                        : Text(
                                            '$picked/${items.length} ${strings.feature('valda')}',
                                          ),
                                    trailing: Icon(
                                      open
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                    ),
                                    onTap: () => setSheetState(
                                      () => open
                                          ? openClubs.remove(club)
                                          : openClubs.add(club),
                                    ),
                                  );
                                },
                              ),
                              if (openClubs.contains(club))
                                for (final item in byClub[club]!)
                                  CheckboxListTile(
                                    contentPadding: const EdgeInsets.only(
                                      left: 40,
                                    ),
                                    dense: true,
                                    title: Text(
                                      item.teamName ??
                                          strings.feature('Hela klubben'),
                                    ),
                                    value: localSelected.contains(item.id),
                                    onChanged: (checked) => apply(
                                      (checked ?? false)
                                          ? (Set<String>.of(localSelected)
                                              ..add(item.id))
                                          : (Set<String>.of(localSelected)
                                              ..remove(item.id)),
                                    ),
                                  ),
                            ],
                          ],
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: Text(strings.feature('Klar')),
                            ),
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
      },
    );
  }

  void _syncList() {
    final threads = _data.state.data;
    if (!identical(threads, _syncedThreads)) {
      _syncedThreads = threads;
      _list.replaceItems(threads ?? const []);
    }
    _tryOpenInitialThread();
  }

  // Split out from _syncList so a target change alone (e.g. tapping a
  // different notification while Inbox is already mounted, which changes
  // initialThreadId but never re-fetches _data) can re-check the
  // already-loaded thread list without needing a new data notification.
  void _tryOpenInitialThread() {
    final threads = _data.state.data;
    final target = widget.initialThreadId;
    if (target == null ||
        target == _openThreadId ||
        target == _dismissedThreadId) {
      return;
    }
    if (!_initialThreadOpened && threads != null) {
      final matches = threads.where((thread) => thread.id == target);
      if (matches.isNotEmpty) {
        _initialThreadOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openThread(matches.first));
        });
      }
    }
  }

  Future<void> _refreshNotificationBadge() async {
    try {
      final center = await widget.messaging.listNotifications();
      if (mounted) setState(() => _notificationUnread = center.unreadCount);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() => _supportCases = _loadSupportCases());
    final succeeded = await _data.refresh();
    if (succeeded) {
      _clearStaleResync();
    } else if (_data.state.isStale) {
      _scheduleStaleResync();
    }
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).safeError)));
    }
  }

  Future<List<ProtectedNameSupportCase>> _loadSupportCases() => widget
      .membership
      .listMyProtectedNameSupportCases()
      .timeout(const Duration(seconds: 15));

  Future<void> _openSupportCases() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _MyProtectedNameSupportCasesSheet(membership: widget.membership),
    );
    if (mounted) setState(() => _supportCases = _loadSupportCases());
  }

  Widget _supportInboxEntry(
    BuildContext context,
  ) => FutureBuilder<List<ProtectedNameSupportCase>>(
    future: _supportCases,
    builder: (context, snapshot) {
      final items = snapshot.data ?? const <ProtectedNameSupportCase>[];
      if (items.isEmpty) return const SizedBox.shrink();
      final unread = items.fold<int>(0, (sum, item) => sum + item.unreadCount);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Card(
          color: unread > 0
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          child: ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: Text(AppStrings.of(context).feature('Mina supportärenden')),
            subtitle: Text(
              unread > 0
                  ? AppStrings.of(context)
                        .feature('{count} nya supportsvar')
                        .replaceFirst('{count}', '$unread')
                  : AppStrings.of(context)
                        .feature('{count} supportärenden')
                        .replaceFirst('{count}', '${items.length}'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unread > 0) Badge.count(count: unread),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: _openSupportCases,
          ),
        ),
      );
    },
  );

  void _scheduleStaleResync() {
    if (_staleResync?.isActive == true || !mounted) return;
    final seconds = switch (_staleResyncAttempt) {
      0 => 3,
      1 => 5,
      2 => 10,
      _ => 30,
    };
    _staleResync = Timer(Duration(seconds: seconds), () async {
      _staleResync = null;
      if (!mounted || !_data.state.isStale) return;
      final succeeded = await _data.refresh();
      if (succeeded) {
        _clearStaleResync();
      } else {
        _staleResyncAttempt++;
        _scheduleStaleResync();
      }
    });
  }

  void _clearStaleResync() {
    _staleResync?.cancel();
    _staleResync = null;
    _staleResyncAttempt = 0;
  }

  Future<void> _markAllRead() async {
    final strings = AppStrings.of(context);
    try {
      await widget.messaging.markAllRead([
        widget.contextValue.id,
        ...widget.contextValue.aliasIds,
      ], _newUuid());
      if (mounted) await _data.refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.safeError)));
      }
    }
  }

  Future<void> _showMessagingSettings() async {
    if (_settingsPending) return;
    final strings = AppStrings.of(context);
    setState(() => _settingsPending = true);
    try {
      final preferences = await widget.messaging.getPreferences();
      if (!mounted) return;
      final enabled = await showDialog<bool>(
        context: context,
        builder: (context) =>
            _MessagingSettingsDialog(pushEnabled: preferences.pushEnabled),
      );
      if (enabled == null || enabled == preferences.pushEnabled) return;
      await widget.messaging.setPushEnabled(enabled, _newUuid());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.feature('Inställningen sparades'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.safeError)));
      }
    } finally {
      if (mounted) setState(() => _settingsPending = false);
    }
  }

  @override
  void didUpdateWidget(covariant _InboxSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) {
      // Switched active team/club elsewhere in the app: the "just the
      // active one" default should follow, discarding any wider selection
      // the user had picked for the old one.
      _selectedContextIds = {widget.contextValue.id};
    } else {
      // Available connections changed (e.g. a membership was added or
      // removed): drop any selected ids that no longer exist, falling back
      // to the active context if that empties the selection.
      final availableIds = widget.contexts.map((context) => context.id).toSet();
      final pruned = _selectedContextIds.intersection(availableIds);
      _selectedContextIds = pruned.isEmpty ? {widget.contextValue.id} : pruned;
    }
    _data.replaceScope(scopeKey: _scopeKey, loader: _reload);
    if (!identical(oldWidget.messaging, widget.messaging)) {
      _subscribeToInbox();
      _subscribeToNotifications();
    }
    if (oldWidget.initialThreadId != widget.initialThreadId) {
      _initialThreadOpened = false;
      if (widget.initialThreadId == null ||
          widget.initialThreadId != _dismissedThreadId) {
        _dismissedThreadId = null;
      }
      _tryOpenInitialThread();
    }
    if (oldWidget.initialAction != widget.initialAction) {
      _openedInitialAction = false;
      _openInitialAction();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _data.removeListener(_syncList);
    _resyncDebounce?.cancel();
    _supportRefreshTimer?.cancel();
    _clearStaleResync();
    unawaited(_inboxSync?.cancel());
    unawaited(_notificationSync?.cancel());
    unawaited(_browserOnlineSync?.cancel());
    _data.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    return Scaffold(
      floatingActionButtonLocation: _assistantUsesFab(context)
          ? _aboveAssistantFabLocation
          : null,
      persistentFooterButtons: compact
          ? null
          : [
              TextButton.icon(
                onPressed: _showRequests,
                icon: const Icon(Icons.mark_email_unread_outlined),
                label: Text(AppStrings.of(context).feature('Förfrågningar')),
              ),
              TextButton.icon(
                onPressed: _crossClub,
                icon: const Icon(Icons.travel_explore),
                label: Text(AppStrings.of(context).feature('Ledarkontakt')),
              ),
              TextButton.icon(
                onPressed: _showNotifications,
                icon: Badge(
                  isLabelVisible: _notificationUnread > 0,
                  label: Text('$_notificationUnread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                label: Text(AppStrings.of(context).feature('Notiser')),
              ),
              TextButton.icon(
                onPressed: _settingsPending ? null : _showMessagingSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(AppStrings.of(context).feature('Inställningar')),
              ),
            ],
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        tooltip: strings.newMessage,
        child: const Icon(Icons.edit),
      ),
      body: Column(
        children: [
          _supportInboxEntry(context),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([_data, _list]),
              builder: (context, _) {
                final state = _data.state;
                if (state.phase == AsyncDataPhase.loading) {
                  return AppLoadingIndicator(
                    label: AppStrings.of(context).loading,
                  );
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
                final threads = _list.visibleItems;
                final attentionAnnouncements = threads
                    .where(
                      (thread) =>
                          thread.type == 'announcement' &&
                          thread.unreadCount > 0,
                    )
                    .toList(growable: false);
                final archivedAnnouncements = threads
                    .where(
                      (thread) =>
                          thread.type == 'announcement' &&
                          thread.unreadCount == 0,
                    )
                    .toList(growable: false);
                final conversations = threads
                    .where((thread) => thread.type != 'announcement')
                    .toList(growable: false);
                final clubs = _groupByClub(conversations);
                if (state.phase == AsyncDataPhase.empty) {
                  return Center(
                    child: _StateCard(
                      icon: Icons.inbox_outlined,
                      title: strings.inboxEmpty,
                      message: strings.inboxSafeEmpty,
                      action: FilledButton.icon(
                        onPressed: _compose,
                        icon: const Icon(Icons.edit),
                        label: Text(strings.newMessage),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: SearchBar(
                        leading: const Icon(Icons.search),
                        hintText: AppStrings.of(
                          context,
                        ).feature('Sök i inkorgen'),
                        onChanged: _list.setQuery,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: strings.feature('Filtrera inkorgen'),
                            onPressed: _showFilterSheet,
                            icon: Badge(
                              isLabelVisible:
                                  _filter != 'all' ||
                                  _selectedContextIds.length > 1,
                              smallSize: 8,
                              child: const Icon(Icons.filter_list),
                            ),
                          ),
                          const Spacer(),
                          if (compact)
                            IconButton(
                              tooltip: strings.feature(
                                'Markera alla som lästa',
                              ),
                              onPressed:
                                  state.data?.any(
                                        (item) => item.unreadCount > 0,
                                      ) ==
                                      true
                                  ? _markAllRead
                                  : null,
                              icon: const Icon(Icons.done_all),
                            )
                          else
                            TextButton.icon(
                              onPressed:
                                  state.data?.any(
                                        (item) => item.unreadCount > 0,
                                      ) ==
                                      true
                                  ? _markAllRead
                                  : null,
                              icon: const Icon(Icons.done_all),
                              label: Text(
                                strings.feature('Markera alla som lästa'),
                              ),
                            ),
                          if (compact)
                            PopupMenuButton<String>(
                              tooltip: strings.feature('Fler inkorgsåtgärder'),
                              onSelected: _handleCompactAction,
                              itemBuilder: (context) => [
                                _compactAction(
                                  context,
                                  value: 'requests',
                                  icon: Icons.mark_email_unread_outlined,
                                  label: 'Förfrågningar',
                                ),
                                _compactAction(
                                  context,
                                  value: 'cross_club',
                                  icon: Icons.travel_explore,
                                  label: 'Ledarkontakt',
                                ),
                                _compactAction(
                                  context,
                                  value: 'notifications',
                                  icon: Icons.notifications_outlined,
                                  label: 'Notiser',
                                ),
                                _compactAction(
                                  context,
                                  value: 'settings',
                                  icon: Icons.settings_outlined,
                                  label: 'Inställningar',
                                ),
                              ],
                              icon: const Icon(Icons.more_vert),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: threads.isEmpty
                          ? _StateCard(
                              icon: Icons.search_off,
                              title: AppStrings.of(
                                context,
                              ).feature('Inga matchande konversationer'),
                              message: AppStrings.of(
                                context,
                              ).feature('Ändra sökningen eller rensa filtret.'),
                              action: TextButton(
                                onPressed: _list.clearQueryAndFilter,
                                child: Text(
                                  AppStrings.of(context).feature(
                                    _list.query.isNotEmpty
                                        ? 'Rensa sökning'
                                        : 'Rensa filter',
                                  ),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _refresh,
                              child: ListView(
                                padding: const EdgeInsets.all(12),
                                children: [
                                  if (state.isStale)
                                    Card(
                                      child: ListTile(
                                        leading: const Icon(Icons.cloud_off),
                                        title: Text(strings.offlineData),
                                        subtitle: state.lastUpdated == null
                                            ? null
                                            : Text(
                                                strings.lastUpdated(
                                                  state.lastUpdated!,
                                                ),
                                              ),
                                      ),
                                    ),
                                  if (attentionAnnouncements.isNotEmpty) ...[
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.tertiary,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.campaign),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              strings.feature(
                                                'Behöver din uppmärksamhet',
                                              ),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                          ),
                                          Badge(
                                            label: Text(
                                              '${attentionAnnouncements.length}',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    for (final thread in attentionAnnouncements)
                                      Card(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.tertiaryContainer,
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: ListTile(
                                          leading: const Icon(Icons.campaign),
                                          title: Text(
                                            thread.subject ??
                                                strings.feature(
                                                  'Viktigt anslag',
                                                ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${thread.preview ?? strings.noMessages}\n${_inboxTime(context, thread.lastAt)}',
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          trailing: const Icon(
                                            Icons.priority_high_rounded,
                                          ),
                                          onTap: () => _openThread(thread),
                                        ),
                                      ),
                                  ],
                                  for (final club in clubs) ...[
                                    Builder(
                                      builder: (context) {
                                        final expanded = _isClubExpanded(
                                          club.club,
                                          clubs.length,
                                        );
                                        return _InboxClubHeader(
                                          key: ValueKey(
                                            'inbox-club-${club.club}',
                                          ),
                                          title: strings.inboxGroupTitle(
                                            club.club,
                                          ),
                                          count: club.threads.length,
                                          unread: club.threads.fold(
                                            0,
                                            (sum, thread) =>
                                                sum + thread.unreadCount,
                                          ),
                                          expanded: expanded,
                                          onTap: () => setState(
                                            () => _clubExpanded[club.club] =
                                                !expanded,
                                          ),
                                        );
                                      },
                                    ),
                                    if (_isClubExpanded(
                                      club.club,
                                      clubs.length,
                                    ))
                                      for (final group in _groupThreads(
                                        club.threads,
                                      )) ...[
                                        // Team headings inside a club; a club with
                                        // only its own club-wide threads needs none.
                                        if (group.title != club.club ||
                                            _groupThreads(club.threads).length >
                                                1)
                                          _InboxTeamHeading(
                                            title: group.title == club.club
                                                ? strings.feature(
                                                    'Hela klubben',
                                                  )
                                                : strings.inboxGroupTitle(
                                                    group.title,
                                                  ),
                                            subtitle: group.title == 'Flera lag'
                                                ? group.subtitle
                                                : null,
                                            count: group.threads.length,
                                          ),
                                        for (final thread in group.threads)
                                          _threadCard(context, strings, thread),
                                      ],
                                  ],
                                  if (archivedAnnouncements.isNotEmpty)
                                    Card(
                                      margin: const EdgeInsets.only(top: 8),
                                      child: ExpansionTile(
                                        initiallyExpanded:
                                            _announcementArchiveExpanded,
                                        onExpansionChanged: (expanded) =>
                                            setState(
                                              () =>
                                                  _announcementArchiveExpanded =
                                                      expanded,
                                            ),
                                        leading: const Icon(
                                          Icons.archive_outlined,
                                        ),
                                        title: Text(
                                          '${strings.feature('Arkiverade anslag')} (${archivedAnnouncements.length})',
                                        ),
                                        children: [
                                          for (final thread
                                              in archivedAnnouncements)
                                            ListTile(
                                              leading: const Icon(
                                                Icons.campaign_outlined,
                                              ),
                                              title: Text(
                                                thread.subject ??
                                                    strings.feature('Anslag'),
                                              ),
                                              subtitle: Text(
                                                '${thread.preview ?? strings.noMessages}\n${_inboxTime(context, thread.lastAt)}',
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              onTap: () => _openThread(thread),
                                            ),
                                        ],
                                      ),
                                    ),
                                  if (_list.hasMore)
                                    TextButton.icon(
                                      onPressed: _list.loadMore,
                                      icon: const Icon(Icons.expand_more),
                                      label: Text(
                                        AppStrings.of(
                                          context,
                                        ).feature('Visa fler'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _threadCard(
    BuildContext context,
    AppStrings strings,
    MessageThreadSummary thread,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      leading: Icon(
        thread.muted
            ? Icons.notifications_off_outlined
            : thread.type == 'group'
            ? Icons.groups_outlined
            : Icons.forum_outlined,
      ),
      title: Text(thread.subject ?? strings.directMessage),
      subtitle: Text(
        '${(thread.senderName ?? '').trim().isEmpty ? '' : '${thread.senderName}: '}${thread.preview ?? strings.noMessages}\n${_inboxTime(context, thread.lastAt)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thread.pinned) const Icon(Icons.push_pin, size: 18),
          if (thread.unreadCount > 0)
            Badge(label: Text('${thread.unreadCount}')),
        ],
      ),
      onTap: () => _openThread(thread),
    ),
  );

  String _announcementSendError(AppStrings strings, Object error) {
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      if (message.contains('no_recipients')) {
        return strings.feature(
          'Det finns inga aktiva mottagare i den valda målgruppen.',
        );
      }
      if (message.contains('not_found') || error.code == '42501') {
        return strings.feature(
          'Du saknar behörighet att skicka anslaget i vald omfattning.',
        );
      }
      if (message.contains('invalid_announcement') ||
          message.contains('invalid_audience')) {
        return strings.feature(
          'Kontrollera rubrik, meddelande och målgrupp och försök igen.',
        );
      }
      return strings
          .feature('Anslaget kunde inte skickas. Serverkod: {code}')
          .replaceFirst('{code}', error.code ?? 'okänd');
    }
    return strings.feature(
      'Anslaget kunde inte skickas. Kontrollera anslutningen och försök igen.',
    );
  }

  PopupMenuItem<String> _compactAction(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
  }) => PopupMenuItem<String>(
    value: value,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(AppStrings.of(context).feature(label)),
    ),
  );

  void _handleCompactAction(String action) {
    switch (action) {
      case 'requests':
        unawaited(_showRequests());
        break;
      case 'cross_club':
        unawaited(_crossClub());
        break;
      case 'notifications':
        unawaited(_showNotifications());
        break;
      case 'settings':
        unawaited(_showMessagingSettings());
        break;
    }
  }

  Future<void> _compose() async {
    final strings = AppStrings.of(context);
    List<AllowedRecipient> recipients;
    try {
      recipients = await widget.messaging.resolveRecipients(
        widget.contextValue.id,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.safeError)));
      }
      return;
    }
    if (!mounted) return;
    TeamZoneContext? clubMessagingContext;
    for (final candidate in widget.contexts) {
      if (candidate.clubId == widget.contextValue.clubId &&
          candidate.teamId == null &&
          candidate.can('club.messaging.manage')) {
        clubMessagingContext = candidate;
        break;
      }
    }
    final draft = await showDialog<_ComposeDraft>(
      context: context,
      builder: (context) => _ComposeDialog(
        recipients: recipients,
        hasTeamScope: widget.contextValue.teamId != null,
        canUseClubScope: clubMessagingContext != null,
        teamName: widget.contextValue.teamName,
        clubName: widget.contextValue.clubName,
        canCreateAnnouncement:
            widget.contextValue.rolePackage == 'leader' ||
            clubMessagingContext != null,
      ),
    );
    if (draft == null || !mounted) return;
    String id;
    try {
      id = draft.type == 'announcement'
          ? await widget.messaging.createAnnouncement(
              contextId: draft.scope == 'club'
                  ? clubMessagingContext!.id
                  : widget.contextValue.id,
              subject: draft.subject,
              body: draft.body,
              audienceRoles: draft.audienceRoles,
              idempotencyKey: _newUuid(),
            )
          : await widget.messaging.createThread(
              contextId: widget.contextValue.id,
              type: draft.type,
              subject: draft.subject,
              recipientIds: draft.recipientIds,
              idempotencyKey: _newUuid(),
            );
    } catch (error) {
      if (mounted) {
        final message = draft.type == 'announcement'
            ? _announcementSendError(strings, error)
            : strings.safeError;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    if (!mounted) return;
    unawaited(_data.refresh());
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _openThread(
      MessageThreadSummary(
        id: id,
        type: draft.type,
        subject: draft.subject.isEmpty ? null : draft.subject,
        revision: draft.type == 'announcement' ? 2 : 1,
        unreadCount: 0,
        muted: false,
        canSend: draft.type != 'announcement',
        lastAt: DateTime.now(),
      ),
    );
  }

  Future<void> _showRequests() async {
    try {
      final requests = await widget.messaging.listRequests();
      if (!mounted) return;
      String? acceptedThreadId;
      String? acceptedRequesterName;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppStrings.of(context).feature('Kontaktförfrågningar')),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (requests.isEmpty)
                  ListTile(
                    title: Text(
                      AppStrings.of(
                        context,
                      ).feature('Inga väntande förfrågningar'),
                    ),
                  ),
                for (final request in requests)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(
                            AppStrings.of(
                              context,
                            ).contactRequestFrom(request.requesterName),
                          ),
                          subtitle: Text(request.requesterAffiliation),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            AppStrings.of(context).contactIssue(
                              _contactReasonLabel(request.reasonCode),
                            ),
                          ),
                        ),
                        if (request.text?.trim().isNotEmpty ?? false)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Text(
                              request.text!.trim(),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            AppStrings.of(context).feature(
                              'Om du accepterar kan ni starta en privat konversation i TeamZone.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            AppStrings.of(context).contactExpires(
                              MaterialLocalizations.of(
                                context,
                              ).formatShortDate(request.expiresAt.toLocal()),
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () async {
                                await widget.messaging.decideRequest(
                                  request.id,
                                  'declined',
                                  _newUuid(),
                                );
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              },
                              child: Text(
                                AppStrings.of(context).feature('Avvisa'),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await widget.messaging.decideRequest(
                                  request.id,
                                  'blocked',
                                  _newUuid(),
                                );
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              },
                              child: Text(
                                AppStrings.of(context).feature('Blockera'),
                              ),
                            ),
                            FilledButton(
                              onPressed: () async {
                                acceptedThreadId = await widget.messaging
                                    .decideRequest(
                                      request.id,
                                      'accepted',
                                      _newUuid(),
                                    );
                                acceptedRequesterName = request.requesterName;
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              },
                              child: Text(
                                AppStrings.of(context).feature('Acceptera'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).feature('Stäng')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      await _data.refresh();
      if (!mounted || acceptedThreadId == null) return;
      await _openThread(
        MessageThreadSummary(
          id: acceptedThreadId!,
          type: 'cross_club_direct',
          subject: acceptedRequesterName,
          revision: 1,
          unreadCount: 0,
          muted: false,
          canSend: true,
          lastAt: DateTime.now(),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  String _contactReasonLabel(String reasonCode) =>
      AppStrings.of(context).contactReasonLabel(reasonCode);

  Future<void> _showNotifications() async {
    var sheetRefreshGeneration = 0;
    try {
      var center = await widget.messaging.listNotifications();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            _refreshOpenNotifications = () {
              final generation = ++sheetRefreshGeneration;
              unawaited(() async {
                try {
                  final updated = await widget.messaging.listNotifications();
                  if (sheetContext.mounted &&
                      generation == sheetRefreshGeneration) {
                    setSheetState(() => center = updated);
                  }
                } catch (_) {
                  // Keep the last known list; the next invalidation can retry.
                }
              }());
            };
            void showError() {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(AppStrings.of(sheetContext).safeError),
                  ),
                );
              }
            }

            // Read without opening: the item stays, the count drops.
            Future<void> markRead(NotificationItem item) async {
              try {
                await widget.messaging.setNotificationState(
                  item.id,
                  'read',
                  _newUuid(),
                );
              } catch (_) {
                showError();
                return;
              }
              if (!sheetContext.mounted) return;
              setSheetState(() {
                center = NotificationCenter(
                  items: [
                    for (final value in center.items)
                      value.id == item.id ? value.asRead() : value,
                  ],
                  unreadCount: center.unreadCount > 0 && item.unread
                      ? center.unreadCount - 1
                      : center.unreadCount,
                );
              });
              unawaited(_refreshNotificationBadge());
            }

            // Removed from the list for you (dismissed); nothing else changes.
            Future<bool> dismiss(NotificationItem item) async {
              try {
                await widget.messaging.setNotificationState(
                  item.id,
                  'dismissed',
                  _newUuid(),
                );
                return true;
              } catch (_) {
                showError();
                return false;
              }
            }

            void removeLocally(NotificationItem item) {
              setSheetState(() {
                center = NotificationCenter(
                  items: center.items
                      .where((value) => value.id != item.id)
                      .toList(growable: false),
                  unreadCount: center.unreadCount - (item.unread ? 1 : 0),
                );
              });
              unawaited(_refreshNotificationBadge());
            }

            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: Text(AppStrings.of(context).feature('Notiser')),
                    subtitle: Text(
                      AppStrings.of(context).feature(
                        'Meddelandeförhandsvisningar visas bara här för chattar du har tillgång till.',
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: center.unreadCount == 0
                          ? null
                          : () async {
                              await widget.messaging.markAllNotificationsRead(
                                _newUuid(),
                              );
                              center = await widget.messaging
                                  .listNotifications();
                              if (sheetContext.mounted) setSheetState(() {});
                            },
                      child: Text(AppStrings.of(context).feature('Läs alla')),
                    ),
                  ),
                  if (center.items.isEmpty)
                    ListTile(
                      title: Text(
                        AppStrings.of(context).feature('Inga notiser'),
                      ),
                    ),
                  for (final item in center.items)
                    Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_outline),
                      ),
                      confirmDismiss: (_) => dismiss(item),
                      onDismissed: (_) => removeLocally(item),
                      child: ListTile(
                        leading: Icon(
                          item.category == 'message'
                              ? Icons.forum_outlined
                              : item.category.startsWith('callup')
                              ? Icons.how_to_reg_outlined
                              : Icons.notifications_none,
                        ),
                        title: Text(
                          item.category == 'message' && item.chatName != null
                              ? item.chatName!
                              : item.title,
                          style: item.unread
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : null,
                        ),
                        subtitle: Text(
                          _notificationSubtitle(context, item),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.unread)
                              IconButton(
                                key: ValueKey('notification-read-${item.id}'),
                                tooltip: AppStrings.of(
                                  context,
                                ).feature('Markera som läst'),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => markRead(item),
                                icon: Badge(
                                  child: Icon(
                                    Icons.mark_email_read_outlined,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                            IconButton(
                              key: ValueKey('notification-dismiss-${item.id}'),
                              tooltip: AppStrings.of(
                                context,
                              ).feature('Ta bort notisen'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                if (await dismiss(item) &&
                                    sheetContext.mounted) {
                                  removeLocally(item);
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        onTap: () async {
                          if (item.unread) {
                            await widget.messaging.setNotificationState(
                              item.id,
                              'read',
                              _newUuid(),
                            );
                          }
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          final target = Uri.tryParse(item.deepLink);
                          if (target?.scheme == 'https' &&
                              target?.host == 'public.teamzoneapp.se') {
                            await launchUrl(
                              target!,
                              mode: LaunchMode.externalApplication,
                            );
                          } else {
                            widget.onNavigate(item.deepLink);
                          }
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
      await _refreshNotificationBadge();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    } finally {
      _refreshOpenNotifications = null;
    }
  }

  Future<void> _crossClub() async {
    final search = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Hitta extern kontakt')),
        content: TextField(
          controller: search,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: AppStrings.of(
              context,
            ).feature('Klubb, lag eller ledare'),
            helperText: AppStrings.of(
              context,
            ).feature('Lämna tomt för att visa alla tillåtna kontakter.'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, search.text.trim()),
            child: Text(AppStrings.of(context).feature('Sök')),
          ),
        ],
      ),
    );
    if (query == null || !mounted) return;
    try {
      final leaders = await widget.messaging.searchLeaders(query);
      if (!mounted) return;
      final selected = await showDialog<CrossClubLeader>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(
            AppStrings.of(context).feature('Verifierade ledarkontakter'),
          ),
          children: [
            if (leaders.isEmpty)
              ListTile(
                title: Text(
                  AppStrings.of(context).feature('Inga tillåtna träffar'),
                ),
              ),
            ..._leaderDirectoryEntries(context, leaders),
          ],
        ),
      );
      if (selected == null || !mounted) return;

      final message = TextEditingController();
      String reason = 'match';
      final request = await showDialog<_CrossClubRequestDraft>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              AppStrings.of(context).contactPerson(selected.displayName),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(
                      context,
                    ).feature('Anledning till kontakt'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'match',
                      child: Text(
                        AppStrings.of(context).contactReasonLabel('match'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'event',
                      child: Text(
                        AppStrings.of(context).contactReasonLabel('event'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text(
                        AppStrings.of(context).contactReasonLabel('transfer'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'club_business',
                      child: Text(
                        AppStrings.of(
                          context,
                        ).contactReasonLabel('club_business'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(
                        AppStrings.of(context).contactReasonLabel('other'),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => reason = value ?? 'match'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  maxLength: 160,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(
                      context,
                    ).feature('Ytterligare information (valfritt)'),
                    hintText: AppStrings.of(
                      context,
                    ).feature('Beskriv kort vad du vill kontakta ledaren om.'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.of(context).feature('Avbryt')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _CrossClubRequestDraft(
                    reason: reason,
                    message: message.text.trim(),
                  ),
                ),
                child: Text(AppStrings.of(context).feature('Skicka')),
              ),
            ],
          ),
        ),
      );
      message.dispose();
      if (request == null || !mounted) return;
      await widget.messaging.requestContact(
        selected.profileId,
        request.reason,
        request.message,
        _newUuid(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).feature('Kontaktförfrågan skickad.'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  List<Widget> _leaderDirectoryEntries(
    BuildContext context,
    List<CrossClubLeader> leaders,
  ) {
    final entries = <Widget>[];
    String? currentClub;
    String? currentTeam;
    for (final leader in leaders) {
      if (leader.clubName != currentClub) {
        currentClub = leader.clubName;
        currentTeam = null;
        entries.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(
              leader.clubName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
      }
      if (leader.teamName != currentTeam) {
        currentTeam = leader.teamName;
        entries.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 2),
            child: Text(
              leader.teamName,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
      }
      entries.add(
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, leader),
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(leader.displayName),
            subtitle: Text(AppStrings.of(context).feature('Verifierad ledare')),
          ),
        ),
      );
    }
    return entries;
  }

  Future<void> _openThread(MessageThreadSummary thread) async {
    _initialThreadOpened = true;
    _dismissedThreadId = null;
    _openThreadId = thread.id;
    if (widget.initialThreadId != thread.id) {
      widget.onNavigate(
        Uri(
          path: ProductRouteContract.inbox,
          queryParameters: {'thread': thread.id},
        ).toString(),
      );
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _ThreadDialog(
        thread: thread,
        messaging: widget.messaging,
        contextId: widget.contextValue.id,
      ),
    );
    _dismissedThreadId = thread.id;
    _openThreadId = null;
    if (mounted) {
      // Don't reset _initialThreadOpened here: onNavigate schedules a
      // route change that hasn't reached widget.initialThreadId yet by
      // the time _data.refresh() below completes and notifies _syncList,
      // which would otherwise see the still-stale (just-closed) thread id
      // as an unopened target and immediately reopen the thread we just
      // closed. didUpdateWidget already resets the flag once
      // initialThreadId actually changes on the next rebuild.
      widget.onNavigate(ProductRouteContract.inbox);
      unawaited(_data.refresh());
    }
  }
}

class _ComposeDraft {
  const _ComposeDraft({
    required this.type,
    required this.subject,
    required this.recipientIds,
    this.body = '',
    this.audienceRoles = const [],
    this.scope = 'team',
  });
  final String type;
  final String subject;
  final List<String> recipientIds;
  final String body;
  final List<String> audienceRoles;
  final String scope;
}

class _CrossClubRequestDraft {
  const _CrossClubRequestDraft({required this.reason, required this.message});
  final String reason;
  final String message;
}

class _MessagingSettingsDialog extends StatefulWidget {
  const _MessagingSettingsDialog({required this.pushEnabled});
  final bool pushEnabled;
  @override
  State<_MessagingSettingsDialog> createState() =>
      _MessagingSettingsDialogState();
}

class _MessagingSettingsDialogState extends State<_MessagingSettingsDialog> {
  late bool _pushEnabled = widget.pushEnabled;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.feature('Meddelandeinställningar')),
      content: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _pushEnabled,
        onChanged: (value) => setState(() => _pushEnabled = value),
        title: Text(strings.feature('Frivilliga pushnotiser')),
        subtitle: Text(
          strings.feature(
            'Av som standard. Låsskärmen visar bara att ett nytt meddelande finns.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _pushEnabled),
          child: Text(strings.feature('Spara')),
        ),
      ],
    );
  }
}

class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog({
    required this.recipients,
    required this.hasTeamScope,
    required this.canUseClubScope,
    required this.canCreateAnnouncement,
    required this.teamName,
    required this.clubName,
  });
  final List<AllowedRecipient> recipients;
  final bool hasTeamScope;
  final bool canUseClubScope;
  final bool canCreateAnnouncement;
  final String? teamName;
  final String clubName;
  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _search = TextEditingController();
  final Set<String> _selected = {};
  final Set<String> _audienceRoles = {};
  // Message or announcement; for a message the thread type follows the
  // number of recipients (see _type).
  String _mode = 'message';
  late String _scope = widget.hasTeamScope ? 'team' : 'club';
  String? _validationError;

  /// One recipient is a direct message, several make a group conversation.
  String get _type => _mode == 'announcement'
      ? 'announcement'
      : _selected.length > 1
      ? 'group'
      : 'direct';

  String get _selectedScopeName =>
      _scope == 'club' ? widget.clubName : (widget.teamName ?? widget.clubName);

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toggle(AllowedRecipient recipient) {
    setState(() {
      _validationError = null;
      if (!_selected.add(recipient.profileId)) {
        _selected.remove(recipient.profileId);
      }
    });
  }

  void _submit() {
    final strings = AppStrings.of(context);
    if (_type == 'announcement') {
      if (_subject.text.trim().isEmpty) {
        setState(() => _validationError = strings.feature('Ange en rubrik.'));
        return;
      }
      if (_body.text.trim().isEmpty) {
        setState(
          () => _validationError = strings.feature('Skriv ett meddelande.'),
        );
        return;
      }
      if (_audienceRoles.isEmpty) {
        setState(
          () => _validationError = strings.feature('Välj minst en målgrupp.'),
        );
        return;
      }
      Navigator.pop(
        context,
        _ComposeDraft(
          type: _type,
          subject: _subject.text.trim(),
          recipientIds: const [],
          body: _body.text.trim(),
          audienceRoles: _audienceRoles.toList(growable: false),
          scope: _scope,
        ),
      );
      return;
    }
    if (_selected.isEmpty) {
      setState(() {
        _validationError = strings.feature('Välj minst en mottagare.');
      });
      return;
    }
    if (_type == 'group' && _subject.text.trim().isEmpty) {
      setState(() {
        _validationError = strings.feature('Ange ett gruppnamn.');
      });
      return;
    }
    Navigator.pop(
      context,
      _ComposeDraft(
        type: _type,
        subject: _type == 'group' ? _subject.text.trim() : '',
        recipientIds: _selected.toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final announcement = _mode == 'announcement';
    final height = (MediaQuery.sizeOf(context).height * .72).clamp(
      320.0,
      600.0,
    );
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        children: [
          Icon(announcement ? Icons.campaign_outlined : Icons.edit_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              strings.feature(announcement ? 'Nytt anslag' : 'Nytt meddelande'),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.canCreateAnnouncement) ...[
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'message',
                    label: Text(strings.feature('Meddelande')),
                    icon: const Icon(Icons.forum_outlined),
                  ),
                  ButtonSegment(
                    value: 'announcement',
                    label: Text(strings.feature('Anslag')),
                    icon: const Icon(Icons.campaign_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) => setState(() {
                  _mode = value.single;
                  _validationError = null;
                }),
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: announcement
                  ? _announcementForm(strings)
                  : _recipientPicker(strings, colors),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 8),
              Text(_validationError!, style: TextStyle(color: colors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_outlined, size: 18),
          label: Text(
            strings.feature(
              announcement
                  ? 'Skicka'
                  : _type == 'group'
                  ? 'Skapa grupp'
                  : 'Starta konversation',
            ),
          ),
        ),
      ],
    );
  }

  Widget _recipientPicker(AppStrings strings, ColorScheme colors) {
    final query = _search.text.trim().toLowerCase();
    final matches = widget.recipients
        .where(
          (item) =>
              query.isEmpty || item.displayName.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final chosen = [
      for (final item in widget.recipients)
        if (_selected.contains(item.profileId)) item,
    ];
    final group = _type == 'group';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The conversation type follows from how many are chosen.
        Container(
          key: const ValueKey('compose-kind'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                chosen.isEmpty
                    ? Icons.person_search_outlined
                    : group
                    ? Icons.groups_outlined
                    : Icons.person_outline,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.feature(
                    chosen.isEmpty
                        ? 'Välj en eller flera mottagare'
                        : group
                        ? 'Gruppkonversation'
                        : 'Direktmeddelande',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (chosen.isNotEmpty)
                Text(
                  strings.selectedRecipients(_selected.length),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        if (chosen.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in chosen)
                InputChip(
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(
                    child: Text(
                      _initialsOf(item.displayName),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  label: Text(item.displayName),
                  deleteButtonTooltipMessage: strings
                      .feature('Ta bort {name}')
                      .replaceFirst('{name}', item.displayName),
                  onDeleted: () => _toggle(item),
                ),
            ],
          ),
        ],
        if (group) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('compose-group-name'),
            controller: _subject,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: strings.feature('Gruppnamn'),
              prefixIcon: const Icon(Icons.label_outline),
              isDense: true,
            ),
            onChanged: (_) => setState(() => _validationError = null),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: strings.feature('Sök mottagare'),
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: matches.isEmpty
              ? Center(
                  child: Text(
                    strings.feature('Inga mottagare matchar sökningen.'),
                  ),
                )
              : ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final item = matches[index];
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      secondary: CircleAvatar(
                        radius: 16,
                        child: Text(
                          _initialsOf(item.displayName),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      value: _selected.contains(item.profileId),
                      onChanged: (_) => _toggle(item),
                      title: Text(item.displayName),
                      subtitle: Text(strings.domainValue(item.rolePackage)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _announcementForm(AppStrings strings) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _subject,
          decoration: InputDecoration(labelText: strings.feature('Rubrik')),
          onChanged: (_) => setState(() => _validationError = null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _body,
          minLines: 4,
          maxLines: 8,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: strings.feature('Meddelande'),
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() => _validationError = null),
        ),
        const SizedBox(height: 4),
        Text(
          '${strings.feature('Målgrupp')} · $_selectedScopeName',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final audience in const [
              ('player', 'Spelare'),
              ('leader', 'Ledare'),
              ('guardian', 'Vårdnadshavare'),
              ('all', 'Alla'),
            ])
              FilterChip(
                selected: _audienceRoles.contains(audience.$1),
                label: Text(
                  audience.$1 == 'all'
                      ? '${strings.feature(audience.$2)} i $_selectedScopeName'
                      : strings.feature(audience.$2),
                ),
                onSelected: (_) => setState(() {
                  _validationError = null;
                  if (audience.$1 == 'all') {
                    _audienceRoles
                      ..clear()
                      ..add('all');
                  } else {
                    _audienceRoles.remove('all');
                    if (!_audienceRoles.add(audience.$1)) {
                      _audienceRoles.remove(audience.$1);
                    }
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.canUseClubScope) ...[
          Text(
            strings.feature('Omfattning'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              if (widget.hasTeamScope)
                ButtonSegment(
                  value: 'team',
                  label: Text(widget.teamName ?? strings.feature('Laget')),
                ),
              ButtonSegment(value: 'club', label: Text(widget.clubName)),
            ],
            selected: {_scope},
            onSelectionChanged: (value) =>
                setState(() => _scope = value.single),
          ),
        ] else
          Text(
            '${strings.feature('Omfattning')}: $_selectedScopeName',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}

/// Collapsible club heading in the inbox list. Closed, only the club name,
/// the number of conversations and any unread count show.
class _InboxClubHeader extends StatelessWidget {
  const _InboxClubHeader({
    super.key,
    required this.title,
    required this.count,
    required this.unread,
    required this.expanded,
    required this.onTap,
  });
  final String title;
  final int count, unread;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Semantics(
        button: true,
        expanded: expanded,
        hint: strings.feature(
          expanded ? 'Dölj konversationer' : 'Visa konversationer',
        ),
        child: Material(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (unread > 0) ...[
                    Badge(
                      label: Text('$unread'),
                      backgroundColor: colors.primary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Team heading inside an open club in the inbox list.
class _InboxTeamHeading extends StatelessWidget {
  const _InboxTeamHeading({
    required this.title,
    required this.count,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: title,
              children: [
                if (subtitle != null)
                  TextSpan(
                    text: ' · $subtitle',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Text('$count', style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

String _inboxTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatCompactDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _notificationPreview(NotificationItem item) {
  if (item.category == 'message' &&
      item.messagePreview != null &&
      item.messagePreview!.trim().isNotEmpty) {
    return item.messagePreview!.trim();
  }
  if (item.category != 'message' || item.messageCount <= 0) {
    return item.preview;
  }
  if (item.messageCount == 1) {
    return '1 nytt meddelande i konversationen.';
  }
  return '${item.messageCount} nya meddelanden i konversationen.';
}

String _notificationSubtitle(BuildContext context, NotificationItem item) {
  final sender = item.category == 'message' && item.senderName != null
      ? 'Från ${item.senderName} · '
      : '';
  final count = item.category == 'message' && item.messageCount > 1
      ? '${item.messageCount} nya · '
      : '';
  return '$sender${_notificationPreview(item)}\n$count${_inboxTime(context, item.createdAt)}';
}

class _ThreadDialog extends StatefulWidget {
  const _ThreadDialog({
    required this.thread,
    required this.messaging,
    required this.contextId,
  });
  final MessageThreadSummary thread;
  final MessagingServices messaging;
  final String contextId;
  @override
  State<_ThreadDialog> createState() => _ThreadDialogState();
}

class _PendingMessage {
  _PendingMessage({
    required this.body,
    required this.idempotencyKey,
    required this.stagedFileIds,
  });
  final String body;
  final String idempotencyKey;
  final List<String> stagedFileIds;
  bool failed = false;
  bool accessLost = false;
}

class _ThreadDialogState extends State<_ThreadDialog>
    with WidgetsBindingObserver {
  final _body = TextEditingController();
  late Future<List<MessageFile>> _filesLoad = widget.messaging.listFiles(
    widget.thread.id,
  );
  final List<_PendingMessage> _pending = [];
  List<ThreadMessage>? _messages;
  StreamSubscription<void>? _threadSync;
  StreamSubscription<void>? _browserOnlineSync;
  Timer? _threadResyncDebounce;
  Timer? _reconnectRetry;
  int _reconnectAttempt = 0;
  bool _retryAfterReconnect = false;
  final MessageHistoryRequestGate _historyRequestGate =
      MessageHistoryRequestGate();
  int? _nextBeforeRevision;
  bool _hasMore = false;
  bool _hasLoadedOlderMessages = false;
  bool _loadingMessages = true;
  bool _loadingOlder = false;
  bool _messageLoadFailed = false;
  bool _sending = false;
  late bool _muted = widget.thread.muted;
  late bool _pinned = widget.thread.pinned;
  bool _preferencePending = false;
  StagedMessageFile? _stagedFile;
  String? _stagedName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _browserOnlineSync = browserOnlineSignals().listen(
      (_) => _resyncAfterReconnect(),
    );
    _subscribeToThread();
    unawaited(_replaceMessages());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _resyncAfterReconnect();
    }
  }

  void _resyncAfterReconnect() {
    _retryAfterReconnect = true;
    _reconnectRetry?.cancel();
    _reconnectRetry = null;
    _reconnectAttempt = 0;
    unawaited(_replaceMessages());
  }

  void _scheduleReconnectRetry() {
    if (!mounted || !_retryAfterReconnect || _reconnectRetry != null) return;
    final seconds = switch (_reconnectAttempt) {
      0 => 3,
      1 => 5,
      2 => 10,
      _ => 30,
    };
    _reconnectRetry = Timer(Duration(seconds: seconds), () {
      _reconnectRetry = null;
      if (!mounted || !_retryAfterReconnect) return;
      _reconnectAttempt++;
      unawaited(_replaceMessages());
    });
  }

  void _subscribeToThread() {
    _threadSync = widget.messaging
        .watchThreadInvalidations(widget.thread.id)
        .listen((_) {
          _threadResyncDebounce?.cancel();
          _threadResyncDebounce = Timer(
            const Duration(milliseconds: 250),
            _replaceMessages,
          );
        }, onError: (_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _threadResyncDebounce?.cancel();
    _reconnectRetry?.cancel();
    unawaited(_threadSync?.cancel());
    unawaited(_browserOnlineSync?.cancel());
    _body.dispose();
    super.dispose();
  }

  Future<void> _replaceMessages() async {
    final requestGeneration = _historyRequestGate.startLatest();
    try {
      final page = await widget.messaging.listMessagePage(widget.thread.id);
      if (!mounted || !_historyRequestGate.isCurrent(requestGeneration)) {
        return;
      }
      final mergedPage = mergeNewestMessagePage(
        page,
        current: _messages,
        hasLoadedOlder: _hasLoadedOlderMessages,
        olderHasMore: _hasMore,
        olderCursor: _nextBeforeRevision,
      );
      _retryAfterReconnect = false;
      _reconnectRetry?.cancel();
      _reconnectRetry = null;
      _reconnectAttempt = 0;
      final replayOlder = _historyRequestGate.finishLatest(
        hasMore: mergedPage.hasMore,
      );
      setState(() {
        _messages = mergedPage.messages;
        _nextBeforeRevision = mergedPage.nextBeforeRevision;
        _hasMore = mergedPage.hasMore;
        _loadingMessages = false;
        _loadingOlder = false;
        _messageLoadFailed = false;
        _filesLoad = widget.messaging.listFiles(widget.thread.id);
      });
      if (replayOlder) unawaited(_loadOlder());
      if (page.messages.isNotEmpty) {
        try {
          await widget.messaging.markRead(
            widget.thread.id,
            page.messages.last.revision,
            _newUuid(),
          );
        } catch (_) {
          // Reading the message still succeeds if the receipt cannot be
          // persisted. A later open or mark-all action can retry it.
        }
      }
    } catch (_) {
      if (mounted && _historyRequestGate.isCurrent(requestGeneration)) {
        _historyRequestGate.failLatest();
        _scheduleReconnectRetry();
        setState(() {
          _loadingMessages = false;
          _loadingOlder = false;
          _messageLoadFailed = true;
        });
      }
    }
  }

  Future<void> _loadOlder() async {
    final cursor = _nextBeforeRevision;
    if (_loadingOlder || !_hasMore || cursor == null) return;
    final requestGeneration = _historyRequestGate.startOlder();
    setState(() => _loadingOlder = true);
    try {
      final page = await widget.messaging.listMessagePage(
        widget.thread.id,
        beforeRevision: cursor,
      );
      if (!mounted || !_historyRequestGate.isCurrent(requestGeneration)) {
        return;
      }
      final mergedPage = mergeOlderMessagePage(_messages ?? const [], page);
      _historyRequestGate.finishOlder();
      setState(() {
        _messages = mergedPage.messages;
        _nextBeforeRevision = mergedPage.nextBeforeRevision;
        _hasMore = mergedPage.hasMore;
        _hasLoadedOlderMessages = true;
        _loadingOlder = false;
      });
    } catch (_) {
      if (mounted && _historyRequestGate.isCurrent(requestGeneration)) {
        _historyRequestGate.finishOlder();
        setState(() => _loadingOlder = false);
      }
    }
  }

  Future<bool> _confirmLifecycle(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppStrings.of(context).feature('Bekräfta')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _hideThread() async {
    if (!await _confirmLifecycle(
      AppStrings.of(context).feature('Dölj konversation'),
      AppStrings.of(context).feature(
        'Konversationen döljs bara för dig. Övriga deltagare och historiken påverkas inte.',
      ),
    )) {
      return;
    }
    try {
      await widget.messaging.setVisibility(widget.thread.id, true, _newUuid());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  Future<void> _leaveThread() async {
    if (!await _confirmLifecycle(
      AppStrings.of(context).feature('Lämna konversation'),
      AppStrings.of(context).feature(
        'Du lämnar konversationen. Tidigare meddelanden finns kvar för övriga deltagare.',
      ),
    )) {
      return;
    }
    try {
      await widget.messaging.leaveThread(widget.thread.id, _newUuid());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  Future<void> _closeThread() async {
    if (!await _confirmLifecycle(
      AppStrings.of(context).feature('Stäng för nya meddelanden'),
      AppStrings.of(
        context,
      ).feature('Historiken bevaras men ingen kan skicka nya meddelanden.'),
    )) {
      return;
    }
    try {
      await widget.messaging.closeThread(
        widget.thread.id,
        'Stängd av behörig ansvarig',
        _newUuid(),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  Future<void> _send() async {
    if (_sending || _body.text.trim().isEmpty) return;
    final pending = _PendingMessage(
      body: _body.text.trim(),
      idempotencyKey: _newUuid(),
      stagedFileIds: _stagedFile == null ? const [] : [_stagedFile!.id],
    );
    _body.clear();
    setState(() {
      _sending = true;
      _pending.add(pending);
      _stagedFile = null;
      _stagedName = null;
    });
    await _deliver(pending);
  }

  Future<void> _deliver(_PendingMessage pending) async {
    setState(() {
      pending.failed = false;
      pending.accessLost = false;
    });
    try {
      await widget.messaging.send(
        threadId: widget.thread.id,
        body: pending.body,
        idempotencyKey: pending.idempotencyKey,
        stagedFileIds: pending.stagedFileIds,
      );
    } catch (error) {
      assert(() {
        debugPrint('Message send failed: ${error.runtimeType}');
        return true;
      }());
      var accessLost = false;
      if (browserIsOnline()) {
        try {
          await widget.messaging.listMessagePage(widget.thread.id);
        } on PostgrestException catch (readError) {
          accessLost = readError.code == '42501';
        } catch (_) {
          // A failed access probe cannot distinguish a network failure.
        }
      }
      if (mounted) {
        setState(() {
          pending.failed = true;
          pending.accessLost = accessLost;
          _sending = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _pending.remove(pending);
        _sending = false;
      });
      await _replaceMessages();
    }
  }

  Future<void> _pickFile() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final file = pick?.files.single;
    if (file?.bytes == null || !mounted) return;
    final ext = (file!.extension ?? '').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'png'
        ? 'image/png'
        : 'image/jpeg';
    setState(() => _sending = true);
    try {
      final staged = await widget.messaging.stageFile(
        widget.thread.id,
        file.name,
        mime,
        file.bytes!,
      );
      if (mounted) {
        setState(() {
          _stagedFile = staged;
          _stagedName = file.name;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addParticipants() async {
    final strings = AppStrings.of(context);
    try {
      final recipients = await widget.messaging.resolveRecipients(
        widget.contextId,
      );
      if (!mounted) return;
      final selected = await showDialog<List<String>>(
        context: context,
        builder: (context) => _ParticipantPickerDialog(recipients: recipients),
      );
      if (selected == null || selected.isEmpty) return;
      await widget.messaging.addParticipants(
        threadId: widget.thread.id,
        profileIds: selected,
        idempotencyKey: _newUuid(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.feature('Deltagare tillagda'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.safeError)));
      }
    }
  }

  Future<void> _toggleMute() async {
    if (_preferencePending) return;
    final targetMuted = !_muted;
    setState(() => _preferencePending = true);
    try {
      await widget.messaging.setMute(widget.thread.id, targetMuted, _newUuid());
      if (mounted) setState(() => _muted = targetMuted);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    } finally {
      if (mounted) setState(() => _preferencePending = false);
    }
  }

  Future<void> _togglePin() async {
    if (_preferencePending) return;
    final targetPinned = !_pinned;
    setState(() => _preferencePending = true);
    try {
      await widget.messaging.setPin(widget.thread.id, targetPinned, _newUuid());
      if (mounted) setState(() => _pinned = targetPinned);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    } finally {
      if (mounted) setState(() => _preferencePending = false);
    }
  }

  Future<void> _messageAction(ThreadMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.mine && message.state == 'sent')
              ListTile(
                leading: const Icon(Icons.undo),
                title: Text(
                  AppStrings.of(context).feature('Återkalla meddelande'),
                ),
                onTap: () => Navigator.pop(context, 'recall'),
              ),
            if (!message.mine)
              ListTile(
                leading: const Icon(Icons.report_outlined),
                title: Text(
                  AppStrings.of(context).feature('Rapportera och blockera'),
                ),
                subtitle: Text(
                  AppStrings.of(
                    context,
                  ).feature('Vid akut fara ring 112. Misstänkt brott: 114 14.'),
                ),
                onTap: () => Navigator.pop(context, 'report'),
              ),
          ],
        ),
      ),
    );
    String? reportReason;
    if (action == 'report' && mounted) {
      reportReason = await _chooseReportReason();
      if (reportReason == null) return;
    }
    try {
      if (action == 'recall') {
        await widget.messaging.recall(message.id, message.revision, _newUuid());
      }
      if (action == 'report') {
        await widget.messaging.report(message.id, reportReason!, _newUuid());
        if (mounted) Navigator.pop(context);
        return;
      }
      if (action != null && mounted) {
        setState(() {
          _filesLoad = widget.messaging.listFiles(widget.thread.id);
        });
        await _replaceMessages();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  Future<String?> _chooseReportReason() => showDialog<String>(
    context: context,
    builder: (context) {
      final strings = AppStrings.of(context);
      return SimpleDialog(
        title: Text(strings.feature('Varför rapporterar du?')),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              strings.feature('Rapporten blockerar också avsändaren.'),
            ),
          ),
          for (final reason in const [
            ('harassment', 'Trakasserier'),
            ('sexual_content', 'Sexuellt innehåll'),
            ('threat', 'Hot'),
            ('spam', 'Spam'),
            ('other', 'Annat'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, reason.$1),
              child: ListTile(title: Text(strings.feature(reason.$2))),
            ),
        ],
      );
    },
  );

  Widget _buildMessageHistory(AppStrings strings) {
    if (_loadingMessages) {
      return AppLoadingIndicator(label: strings.loading);
    }
    if (_messageLoadFailed && _messages == null) {
      return _StateCard(
        icon: Icons.sync_problem,
        title: strings.couldNotLoad,
        message: strings.safeError,
        action: FilledButton(
          onPressed: () {
            setState(() => _loadingMessages = true);
            unawaited(_replaceMessages());
          },
          child: Text(strings.retry),
        ),
      );
    }
    final messages = _messages ?? const <ThreadMessage>[];
    if (messages.isEmpty && _pending.isEmpty) {
      return Center(child: Text(strings.noMessages));
    }
    return FutureBuilder<List<MessageFile>>(
      future: _filesLoad,
      builder: (context, fileSnapshot) {
        final files = fileSnapshot.data ?? const <MessageFile>[];
        if (widget.thread.type == 'announcement') {
          final first = messages.first;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.campaign,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onTertiaryContainer,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                strings.feature('Information'),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${first.senderName} · ${_inboxTime(context, first.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Divider(height: 32),
                          for (
                            var index = 0;
                            index < messages.length;
                            index++
                          ) ...[
                            if (index > 0) const Divider(height: 28),
                            SelectableText(
                              messages[index].body ?? strings.recalledMessage,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            for (final file in files.where(
                              (item) => item.messageId == messages[index].id,
                            )) ...[
                              const SizedBox(height: 12),
                              _InlineMessageFile(
                                file: file,
                                messaging: widget.messaging,
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        final bubbleMaxWidth = min(
          360.0,
          MediaQuery.sizeOf(context).width * 0.78,
        );
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            if (_hasMore)
              Center(
                child: TextButton.icon(
                  onPressed: _loadingOlder ? null : _loadOlder,
                  icon: _loadingOlder
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.history),
                  label: Text(strings.feature('Visa äldre meddelanden')),
                ),
              ),
            for (final group in groupMessagesForDisplay(messages))
              Align(
                alignment: group.first.mine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: group.first.mine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 8,
                            right: 8,
                            bottom: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!group.first.mine) ...[
                                Text(
                                  group.first.senderName,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                _inboxTime(context, group.first.createdAt),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        for (final message in group.messages) ...[
                          if (message != group.first) const SizedBox(height: 6),
                          Card(
                            margin: EdgeInsets.zero,
                            color: message.mine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onLongPress: () => _messageAction(message),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: message.mine
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.body ?? strings.recalledMessage,
                                      textAlign: message.mine
                                          ? TextAlign.right
                                          : TextAlign.left,
                                    ),
                                    for (final file in files.where(
                                      (item) => item.messageId == message.id,
                                    )) ...[
                                      const SizedBox(height: 6),
                                      _InlineMessageFile(
                                        file: file,
                                        messaging: widget.messaging,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            for (final pending in _pending)
              Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                  child: Card(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: pending.failed
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.secondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SelectableText(pending.body),
                          const SizedBox(height: 4),
                          if (pending.accessLost)
                            Text(
                              strings.feature(
                                'Meddelandet skickades inte eftersom du inte längre har tillgång till konversationen. Kopiera texten innan du stänger.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          else if (pending.failed)
                            TextButton.icon(
                              onPressed: _sending
                                  ? null
                                  : () {
                                      setState(() => _sending = true);
                                      unawaited(_deliver(pending));
                                    },
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                strings.feature('Försök skicka igen'),
                              ),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(strings.feature('Skickar…')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.thread.subject ?? strings.directMessage),
          leading: IconButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(Icons.close),
          ),
          actions: [
            if (widget.thread.type == 'group')
              IconButton(
                onPressed: _addParticipants,
                tooltip: strings.feature('Lägg till deltagare'),
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
            IconButton(
              onPressed: _preferencePending ? null : _togglePin,
              tooltip: strings.feature(_pinned ? 'Lossa tråd' : 'Fäst tråd'),
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            ),
            IconButton(
              onPressed: _preferencePending ? null : _toggleMute,
              tooltip: _muted
                  ? strings.feature('Slå på notiser')
                  : strings.muteThread,
              icon: Icon(
                _muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: strings.feature('Fler alternativ'),
              onSelected: (value) {
                if (value == 'hide') unawaited(_hideThread());
                if (value == 'leave') unawaited(_leaveThread());
                if (value == 'close') unawaited(_closeThread());
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'hide',
                  child: Text(strings.feature('Dölj för mig')),
                ),
                if (widget.thread.canLeave)
                  PopupMenuItem(
                    value: 'leave',
                    child: Text(strings.feature('Lämna konversation')),
                  ),
                if (widget.thread.canManage)
                  PopupMenuItem(
                    value: 'close',
                    child: Text(strings.feature('Stäng för nya meddelanden')),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            const BrowserOfflineNotice(),
            Expanded(child: _buildMessageHistory(strings)),
            if (!widget.thread.canSend && widget.thread.type != 'announcement')
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(strings.feature('Endast information')),
                  subtitle: Text(
                    strings.feature(
                      widget.thread.type == 'announcement'
                          ? 'Anslaget är avslutat och kan inte få fler meddelanden.'
                          : 'Bara avsändaren kan skriva i den här konversationen.',
                    ),
                  ),
                ),
              ),
            if (widget.thread.canSend && widget.thread.type != 'announcement')
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _sending ? null : _pickFile,
                        tooltip: AppStrings.of(context).feature('Bifoga fil'),
                        icon: const Icon(Icons.attach_file),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_stagedName != null)
                              Text(
                                'Bilaga: $_stagedName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            TextField(
                              controller: _body,
                              maxLength: 4000,
                              minLines: 1,
                              maxLines: 4,
                              decoration: InputDecoration(
                                labelText: strings.messageBody,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _sending ? null : _send,
                        tooltip: strings.sendMessage,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantPickerDialog extends StatefulWidget {
  const _ParticipantPickerDialog({required this.recipients});
  final List<AllowedRecipient> recipients;
  @override
  State<_ParticipantPickerDialog> createState() =>
      _ParticipantPickerDialogState();
}

class _ParticipantPickerDialogState extends State<_ParticipantPickerDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(AppStrings.of(context).feature('Lägg till deltagare')),
    content: SizedBox(
      width: 440,
      height: 360,
      child: ListView(
        children: [
          for (final item in widget.recipients)
            CheckboxListTile(
              value: _selected.contains(item.profileId),
              onChanged: (_) => setState(() {
                if (!_selected.add(item.profileId)) {
                  _selected.remove(item.profileId);
                }
              }),
              title: Text(item.displayName),
              subtitle: Text(item.rolePackage),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, _selected.toList(growable: false)),
        child: Text(AppStrings.of(context).feature('Lägg till')),
      ),
    ],
  );
}

class _InlineMessageFile extends StatefulWidget {
  const _InlineMessageFile({required this.file, required this.messaging});
  final MessageFile file;
  final MessagingServices messaging;
  @override
  State<_InlineMessageFile> createState() => _InlineMessageFileState();
}

class _InlineMessageFileState extends State<_InlineMessageFile> {
  late final Future<String> _url = widget.messaging.signedFileUrl(
    widget.file.id,
  );
  Future<void> _open() async {
    try {
      final url = await widget.messaging.signedFileUrl(widget.file.id);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.file.mimeType.startsWith('image/');
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: image
            ? FutureBuilder<String>(
                future: _url,
                builder: (context, snapshot) => snapshot.hasData
                    ? Image.network(
                        snapshot.requireData,
                        width: 240,
                        height: 150,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          height: 96,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 96,
                        child: AppLoadingIndicator(
                          label: AppStrings.of(context).loading,
                        ),
                      ),
              )
            : ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: Text(
                  widget.file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${widget.file.sizeBytes} byte'),
              ),
      ),
    );
  }
}
