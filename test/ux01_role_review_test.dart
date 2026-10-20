import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/product_route_contract.dart';
import 'package:teamzone_app/src/features/account/profile_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';

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

  test('absence notices and the people you answer for come with the squad', () {
    final squad = SquadDetails.fromJson({
      'event_id': 'e1',
      'squad_state': 'empty',
      'absence_notices': [
        {'person_id': 'p1', 'name': 'Anna', 'reason_code': 'illness'},
      ],
      'represented_people': [
        {'person_id': 'p1', 'name': 'Anna'},
      ],
    });
    expect(squad.noticeFor('p1')?.reasonCode, 'illness');
    expect(squad.noticeFor('p2'), isNull);
    expect(squad.representedPeople.single.name, 'Anna');
  });

  test('a line-up keeps its order, positions and bench', () {
    final lineup = EventLineup.fromJson({
      'can_edit': false,
      'published': true,
      'revision': 2,
      'formation': '4-4-2',
      'starters': [
        {'person_id': 'p1', 'name': 'Anna', 'position': 'MV'},
        {'person_id': 'p2', 'name': 'Bo'},
      ],
      'substitutes': [
        {'person_id': 'p3', 'name': 'Cia'},
      ],
    });
    expect(lineup.starters.map((x) => (x.name, x.position)), [
      ('Anna', 'MV'),
      ('Bo', null),
    ]);
    expect(lineup.substitutes.single.name, 'Cia');
    expect(lineup.formation, '4-4-2');
  });

  test('the club home carries only what your permissions give', () {
    final home = ClubHome.fromJson({
      'club_id': 'c1',
      'own_name': 'Benjamin Jonsson',
      'own_offices': ['chair'],
      'board': {'active_mandates': 5, 'pending_changes': 1},
      'economy': null,
      'members': null,
      'can_announce': true,
      'teams': [
        {
          'team_id': 't1',
          'name': 'F2013',
          'member_count': 15,
          'upcoming': [
            {
              'title': 'Träning',
              'event_type': 'training',
              'starts_at': '2026-10-21T15:00:00Z',
              'ends_at': '2026-10-21T16:30:00Z',
              'all_day': false,
              'location_name': 'Demovallen',
            },
          ],
        },
      ],
    });
    expect(home.ownOffices, ['chair']);
    expect(home.board?.pendingChanges, 1);
    expect(home.economy, isNull);
    expect(home.members, isNull);
    expect(home.canAnnounce, isTrue);
    expect(home.teams.single.memberCount, 15);
    expect(home.teams.single.upcoming.single.locationName, 'Demovallen');
  });

  test('a recipient names the teams they are in', () {
    final recipient = AllowedRecipient.fromJson({
      'profile_id': 'p1',
      'display_name': 'Anna',
      'role_package': 'player',
      'team_names': 'F2013, P2015',
    });
    expect(recipient.teamNames, 'F2013, P2015');
    expect(
      AllowedRecipient.fromJson({
        'profile_id': 'p2',
        'display_name': 'Bo',
        'role_package': 'club_functionary',
      }).teamNames,
      isNull,
    );
  });
}
