import 'package:teamzone_app/src/shared/async/async_data_controller.dart';

enum OfflineMutationPolicy { block, retryExplicitly, queue }

enum MutationKind {
  signIn,
  rosterCommand,
  eventCommand,
  attendanceBatch,
  messageSend,
  fileUpload,
}

abstract final class MutationPolicyRegistry {
  static const Map<MutationKind, OfflineMutationPolicy> policies = {
    MutationKind.signIn: OfflineMutationPolicy.block,
    MutationKind.rosterCommand: OfflineMutationPolicy.retryExplicitly,
    MutationKind.eventCommand: OfflineMutationPolicy.retryExplicitly,
    MutationKind.attendanceBatch: OfflineMutationPolicy.retryExplicitly,
    MutationKind.messageSend: OfflineMutationPolicy.retryExplicitly,
    MutationKind.fileUpload: OfflineMutationPolicy.retryExplicitly,
  };

  static OfflineMutationPolicy forKind(MutationKind kind) => policies[kind]!;

  static bool canStart({
    required MutationKind kind,
    required AppConnectionStatus connection,
  }) =>
      connection == AppConnectionStatus.online ||
      forKind(kind) == OfflineMutationPolicy.queue;
}
