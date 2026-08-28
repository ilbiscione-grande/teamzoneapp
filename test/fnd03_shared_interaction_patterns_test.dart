import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/shared/forms/app_form_controller.dart';
import 'package:teamzone_app/src/shared/lists/app_list_controller.dart';

void main() {
  group('AppFormController', () {
    test('tracks dirty state and cleans a successful submission', () async {
      final controller = AppFormController()..markDirty();

      expect(controller.isDirty, isTrue);
      expect(await controller.run(() async {}), isTrue);
      expect(controller.isDirty, isFalse);
      expect(controller.isPending, isFalse);
      controller.dispose();
    });

    test('prevents a second submission while the first is pending', () async {
      final controller = AppFormController();
      final completion = Completer<void>();
      var calls = 0;

      final first = controller.run(() {
        calls += 1;
        return completion.future;
      });
      expect(controller.isPending, isTrue);
      expect(await controller.run(() async => calls += 1), isFalse);
      expect(calls, 1);

      completion.complete();
      expect(await first, isTrue);
      expect(controller.isPending, isFalse);
      controller.dispose();
    });

    test('keeps dirty state when submission fails', () async {
      final controller = AppFormController()..markDirty();

      await expectLater(
        controller.run(() async => throw StateError('safe test failure')),
        throwsStateError,
      );
      expect(controller.isDirty, isTrue);
      expect(controller.isPending, isFalse);
      controller.dispose();
    });
  });

  group('AppListController', () {
    test('combines search, filter, sort and pagination deterministically', () {
      final controller =
          AppListController<_ListItem>(
            pageSize: 2,
            searchText: (item) => '${item.name} ${item.group}',
          )..replaceItems(const [
            _ListItem('Zara', 'A', true),
            _ListItem('Anna', 'A', true),
            _ListItem('Bo', 'B', false),
            _ListItem('Amina', 'A', true),
          ]);

      expect(controller.visibleItems.map((item) => item.name), [
        'Zara',
        'Anna',
      ]);
      expect(controller.hasMore, isTrue);

      controller.setSort((left, right) => left.name.compareTo(right.name));
      controller.setFilter(key: 'active', predicate: (item) => item.active);
      controller.setQuery('a');
      expect(controller.visibleItems.map((item) => item.name), [
        'Amina',
        'Anna',
      ]);
      expect(controller.hasMore, isTrue);

      controller.loadMore();
      expect(controller.visibleItems.map((item) => item.name), [
        'Amina',
        'Anna',
        'Zara',
      ]);
      controller.dispose();
    });

    test('clear restores the unfiltered first page', () {
      final controller = AppListController<String>(
        pageSize: 1,
        searchText: (item) => item,
      )..replaceItems(const ['One', 'Two']);
      controller.setQuery('two');

      controller.clearQueryAndFilter();

      expect(controller.query, isEmpty);
      expect(controller.visibleItems, ['One']);
      expect(controller.hasMore, isTrue);
      controller.dispose();
    });
  });

  group('ProductRouteContract', () {
    test('accepts every registered route on a cold start', () {
      for (final path in ProductRouteContract.canonicalPaths) {
        expect(ProductRouteContract.canonicalInitialLocation(path), path);
        expect(ProductRouteContract.isCanonical(path), isTrue);
      }
    });

    test('retains a canonical path across refresh and ignores its query', () {
      expect(
        ProductRouteContract.canonicalInitialLocation(
          '/billing?result=success',
        ),
        ProductRouteContract.billing,
      );
    });

    test('falls back safely for unknown or malformed routes', () {
      expect(
        ProductRouteContract.canonicalInitialLocation('/not-registered'),
        ProductRouteContract.home,
      );
      expect(
        ProductRouteContract.canonicalInitialLocation('://invalid'),
        ProductRouteContract.home,
      );
    });
  });

  test('priority surfaces use the shared interaction contracts', () {
    final auth = File(
      'lib/src/features/auth/auth_surfaces.dart',
    ).readAsStringSync();
    final roster = File(
      'lib/src/features/roster/roster_surface.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/src/features/calendar/calendar_surface.dart',
    ).readAsStringSync();
    final inbox = File(
      'lib/src/features/messaging/inbox_surface.dart',
    ).readAsStringSync();

    expect(auth, contains('AppFormController'));
    expect(auth, contains('TextFormField'));
    expect(calendar, contains('AppUnsavedChangesScope'));
    expect(roster, contains('AppListController<RosterPersonSummary>'));
    expect(roster, contains('RefreshIndicator'));
    expect(inbox, contains('AppListController<MessageThreadSummary>'));
    expect(inbox, contains('RefreshIndicator'));
  });
}

class _ListItem {
  const _ListItem(this.name, this.group, this.active);

  final String name;
  final String group;
  final bool active;
}
