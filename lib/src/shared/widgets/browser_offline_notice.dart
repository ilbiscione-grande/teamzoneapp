import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/app_strings.dart';
import 'package:teamzone_app/src/shared/connectivity/browser_online_signals.dart';

class BrowserOfflineNotice extends StatefulWidget {
  const BrowserOfflineNotice({
    super.key,
    this.initiallyOnline,
    this.connectionChanges,
  });

  final bool? initiallyOnline;
  final Stream<bool>? connectionChanges;

  @override
  State<BrowserOfflineNotice> createState() => _BrowserOfflineNoticeState();
}

class _BrowserOfflineNoticeState extends State<BrowserOfflineNotice> {
  late bool _online;
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _online = widget.initiallyOnline ?? browserIsOnline();
    _connectionSubscription =
        (widget.connectionChanges ?? browserConnectionChanges()).listen((
          online,
        ) {
          if (mounted && _online != online) setState(() => _online = online);
        });
  }

  @override
  void dispose() {
    unawaited(_connectionSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_online) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: colors.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.of(context).offlineNotice,
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
