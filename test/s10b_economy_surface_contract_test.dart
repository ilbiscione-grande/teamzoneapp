import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('economy client uses only API RPCs and capability gates', () {
    final service = File(
      'lib/src/features/economy/economy_services.dart',
    ).readAsStringSync();
    final surface = [
      File('lib/src/features/economy/economy_surface.dart').readAsStringSync(),
      File('lib/src/app/product_shell.dart').readAsStringSync(),
      File('lib/src/app/product_routes.dart').readAsStringSync(),
    ].join('\n');
    final strings = File(
      'lib/src/core/localization/economy_strings.dart',
    ).readAsStringSync();
    expect(service, contains("schema('api').rpc"));
    expect(service, isNot(contains(".from('")));
    for (final capability in [
      'economy.read',
      'economy.manage',
      'economy.post',
      'economy.approve',
      'economy.reverse',
    ]) {
      expect(surface, contains("can('$capability')"));
    }
    expect(surface, contains("path: '/economy'"));
    expect(
      surface,
      contains('void didUpdateWidget(covariant _EconomySurface oldWidget)'),
    );
    expect(surface, contains('EconomyStrings.of(context)'));
    expect(strings, contains('Economy är inte aktiv'));
    expect(strings, contains('Economy is not active'));
    expect(surface, contains('approvalCount'));
    expect(strings, contains('Du har redan godkänt'));
    expect(strings, contains('Two independent approvals are required'));
    expect(
      RegExp(r'entry\.reversalState\s*==\s*null').hasMatch(surface),
      isTrue,
    );
    expect(strings, contains("'Reversering'"));
    expect(strings, contains("'Reversal'"));
    expect(surface, isNot(contains('_economyErrorMessage(')));
  });
}
