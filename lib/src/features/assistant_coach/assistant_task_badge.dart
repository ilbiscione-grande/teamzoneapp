import 'dart:async';
import 'package:flutter/material.dart';
import 'assistant_tasks.dart';

/// Counts actionable cards, not participants or checklist rows inside a card.
class AssistantTaskBadge extends StatefulWidget {
  const AssistantTaskBadge({
    super.key,
    required this.load,
    required this.refreshToken,
    required this.child,
  });
  final Future<AssistantTaskSnapshot> Function() load;
  final Object refreshToken;
  final Widget child;

  @override
  State<AssistantTaskBadge> createState() => _AssistantTaskBadgeState();
}

class _AssistantTaskBadgeState extends State<AssistantTaskBadge>
    with WidgetsBindingObserver {
  int? _count;
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
      setState(
        () => _count = complete
            ? snapshot.tasks
                  .where((task) => task.task.assistantStatus == 'active')
                  .length
            : null,
      );
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
    } catch (_) {
      // An unknown count is not a confirmed zero. The assistant shows read errors.
      if (mounted && generation == _generation) setState(() => _count = null);
    }
  }

  @override
  void dispose() {
    _wakeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: _count == null ? null : '$_count aktuella uppgifter i assistenten',
    child: Badge.count(
      key: const Key('assistant-task-count'),
      count: _count ?? 0,
      isLabelVisible: (_count ?? 0) > 0,
      child: widget.child,
    ),
  );
}
