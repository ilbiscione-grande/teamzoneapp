import 'dart:async';
import 'package:flutter/material.dart';
import 'assistant_tasks.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';

/// Counts actionable cards, not participants or checklist rows inside a card.
class AssistantTaskBadge extends StatefulWidget {
  const AssistantTaskBadge({
    super.key,
    required this.load,
    required this.refreshToken,
    required this.child,
    this.hideWhenEmpty = false,
  });
  final Future<AssistantTaskSnapshot> Function() load;
  final Object refreshToken;
  final Widget child;

  /// Hides the child (the assistant's button) while there is confirmed to be
  /// nothing current. An unknown count (loading, a read error) still shows
  /// it, so errors stay reachable.
  final bool hideWhenEmpty;

  @override
  State<AssistantTaskBadge> createState() => _AssistantTaskBadgeState();
}

class _AssistantTaskBadgeState extends State<AssistantTaskBadge>
    with WidgetsBindingObserver {
  int? _count;
  // Important ones (today's callups and preparations, clashes) colour the
  // badge red; general ones alone keep it neutral.
  int _important = 0;
  // The last complete answer was zero. Kept while a refresh loads, so the
  // button does not flash on every page change.
  bool _confirmedEmpty = false;
  int _generation = 0;
  Timer? _wakeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant AssistantTaskBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    _wakeTimer?.cancel();
    // Do not retain another context's count while its permissions are checked.
    setState(() => _count = null);
    try {
      final snapshot = await widget.load();
      if (!mounted || generation != _generation) return;
      final complete =
          !snapshot.settingsFailed &&
          !snapshot.personalFailed &&
          snapshot.failedContexts.isEmpty &&
          snapshot.tasks.every((task) => !task.stale);
      setState(() {
        final active = snapshot.tasks.where(
          (task) => task.task.assistantStatus == 'active',
        );
        _count = complete ? active.length : null;
        _important = complete
            ? active.where((task) => task.isImportant).length
            : 0;
        _confirmedEmpty = _count == 0;
      });
      final wakeTimes =
          snapshot.tasks
              .map((task) => task.task.snoozedUntil)
              .whereType<DateTime>()
              .where((time) => time.isAfter(DateTime.now()))
              .toList()
            ..sort();
      if (wakeTimes.isNotEmpty) {
        _wakeTimer = Timer(
          wakeTimes.first.difference(DateTime.now()) +
              const Duration(seconds: 1),
          _refresh,
        );
      }
    } catch (error) {
      AppErrors.caught('assistant_task_badge._refresh', error);

      // An unknown count is not a confirmed zero. The assistant shows read errors.
      if (mounted && generation == _generation) {
        setState(() {
          _count = null;
          _confirmedEmpty = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _wakeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.hideWhenEmpty && _confirmedEmpty
      ? const SizedBox.shrink()
      : Semantics(
          label: _count == null
              ? null
              : _important > 0
              ? '$_count aktuella uppgifter i assistenten, $_important viktiga'
              : '$_count aktuella uppgifter i assistenten',
          child: Badge.count(
            key: const Key('assistant-task-count'),
            count: _count ?? 0,
            isLabelVisible: (_count ?? 0) > 0,
            backgroundColor: _important > 0
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.secondary,
            textColor: _important > 0
                ? Theme.of(context).colorScheme.onError
                : Theme.of(context).colorScheme.onSecondary,
            child: widget.child,
          ),
        );
}
