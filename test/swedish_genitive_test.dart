import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/localization/swedish_genitive.dart';

void main() {
  test('team and person names take the right genitive', () {
    expect(swedishGenitive('A'), 'A:s');
    expect(swedishGenitive('J'), 'J:s');
    expect(swedishGenitive('P2014'), 'P2014:s');
    expect(swedishGenitive('IFK'), 'IFK:s');
    expect(swedishGenitive('Herrar A'), 'Herrar A:s');
    expect(swedishGenitive('Anna'), 'Annas');
    expect(swedishGenitive('Damlaget'), 'Damlagets');
    expect(swedishGenitive('Lars'), 'Lars');
    expect(swedishGenitive('Max'), 'Max');
  });
}
