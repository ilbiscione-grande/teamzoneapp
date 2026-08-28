import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/shared/async/async_data_controller.dart';
import 'package:teamzone_app/src/shared/async/mutation_policy.dart';

void main() {
  test(
    'represents loading, empty and ready without retaining raw errors',
    () async {
      final controller = AsyncDataController<List<String>>(
        scopeKey: 'team-a',
        loader: () async => const [],
        isEmpty: (items) => items.isEmpty,
      );

      expect(controller.state.phase, AsyncDataPhase.loading);
      expect(await controller.load(), isTrue);
      expect(controller.state.phase, AsyncDataPhase.empty);

      controller.replaceScope(
        scopeKey: 'team-b',
        loader: () async => const ['Player'],
      );
      await pumpEventQueue();
      expect(controller.state.phase, AsyncDataPhase.ready);
      expect(controller.state.data, const ['Player']);
      controller.dispose();
    },
  );

  test('ignores a completed request from the previous context', () async {
    final oldRequest = Completer<List<String>>();
    final controller = AsyncDataController<List<String>>(
      scopeKey: 'club-a',
      loader: () => oldRequest.future,
      isEmpty: (items) => items.isEmpty,
    );
    unawaited(controller.load());

    controller.replaceScope(
      scopeKey: 'club-b',
      loader: () async => const ['Club B'],
    );
    await pumpEventQueue();
    oldRequest.complete(const ['Club A']);
    await pumpEventQueue();

    expect(controller.scopeKey, 'club-b');
    expect(controller.state.data, const ['Club B']);
    controller.dispose();
  });

  test('keeps previous data stale when refresh fails', () async {
    var fail = false;
    final controller = AsyncDataController<List<String>>(
      scopeKey: 'team-a',
      loader: () async {
        if (fail) throw StateError('sensitive backend detail');
        return const ['Existing'];
      },
      isEmpty: (items) => items.isEmpty,
    );

    await controller.load();
    fail = true;
    expect(await controller.refresh(), isFalse);
    expect(controller.state.phase, AsyncDataPhase.ready);
    expect(controller.state.data, const ['Existing']);
    expect(controller.state.isStale, isTrue);
    controller.dispose();
  });

  test(
    'reconnect marks data stale and performs a deterministic resync',
    () async {
      var loads = 0;
      final controller = AsyncDataController<List<int>>(
        scopeKey: 'calendar',
        loader: () async => [++loads],
        isEmpty: (items) => items.isEmpty,
      );
      await controller.load();

      controller.setConnection(AppConnectionStatus.offline);
      expect(controller.state.isStale, isTrue);
      controller.setConnection(
        AppConnectionStatus.online,
        resyncOnReconnect: true,
      );
      await pumpEventQueue();

      expect(loads, 2);
      expect(controller.state.data, const [2]);
      expect(controller.state.isStale, isFalse);
      controller.dispose();
    },
  );

  test('mutation policies never silently queue existing commands', () {
    for (final kind in MutationKind.values) {
      expect(
        MutationPolicyRegistry.forKind(kind),
        isNot(OfflineMutationPolicy.queue),
      );
      expect(
        MutationPolicyRegistry.canStart(
          kind: kind,
          connection: AppConnectionStatus.offline,
        ),
        isFalse,
      );
    }
  });
}
