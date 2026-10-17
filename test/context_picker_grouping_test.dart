import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';

TeamZoneContext _context(String id, String club, String? team) =>
    TeamZoneContext(
      id: id,
      clubId: 'club-$club',
      clubName: club,
      teamId: team == null ? null : 'team-$id',
      teamName: team,
      rolePackage: 'leader',
      capabilities: const {},
    );

void main() {
  test('the active team first, then its club, then the other clubs A–Ö', () {
    final active = _context('j', 'IF Eksjö Fotboll', 'J');
    final groups = groupContextsForPicker([
      _context('o', 'Östra IK', 'P14'),
      _context('a1', 'Alby IF', 'P2012'),
      _context('a0', 'Alby IF', 'F2013'),
      _context('e2', 'IF Eksjö Fotboll', 'A-lag'),
      _context('e0', 'IF Eksjö Fotboll', null),
      active,
      _context('ae', 'Ängby SK', 'P13'),
      _context('aa', 'Åby BK', 'P13'),
    ], active);
    expect(groups.map((group) => group.clubName), [
      'IF Eksjö Fotboll',
      'Alby IF',
      'Åby BK',
      'Ängby SK',
      'Östra IK',
    ]);
    expect(groups.first.contexts.map((item) => item.id), ['j', 'e0', 'e2']);
    expect(groups[1].contexts.map((item) => item.teamName), ['F2013', 'P2012']);
  });

  test('the active context always has a group, even when not listed', () {
    final active = _context('x', 'Bro BK', 'P10');
    final groups = groupContextsForPicker(const [], active);
    expect(groups.single.clubName, 'Bro BK');
    expect(groups.single.contexts.single.id, 'x');
  });
}
