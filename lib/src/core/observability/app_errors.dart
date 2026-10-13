/// Failures the app has already handled (a fallback, a neutral message) but
/// that operations should still see. main() installs the sink; tests and an
/// unconfigured app have none, so reporting is then a no-op.
///
/// Only the operation name and the error's type leave the device, as the
/// observability policy requires (PAR-OPS-05): no message, no stack trace.
abstract final class AppErrors {
  static void Function(String operation, Object error)? _sink;
  static final Map<String, DateTime> _lastReported = {};

  /// The same failure is reported at most once per this window.
  static const repeatWindow = Duration(minutes: 10);

  static void install(void Function(String operation, Object error) sink) {
    _sink = sink;
    _lastReported.clear();
  }

  static void uninstall() {
    _sink = null;
    _lastReported.clear();
  }

  /// Reports a caught [error] for [operation] unless it is an expected
  /// connectivity failure or was reported recently.
  static void caught(String operation, Object error, {DateTime? now}) {
    final sink = _sink;
    if (sink == null || isExpected(error)) return;
    final key = '$operation:${error.runtimeType}';
    final at = now ?? DateTime.now();
    final last = _lastReported[key];
    if (last != null && at.difference(last) < repeatWindow) return;
    _lastReported[key] = at;
    sink(operation, error);
  }

  /// Being offline or slow is not a defect: timeouts and transport failures
  /// (matched by type name, so this file needs no dart:io).
  static bool isExpected(Object error) =>
      _expectedTypes.contains(error.runtimeType.toString());

  static const _expectedTypes = {
    'TimeoutException',
    'SocketException',
    'HttpException',
    'ClientException',
    'HandshakeException',
    'AuthRetryableFetchException',
    'RealtimeSubscribeException',
  };
}
