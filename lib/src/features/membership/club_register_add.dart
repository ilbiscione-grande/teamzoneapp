import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

// Lägg till person (2026-11-13): the member register adds someone new to
// the club directly, a board member, functionary, club member or leader,
// and can hand them an invitation code to connect their account.

/// A new person the server refused: no_role, invalid_email or invalid_team.
class ClubPersonCreateException implements Exception {
  const ClubPersonCreateException(this.code);
  final String code;
  @override
  String toString() => 'ClubPersonCreateException($code)';
}

/// The leader titles offered when adding a leader, as in Laget.
const clubLeaderTitles = [
  'head_coach',
  'assistant_coach',
  'team_manager',
  'goalkeeper_coach',
  'fitness_coach',
  'equipment_manager',
  'medical_staff',
  'contact_person',
];

/// Creates the person with their roles; returns the new person's id.
Future<String> createClubPersonWith(
  SupabaseClient client, {
  required String clubId,
  required String name,
  String? email,
  required List<String> clubRoles,
  required List<String> leaderTeamIds,
  String? leaderTitle,
  required String idempotencyKey,
}) async {
  try {
    final value = await client
        .schema('api')
        .rpc<Object?>(
          'create_club_person',
          params: {
            'target_club_id': clubId,
            'new_display_name': name,
            'new_email': email,
            'club_roles': clubRoles,
            'leader_team_ids': leaderTeamIds,
            'leader_title': leaderTitle,
            'idempotency_key': idempotencyKey,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (value is! Map || value['person_id'] is! String) {
      throw const FormatException('Invalid create person response.');
    }
    return value['person_id'] as String;
  } on PostgrestException catch (error) {
    for (final code in const ['no_role', 'invalid_email', 'invalid_team']) {
      if (error.message.contains(code)) throw ClubPersonCreateException(code);
    }
    rethrow;
  }
}

/// Issues a 14-day invitation code meant for [email]; returns the code to
/// hand over. The person enters it under Inställningar → Använd kod.
Future<String> issueClubPersonInvitationWith(
  SupabaseClient client, {
  required String personId,
  required String email,
}) async {
  final token = '${newClubRegisterUuid()}${newClubRegisterUuid()}';
  await client
      .schema('api')
      .rpc<Object?>(
        'issue_roster_invitation_v2',
        params: {
          'target_club_person_id': personId,
          'intended_email': email,
          'raw_token': token,
          'expires_at': DateTime.now()
              .add(const Duration(days: 14))
              .toUtc()
              .toIso8601String(),
          'idempotency_key': newClubRegisterUuid(),
        },
      )
      .timeout(const Duration(seconds: 20));
  return token;
}

String newClubRegisterUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
