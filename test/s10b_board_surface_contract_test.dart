import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('board client is API-only and capability-adapted', () {
    final service = File(
      'lib/src/features/board/board_services.dart',
    ).readAsStringSync();
    final surface = [
      File('lib/src/features/board/board_surface.dart').readAsStringSync(),
      File('lib/src/app/product_shell.dart').readAsStringSync(),
      File('lib/src/app/product_routes.dart').readAsStringSync(),
      File('lib/src/app/product_route_contract.dart').readAsStringSync(),
    ].join('\n');
    final strings = File(
      'lib/src/core/localization/board_strings.dart',
    ).readAsStringSync();
    expect(service, contains("schema('api').rpc"));
    expect(service, isNot(contains(".from('")));
    for (final capability in ['board.read', 'board.manage', 'board.approve']) {
      expect(surface, contains("can('$capability')"));
    }
    expect(surface, contains("path: '/board'"));
    expect(
      surface,
      contains('void didUpdateWidget(covariant _BoardSurface oldWidget)'),
    );
    expect(
      surface,
      allOf(
        contains("static const board = '/board';"),
        contains('auxiliaryPaths = {billing, economy, board, assistant}'),
      ),
      reason: 'A cold Board deep link must survive app bootstrap.',
    );
    expect(surface, contains('BoardStrings.of(context)'));
    expect(strings, contains('2 godkännanden krävs'));
    expect(strings, contains('2 approvals are required'));
  });
}
