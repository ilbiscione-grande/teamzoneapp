import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827193735_home03_guardian_home.sql',
  ).readAsStringSync();
  final surface = File(
    'lib/src/features/overview/overview_surface.dart',
  ).readAsStringSync();
  final services = File(
    'lib/src/features/overview/overview_services.dart',
  ).readAsStringSync();
  final models = File(
    'lib/src/features/overview/overview_models.dart',
  ).readAsStringSync();
  final reasonMigration = File(
    'supabase/migrations/20260924102411_home03_visible_own_decline_reason.sql',
  ).readAsStringSync();
  final responseInvalidationMigration = File(
    'supabase/migrations/20260924105355_home_callup_response_invalidation.sql',
  ).readAsStringSync();

  test('guardian and selected child require active relation and team', () {
    expect(migration, contains("context_row.role_package<>'guardian'"));
    expect(
      migration,
      contains('relation.guardian_person_id=guardian_actor_person_id'),
    );
    expect(migration, contains("relation.state='active'"));
    expect(migration, contains('child.id=target_child_person_id'));
    expect(migration, contains('assignment.club_person_id=child.id'));
    expect(migration, contains('assignment.team_id=context_row.team_id'));
  });

  test(
    'projection contains only selected child data and visible acting-as',
    () {
      expect(migration, contains('callup.club_person_id=selected_child_id'));
      expect(migration, contains('selected_child_id acting_as_person_id'));
      expect(migration, contains("'guardian'::text response_role"));
      expect(surface, contains("labelText: 'Visa för barn'"));
      expect(surface, contains("'Du agerar för \${child.displayName}'"));
      expect(
        surface,
        contains("'Svarar som vårdnadshavare för \${widget.actingAsName}'"),
      );
    },
  );

  test('acting-as survives the callup mutation', () {
    expect(surface, contains('actingAsPersonId: callup.actingAsPersonId'));
    expect(surface, contains('expectedRevision: callup.revision'));
    expect(surface, contains('declineReasonCode: reasonCode'));
    expect(surface, contains('declineReasonText: reasonText'));
  });

  test('only the current own or selected-child decline reason reaches Home', () {
    expect(
      reasonMigration,
      contains('internal.get_player_home_for_actor(target_context_id)'),
    );
    expect(
      reasonMigration,
      contains(
        'internal.get_guardian_home_for_actor(target_context_id,target_child_person_id)',
      ),
    );
    expect(
      reasonMigration,
      contains("response.revision=(item.value->>'revision')::bigint"),
    );
    expect(
      reasonMigration,
      contains("case when item.value->>'state'='declined'"),
    );
    expect(
      reasonMigration,
      contains('revoke all on function internal.home_with_own_decline_reasons'),
    );
    expect(surface, contains('_playerCallupDeclineReason(context, callup)'));

    final callup = PlayerHomeCallup.fromJson({
      'callup_id': 'callup-1',
      'event_id': 'event-1',
      'state': 'declined',
      'revision': 2,
      'event_title': 'Träning',
      'event_type': 'training',
      'starts_at': '2026-09-25T12:00:00Z',
      'ends_at': '2026-09-25T13:00:00Z',
      'can_respond': true,
      'response_role': 'guardian',
      'decline_reason_code': 'other',
      'decline_reason_text': 'Skolresa',
    });
    expect(callup.declineReasonCode, 'other');
    expect(callup.declineReasonText, 'Skolresa');
  });

  test(
    'response sends data-free private resync to actor and linked family',
    () {
      expect(
        responseInvalidationMigration,
        contains('after insert on core.callup_responses'),
      );
      expect(
        responseInvalidationMigration,
        contains('select new.actor_profile_id as profile_id'),
      );
      expect(responseInvalidationMigration, contains("link.state='active'"));
      expect(
        responseInvalidationMigration,
        contains("relation.state='active'"),
      );
      expect(
        responseInvalidationMigration,
        contains("guardian_link.state='active'"),
      );
      expect(responseInvalidationMigration, contains("'{}'::jsonb"));
      expect(
        responseInvalidationMigration,
        contains("'notification:center:'||target_profile_id::text"),
      );
      expect(
        surface,
        contains(
          '.watchNotificationInvalidations(includeTeamUpdatePoll: false)',
        ),
      );
    },
  );

  test('child event and messages stay in selected team context', () {
    expect(migration, contains('team_relation.team_id=context_row.team_id'));
    expect(migration, contains('scope.team_id=context_row.team_id'));
    expect(migration, contains("'child_callups'"));
    expect(migration, contains("'unread_message_count'"));
  });

  test('cached guardian relation is stale and read-only per child', () {
    expect(models, contains('GuardianHomeProjection asStale()'));
    expect(services, contains(r"final cacheKey = '$contextId:"));
    expect(services, contains("childPersonId ?? 'default'"));
    expect(services, contains('return cached.asStale()'));
    expect(surface, contains('onChanged: value.isStale'));
    expect(surface, contains('isStale: value.isStale'));
    expect(surface, contains('callup.canRespond && !widget.value.isStale'));
  });
}
