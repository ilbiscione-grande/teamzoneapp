import 'dart:async';

import 'package:flutter/foundation.dart';

enum AsyncDataPhase { loading, ready, empty, failed }

enum AppConnectionStatus { online, reconnecting, offline }

@immutable
class AsyncDataState<T> {
  const AsyncDataState({
    required this.phase,
    required this.connection,
    this.data,
    this.isRefreshing = false,
    this.isStale = false,
    this.lastUpdated,
  });

  const AsyncDataState.loading()
    : this(
        phase: AsyncDataPhase.loading,
        connection: AppConnectionStatus.online,
      );

  final AsyncDataPhase phase;
  final AppConnectionStatus connection;
  final T? data;
  final bool isRefreshing;
  final bool isStale;
  final DateTime? lastUpdated;

  bool get hasData => data != null;

  AsyncDataState<T> copyWith({
    AsyncDataPhase? phase,
    AppConnectionStatus? connection,
    T? data,
    bool? isRefreshing,
    bool? isStale,
    DateTime? lastUpdated,
  }) => AsyncDataState<T>(
    phase: phase ?? this.phase,
    connection: connection ?? this.connection,
    data: data ?? this.data,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isStale: isStale ?? this.isStale,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
}

class AsyncDataController<T> extends ChangeNotifier {
  factory AsyncDataController({
    required Object scopeKey,
    required Future<T> Function() loader,
    required bool Function(T) isEmpty,
    Duration timeout = const Duration(seconds: 15),
  }) => AsyncDataController<T>._(scopeKey, loader, isEmpty, timeout);

  AsyncDataController._(
    this._scopeKey,
    this._loader,
    this._isEmpty,
    this.timeout,
  );

  final Duration timeout;
  Object _scopeKey;
  Future<T> Function() _loader;
  final bool Function(T) _isEmpty;
  AsyncDataState<T> _state = const AsyncDataState.loading();
  int _generation = 0;
  bool _disposed = false;

  AsyncDataState<T> get state => _state;
  Object get scopeKey => _scopeKey;

  Future<bool> load({bool preserveData = false}) async {
    final generation = ++_generation;
    final previous = _state.data;
    if (preserveData && previous != null) {
      _emit(_state.copyWith(isRefreshing: true));
    } else {
      _emit(
        AsyncDataState<T>(
          phase: AsyncDataPhase.loading,
          connection: _state.connection,
        ),
      );
    }

    try {
      final value = await _loader().timeout(timeout);
      if (!_accepts(generation)) return false;
      _emit(
        AsyncDataState<T>(
          phase: _isEmpty(value) ? AsyncDataPhase.empty : AsyncDataPhase.ready,
          connection: AppConnectionStatus.online,
          data: value,
          lastUpdated: DateTime.now(),
        ),
      );
      return true;
    } catch (_) {
      if (!_accepts(generation)) return false;
      if (previous != null) {
        _emit(
          AsyncDataState<T>(
            phase: _isEmpty(previous)
                ? AsyncDataPhase.empty
                : AsyncDataPhase.ready,
            connection: _state.connection,
            data: previous,
            isStale: true,
            lastUpdated: _state.lastUpdated,
          ),
        );
      } else {
        _emit(
          AsyncDataState<T>(
            phase: AsyncDataPhase.failed,
            connection: _state.connection,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> refresh() => load(preserveData: true);

  void replaceScope({
    required Object scopeKey,
    required Future<T> Function() loader,
  }) {
    if (_scopeKey == scopeKey) return;
    _generation++;
    _scopeKey = scopeKey;
    _loader = loader;
    _state = AsyncDataState<T>(
      phase: AsyncDataPhase.loading,
      connection: _state.connection,
    );
    notifyListeners();
    unawaited(load());
  }

  void setConnection(
    AppConnectionStatus connection, {
    bool resyncOnReconnect = false,
  }) {
    final wasOnline = _state.connection == AppConnectionStatus.online;
    _emit(
      _state.copyWith(
        connection: connection,
        isStale: connection == AppConnectionStatus.online
            ? _state.isStale
            : _state.hasData,
      ),
    );
    if (resyncOnReconnect &&
        !wasOnline &&
        connection == AppConnectionStatus.online) {
      unawaited(refresh());
    }
  }

  bool _accepts(int generation) => !_disposed && generation == _generation;

  void _emit(AsyncDataState<T> next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
