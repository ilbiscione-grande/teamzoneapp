import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

void main() {
  test(
    'callup projection exposes guardian acting-as and reminder delivery',
    () {
      final callup = CallupView.fromJson({
        'callup_id': 'callup-1',
        'person_id': 'child-1',
        'name': 'Alex Andersson',
        'state': 'pending',
        'delivery_state': 'delivered',
        'revision': 3,
        'can_respond': true,
        'acting_as_person_id': 'child-1',
        'response_role': 'guardian',
        'last_reminded_at': '2026-08-27T12:00:00Z',
        'reminder_count': 1,
        'reminder_delivery_state': 'delivered',
      });

      expect(callup.canRespond, isTrue);
      expect(callup.actingAsPersonId, 'child-1');
      expect(callup.responseRole, 'guardian');
      expect(callup.reminderCount, 1);
      expect(callup.reminderDeliveryState, 'delivered');
    },
  );

  test('CAL-07 migration scopes responses, reminders and action tokens', () {
    final sql = File(
      'supabase/migrations/20260827074757_cal07_callup_response_guardian_reminder_tokens.sql',
    ).readAsStringSync();

    expect(sql, contains("'callup.response.recorded.v2'"));
    expect(sql, contains('acting_as_person_id=callup.club_person_id'));
    expect(
      sql,
      contains("'illness','injury','unavailable','transport','other'"),
    );
    expect(sql, contains("interval'6 hours'"));
    expect(sql, contains("'callup.callup.reminded.v2'"));
    expect(sql, contains("interval'15 minutes'"));
    expect(sql, contains('allowed_responses'));
    expect(sql, contains("state='consumed',consumed_at=now()"));
    expect(sql, contains("state='revoked'"));
  });

  test('decline reasons are projected only for managers or representatives', () {
    final sql = File(
      'supabase/migrations/20260920125856_cal07_visible_decline_reasons.sql',
    ).readAsStringSync();

    expect(sql, contains('internal.actor_can_manage_squad(target_event_id)'));
    expect(sql, contains('internal.actor_represents_club_person'));
    expect(sql, contains("callup.state='declined'"));
    expect(sql, contains("response.response='declined'"));
    expect(sql, contains("'decline_reasons'"));
    expect(
      sql,
      contains(
        'revoke all on function internal.get_visible_decline_reasons_for_actor(uuid)',
      ),
    );
  });

  test('squad model joins a visible decline reason onto its roster row', () {
    final squad = SquadDetails.fromJson({
      'event_id': 'event-1',
      'squad_state': 'sent',
      'callups': [
        {
          'callup_id': 'callup-1',
          'person_id': 'person-1',
          'name': 'Kim',
          'state': 'declined',
          'delivery_state': 'sent',
          'revision': 2,
          'can_respond': false,
        },
      ],
      'roster': [
        {
          'person_id': 'person-1',
          'name': 'Kim',
          'team_id': 'team-1',
          'team_name': 'F2012',
          'role_package': 'player',
          'in_draft': true,
          'callup_id': 'callup-1',
          'callup_state': 'declined',
        },
      ],
      'decline_reasons': [
        {
          'person_id': 'person-1',
          'decline_reason_code': 'other',
          'decline_reason_text': 'Skolresa',
        },
      ],
    });

    expect(squad.roster.single.declineReasonCode, 'other');
    expect(squad.roster.single.declineReasonText, 'Skolresa');
    expect(squad.callups.single.declineReasonCode, 'other');
  });
}
