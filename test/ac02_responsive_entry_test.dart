import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';

void main() {
  test('Assistant Coach has a canonical deep-link route', () {
    expect(ProductRouteContract.assistant, '/assistant');
    expect(ProductRouteContract.isCanonical('/assistant'), isTrue);
    expect(
      ProductRouteContract.canonicalInitialLocation('/assistant'),
      '/assistant',
    );
  });

  test('responsive entry contract is present without AC activation', () {
    final source = File(
      'lib/src/features/assistant_coach/assistant_coach_entry.dart',
    ).readAsStringSync();
    expect(source, contains("Key('assistant-coach-mobile-fab')"));
    expect(source, contains("Key('assistant-coach-side-panel')"));
    expect(source, contains("Key('assistant-coach-holding-surface')"));
    expect(source, contains('Semantics('));
    expect(source, contains('FocusTraversalGroup('));
    expect(source, contains('Ingen analys körs'));
    expect(source.toLowerCase(), isNot(contains('watchpoint')));
  });
}
