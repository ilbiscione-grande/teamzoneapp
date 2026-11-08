import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/event_identity.dart';

TeamZoneContext ctx(String id, String club, String? team) => TeamZoneContext(
  id: id,
  clubId: club,
  clubName: '$club förening',
  teamId: team,
  teamName: team,
  rolePackage: 'leader',
  capabilities: const {'event.manage'},
);
EventDetails details({bool owner = true}) => EventDetails.fromJson({
  'id': 'event',
  'club_id': 'target',
  'owning_team_id': 'owner',
  'title': 'Aktivitet',
  'event_type': 'training',
  'state': 'scheduled',
  'starts_at': '2026-11-02T18:00:00Z',
  'ends_at': '2026-11-02T19:00:00Z',
  'timezone': 'Europe/Stockholm',
  'revision': 1,
  'teams': [
    {
      'team_id': 'shared',
      'name': 'Delat lag',
      'relation': 'shared',
      'capabilities': ['view'],
    },
    if (owner)
      {'team_id': 'owner', 'name': 'Ägande lag', 'relation': 'primary'},
  ],
});
void main() {
  test('existing API ownership fields are retained', () {
    expect(details().clubId, 'target');
    expect(details().owningTeamId, 'owner');
  });
  test(
    'unrelated club and unrelated team resolve only to an existing owner context',
    () {
      final owner = ctx('owner-context', 'target', 'owner');
      for (final active in [
        ctx('foreign', 'other', 'other-team'),
        ctx('unrelated', 'target', 'other-team'),
      ]) {
        expect(
          eventDetailsContext(details(), active, [active, owner]),
          same(owner),
        );
        expect(
          eventDetailsSubtitle(details(), active, [
            active,
            owner,
          ], fallback: 'Aktivitet'),
          'target förening · Ägande lag',
        );
      }
    },
  );
  test(
    'a shared recipient context is not promoted to its stronger owner role',
    () {
      final shared = ctx('shared-context', 'target', 'shared'),
          owner = ctx('owner-context', 'target', 'owner');
      expect(
        eventDetailsContext(details(), shared, [shared, owner]),
        same(shared),
      );
      expect(
        eventDetailsSubtitle(details(), shared, [owner], fallback: 'Aktivitet'),
        'target förening · Ägande lag',
      );
    },
  );
  test(
    'an unavailable target never borrows an unrelated club name or invents a context',
    () {
      final foreign = ctx('foreign', 'other', 'other-team');
      expect(eventDetailsContext(details(), foreign, [foreign]), same(foreign));
      expect(
        eventDetailsSubtitle(details(), foreign, [
          foreign,
        ], fallback: 'Aktivitet'),
        'Ägande lag',
      );
      expect(
        eventDetailsSubtitle(details(owner: false), foreign, [
          foreign,
        ], fallback: 'Aktivitet'),
        'Aktivitet',
      );
    },
  );
}
