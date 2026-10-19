import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/features/account/profile_models.dart';

void main() {
  test('a message from the player page starts with its recipients', () {
    final uri = Uri.parse(ProductRouteContract.inboxCompose(to: ['p1', 'g1']));
    expect(uri.path, '/inbox');
    expect(uri.queryParameters, {'action': 'compose', 'to': 'p1,g1'});
    expect(Uri.parse(ProductRouteContract.inboxCompose()).queryParameters, {
      'action': 'compose',
    });
  });

  test('guardians come with the contact that may be shown', () {
    final value = PersonGuardians.fromJson({
      'guardians': [
        {
          'person_id': 'g1',
          'name': 'Gun Förälder',
          'has_account': true,
          'phone': '070-1',
          'can_see_contact': true,
        },
        {'person_id': 'g2', 'name': 'Gösta', 'has_account': false},
      ],
      'message_profile_ids': ['p1', 'g1'],
    });
    expect(value.guardians.map((g) => g.name), ['Gun Förälder', 'Gösta']);
    expect(value.guardians.first.canSeeContact, isTrue);
    expect(value.guardians.last.hasAccount, isFalse);
    expect(value.messageProfileIds, ['p1', 'g1']);
  });
}
