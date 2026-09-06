part of '../../app/teamzone_app.dart';

class _InboxSurface extends StatefulWidget {
  const _InboxSurface({
    required this.contextValue,
    required this.messaging,
    this.initialThreadId,
    required this.onNavigate,
  });
  final TeamZoneContext contextValue;
  final MessagingServices messaging;
  final String? initialThreadId;
  final ValueChanged<String> onNavigate;
  @override
  State<_InboxSurface> createState() => _InboxSurfaceState();
}

class _InboxSurfaceState extends State<_InboxSurface> {
  late final AsyncDataController<List<MessageThreadSummary>> _data;
  late final AppListController<MessageThreadSummary> _list;
  StreamSubscription<void>? _inboxSync;
  StreamSubscription<void>? _notificationSync;
  Timer? _resyncDebounce;
  Timer? _staleResync;
  int _staleResyncAttempt = 0;
  String _filter = 'all';
  List<MessageThreadSummary>? _syncedThreads;
  bool _initialThreadOpened = false;
  bool _settingsPending = false;
  int _notificationUnread = 0;
  Future<List<MessageThreadSummary>> _reload() =>
      widget.messaging.listThreads([widget.contextValue.id]);

  @override
  void initState() {
    super.initState();
    _data = AsyncDataController<List<MessageThreadSummary>>(
      scopeKey: widget.contextValue.id,
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
    _data.addListener(_syncList);
    _subscribeToInbox();
    _subscribeToNotifications();
    unawaited(_data.load());
    unawaited(_refreshNotificationBadge());
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
    if (succeeded) _clearStaleResync();
  }

  void _subscribeToNotifications() {
    unawaited(_notificationSync?.cancel());
    _notificationSync = widget.messaging
        .watchNotificationInvalidations()
        .listen((_) => unawaited(_refreshNotificationBadge()), onError: (_) {});
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

  void _syncList() {
    final threads = _data.state.data;
    if (identical(threads, _syncedThreads)) return;
    _syncedThreads = threads;
    _list.replaceItems(threads ?? const []);
    final target = widget.initialThreadId;
    if (!_initialThreadOpened && target != null && threads != null) {
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
      await widget.messaging.markAllRead([widget.contextValue.id], _newUuid());
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
      _data.replaceScope(scopeKey: widget.contextValue.id, loader: _reload);
    }
    if (!identical(oldWidget.messaging, widget.messaging)) {
      _subscribeToInbox();
      _subscribeToNotifications();
    }
    if (oldWidget.initialThreadId != widget.initialThreadId) {
      _initialThreadOpened = false;
    }
  }

  @override
  void dispose() {
    _data.removeListener(_syncList);
    _resyncDebounce?.cancel();
    _clearStaleResync();
    unawaited(_inboxSync?.cancel());
    unawaited(_notificationSync?.cancel());
    _data.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.edit),
        label: Text(strings.newMessage),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_data, _list]),
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
          final threads = _list.visibleItems;
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
                  hintText: AppStrings.of(context).feature('Sök i inkorgen'),
                  onChanged: _list.setQuery,
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 8,
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
                        label: Text(AppStrings.of(context).feature(entry.$2)),
                        selected: _filter == entry.$1,
                        onSelected: (_) => _setFilter(entry.$1),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed:
                        state.data?.any((item) => item.unreadCount > 0) == true
                        ? _markAllRead
                        : null,
                    icon: const Icon(Icons.done_all),
                    label: Text(strings.feature('Markera alla som lästa')),
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
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount:
                              threads.length +
                              (state.isStale ? 1 : 0) +
                              (_list.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (state.isStale && index == 0) {
                              return Card(
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
                              );
                            }
                            final dataIndex = index - (state.isStale ? 1 : 0);
                            if (dataIndex == threads.length) {
                              return TextButton.icon(
                                onPressed: _list.loadMore,
                                icon: const Icon(Icons.expand_more),
                                label: Text(
                                  AppStrings.of(context).feature('Visa fler'),
                                ),
                              );
                            }
                            final thread = threads[dataIndex];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  thread.muted
                                      ? Icons.notifications_off_outlined
                                      : Icons.forum_outlined,
                                ),
                                title: Text(
                                  thread.subject ?? strings.directMessage,
                                ),
                                subtitle: Text(
                                  '${(thread.senderName ?? '').trim().isEmpty ? '' : '${thread.senderName}: '}${thread.preview ?? strings.noMessages}\n${_inboxTime(context, thread.lastAt)}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (thread.pinned)
                                      const Icon(Icons.push_pin, size: 18),
                                    if (thread.unreadCount > 0)
                                      Badge(
                                        label: Text('${thread.unreadCount}'),
                                      ),
                                  ],
                                ),
                                onTap: () => _openThread(thread),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
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
    if (recipients.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.noAllowedRecipients)));
      return;
    }
    final draft = await showDialog<_ComposeDraft>(
      context: context,
      builder: (context) => _ComposeDialog(recipients: recipients),
    );
    if (draft == null || !mounted) return;
    String id;
    try {
      id = draft.type == 'announcement'
          ? await widget.messaging.createAnnouncement(
              contextId: widget.contextValue.id,
              subject: draft.subject,
              recipientIds: draft.recipientIds,
              idempotencyKey: _newUuid(),
            )
          : await widget.messaging.createThread(
              contextId: widget.contextValue.id,
              type: draft.type,
              subject: draft.subject,
              recipientIds: draft.recipientIds,
              idempotencyKey: _newUuid(),
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
    unawaited(_data.refresh());
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _openThread(
      MessageThreadSummary(
        id: id,
        type: draft.type,
        subject: draft.subject.isEmpty ? null : draft.subject,
        revision: 1,
        unreadCount: 0,
        muted: false,
        canSend: true,
        lastAt: DateTime.now(),
      ),
    );
  }

  Future<void> _showRequests() async {
    try {
      final requests = await widget.messaging.listRequests();
      if (!mounted) return;
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
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(request.requesterName),
                          subtitle: Text(
                            '${request.reasonCode}${request.text == null ? '' : ' · ${request.text}'}',
                          ),
                        ),
                        Wrap(
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
                                await widget.messaging.decideRequest(
                                  request.id,
                                  'accepted',
                                  _newUuid(),
                                );
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
      if (mounted) unawaited(_data.refresh());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  Future<void> _showNotifications() async {
    try {
      var center = await widget.messaging.listNotifications();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(AppStrings.of(context).feature('Notiser')),
                  subtitle: Text(
                    AppStrings.of(context).feature(
                      'Säkra förhandsvisningar utan meddelandetext eller personuppgifter.',
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: center.unreadCount == 0
                        ? null
                        : () async {
                            await widget.messaging.markAllNotificationsRead(
                              _newUuid(),
                            );
                            center = await widget.messaging.listNotifications();
                            if (sheetContext.mounted) setSheetState(() {});
                          },
                    child: Text(AppStrings.of(context).feature('Läs alla')),
                  ),
                ),
                if (center.items.isEmpty)
                  ListTile(
                    title: Text(AppStrings.of(context).feature('Inga notiser')),
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
                    confirmDismiss: (_) async {
                      try {
                        await widget.messaging.setNotificationState(
                          item.id,
                          'dismissed',
                          _newUuid(),
                        );
                        return true;
                      } catch (_) {
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppStrings.of(sheetContext).safeError,
                              ),
                            ),
                          );
                        }
                        return false;
                      }
                    },
                    onDismissed: (_) {
                      setSheetState(() {
                        center = NotificationCenter(
                          items: center.items
                              .where((value) => value.id != item.id)
                              .toList(growable: false),
                          unreadCount:
                              center.unreadCount - (item.unread ? 1 : 0),
                        );
                      });
                    },
                    child: ListTile(
                      leading: Icon(
                        item.category == 'message'
                            ? Icons.forum_outlined
                            : item.category.startsWith('callup')
                            ? Icons.how_to_reg_outlined
                            : Icons.notifications_none,
                      ),
                      title: Text(
                        item.title,
                        style: item.unread
                            ? const TextStyle(fontWeight: FontWeight.w700)
                            : null,
                      ),
                      subtitle: Text(
                        '${item.preview}\n${_inboxTime(context, item.createdAt)}',
                      ),
                      isThreeLine: true,
                      trailing: item.unread ? const Badge() : null,
                      onTap: () async {
                        if (item.unread) {
                          await widget.messaging.setNotificationState(
                            item.id,
                            'read',
                            _newUuid(),
                          );
                        }
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        widget.onNavigate(item.deepLink);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await _refreshNotificationBadge();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  Future<void> _crossClub() async {
    final search = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Verifierad ledarkontakt')),
        content: TextField(
          controller: search,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: AppStrings.of(context).feature('Ledarnamn'),
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
            AppStrings.of(context).feature('Tillåtna verifierade ledare'),
          ),
          children: [
            if (leaders.isEmpty)
              ListTile(
                title: Text(
                  AppStrings.of(context).feature('Inga tillåtna träffar'),
                ),
              ),
            for (final leader in leaders)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, leader),
                child: ListTile(
                  title: Text(leader.displayName),
                  subtitle: Text('${leader.clubName} · ${leader.teamName}'),
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      await widget.messaging.requestContact(
        selected.profileId,
        'club_business',
        AppStrings.of(context).feature('Kontaktförfrågan från TeamZone'),
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

  Future<void> _openThread(MessageThreadSummary thread) async {
    _initialThreadOpened = true;
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
    if (mounted) {
      _initialThreadOpened = false;
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
  });
  final String type;
  final String subject;
  final List<String> recipientIds;
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
  const _ComposeDialog({required this.recipients});
  final List<AllowedRecipient> recipients;
  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final _subject = TextEditingController();
  final Set<String> _selected = {};
  String _type = 'direct';

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  void _toggle(AllowedRecipient recipient) {
    setState(() {
      if (_type == 'direct') _selected.clear();
      if (!_selected.add(recipient.profileId)) {
        _selected.remove(recipient.profileId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final valid =
        _selected.isNotEmpty &&
        (_type == 'direct' || _subject.text.trim().isNotEmpty);
    return AlertDialog(
      title: Text(strings.feature('Ny konversation')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'direct',
                  label: Text(strings.feature('Direkt')),
                ),
                ButtonSegment(
                  value: 'group',
                  label: Text(strings.feature('Grupp')),
                ),
                ButtonSegment(
                  value: 'announcement',
                  label: Text(strings.feature('Info')),
                  icon: const Icon(Icons.campaign_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) => setState(() {
                _type = value.single;
                if (_type == 'direct' && _selected.length > 1) {
                  final first = _selected.first;
                  _selected
                    ..clear()
                    ..add(first);
                }
              }),
            ),
            if (_type != 'direct') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _subject,
                decoration: InputDecoration(
                  labelText: _type == 'announcement'
                      ? strings.feature('Rubrik')
                      : strings.feature('Gruppnamn'),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: ListView(
                children: [
                  for (final item in widget.recipients)
                    CheckboxListTile(
                      value: _selected.contains(item.profileId),
                      onChanged: (_) => _toggle(item),
                      title: Text(item.displayName),
                      subtitle: Text(item.rolePackage),
                    ),
                ],
              ),
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
          onPressed: valid
              ? () => Navigator.pop(
                  context,
                  _ComposeDraft(
                    type: _type,
                    subject: _subject.text.trim(),
                    recipientIds: _selected.toList(growable: false),
                  ),
                )
              : null,
          child: Text(strings.feature('Skapa')),
        ),
      ],
    );
  }
}

String _inboxTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatCompactDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
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
}

class _ThreadDialogState extends State<_ThreadDialog> {
  final _body = TextEditingController();
  late Future<List<MessageFile>> _filesLoad = widget.messaging.listFiles(
    widget.thread.id,
  );
  final List<_PendingMessage> _pending = [];
  List<ThreadMessage>? _messages;
  StreamSubscription<void>? _threadSync;
  Timer? _threadResyncDebounce;
  int _messageRequestGeneration = 0;
  int? _nextBeforeRevision;
  bool _hasMore = false;
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
    _subscribeToThread();
    unawaited(_replaceMessages());
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
    _threadResyncDebounce?.cancel();
    unawaited(_threadSync?.cancel());
    _body.dispose();
    super.dispose();
  }

  Future<void> _replaceMessages() async {
    final requestGeneration = ++_messageRequestGeneration;
    try {
      final page = await widget.messaging.listMessagePage(widget.thread.id);
      if (!mounted || requestGeneration != _messageRequestGeneration) return;
      setState(() {
        _messages = page.messages;
        _nextBeforeRevision = page.nextBeforeRevision;
        _hasMore = page.hasMore;
        _loadingMessages = false;
        _loadingOlder = false;
        _messageLoadFailed = false;
        _filesLoad = widget.messaging.listFiles(widget.thread.id);
      });
      if (page.messages.isNotEmpty) {
        unawaited(
          widget.messaging.markRead(
            widget.thread.id,
            page.messages.last.revision,
            _newUuid(),
          ),
        );
      }
    } catch (_) {
      if (mounted && requestGeneration == _messageRequestGeneration) {
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
    final requestGeneration = _messageRequestGeneration;
    setState(() => _loadingOlder = true);
    try {
      final page = await widget.messaging.listMessagePage(
        widget.thread.id,
        beforeRevision: cursor,
      );
      if (!mounted || requestGeneration != _messageRequestGeneration) return;
      final byId = {
        for (final message in [...?_messages, ...page.messages])
          message.id: message,
      };
      final merged = byId.values.toList()
        ..sort((a, b) => a.revision.compareTo(b.revision));
      setState(() {
        _messages = merged;
        _nextBeforeRevision = page.nextBeforeRevision;
        _hasMore = page.hasMore;
        _loadingOlder = false;
      });
    } catch (_) {
      if (mounted && requestGeneration == _messageRequestGeneration) {
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
    setState(() => pending.failed = false);
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
      if (mounted) {
        setState(() {
          pending.failed = true;
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
        return ListView(
          padding: const EdgeInsets.all(16),
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
            for (final message in messages)
              Align(
                alignment: message.mine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: InkWell(
                      onLongPress: () => _messageAction(message),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.senderName,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(message.body ?? strings.recalledMessage),
                          for (final file in files.where(
                            (item) => item.messageId == message.id,
                          )) ...[
                            const SizedBox(height: 8),
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
              ),
            for (final pending in _pending)
              Align(
                alignment: Alignment.centerRight,
                child: Card(
                  color: pending.failed
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pending.body),
                        const SizedBox(height: 4),
                        if (pending.failed)
                          TextButton.icon(
                            onPressed: _sending
                                ? null
                                : () {
                                    setState(() => _sending = true);
                                    unawaited(_deliver(pending));
                                  },
                            icon: const Icon(Icons.refresh),
                            label: Text(strings.feature('Försök skicka igen')),
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
            onPressed: () => Navigator.pop(context),
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
            Expanded(child: _buildMessageHistory(strings)),
            if (!widget.thread.canSend)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(strings.feature('Endast information')),
                  subtitle: Text(
                    strings.feature(
                      'Bara avsändaren kan skriva i den här konversationen.',
                    ),
                  ),
                ),
              ),
            if (widget.thread.canSend)
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
