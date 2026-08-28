import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';

abstract interface class RosterServices {
  Future<TeamOverview> getTeamOverview({required String teamId});
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  });
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  });
  Future<String> createPerson({
    required String clubId,
    required String teamId,
    required String displayName,
    required String ageClass,
    required DateTime startsAt,
    required String idempotencyKey,
  });
  Future<int> updatePerson({
    required String clubId,
    required String teamId,
    required String personId,
    required String displayName,
    required String ageClass,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<String> issueTargetedInvitation({
    required String personId,
    required String intendedEmail,
    required String token,
    required DateTime expiresAt,
    required String idempotencyKey,
  });
  Future<String> issueGuardianInvitation({
    required String guardianPersonId,
    required String childPersonId,
    required String token,
    required DateTime expiresAt,
    required String idempotencyKey,
  });
  Future<String> issueTeamCode({
    required String clubId,
    required String teamId,
    required String requestedRole,
    required String token,
    required DateTime expiresAt,
    required int maxUses,
    required String idempotencyKey,
  });
  Future<String> claimTeamCode({
    required String token,
    required String idempotencyKey,
  });
  Future<List<InvitationAdminItem>> listInvitationAdmin({
    required String clubId,
    required String teamId,
  });
  Future<int> revokeInvitation({
    required String kind,
    required String invitationId,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<int> endGuardianRelation({
    required String relationId,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<List<PlayEligibilitySummary>> listPlayEligibilities({
    required String clubId,
    required String teamId,
  });
  Future<String> createPlayEligibility({
    required String clubId,
    required String teamId,
    required String personId,
    required String kind,
    required String validityKind,
    required DateTime startsAt,
    DateTime? endsAt,
    DateTime? seasonEndsOn,
    DateTime? reviewDueAt,
    required String sourceNote,
    required String idempotencyKey,
  });
  Future<int> endPlayEligibility({
    required String eligibilityId,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<IntraClubMoveOptions> getIntraClubMoveOptions({
    required String clubId,
    required String sourceTeamId,
  });
  Future<void> movePlayerWithinClub({
    required String clubId,
    required String sourceTeamId,
    required String targetTeamId,
    required String personId,
    required String assignmentId,
    required DateTime effectiveAt,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  });
  Future<RosterLifecycleOptions> getRosterLifecycle({
    required String clubId,
    required String teamId,
  });
  Future<int> archiveTeamAssignment({
    required String clubId,
    required String teamId,
    required String personId,
    required String assignmentId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  });
  Future<String> requestClubPersonErasure({
    required String clubId,
    required String teamId,
    required String personId,
    required String reason,
    required String idempotencyKey,
  });
  Future<int> approveClubPersonErasure({
    required String requestId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  });
  Future<String> requestGlobalPersonErasure({
    required String reason,
    required String idempotencyKey,
  });

  Future<String> claim({required String token, required String idempotencyKey});

  Future<String> acceptGuardianInvite({
    required String token,
    required String idempotencyKey,
  });

  Future<InvitationPreview> previewInvitation({required String token});

  Future<InvitationClaimResult> claimInvitation({
    required String token,
    required String idempotencyKey,
  });
}

class UnconfiguredRosterServices implements RosterServices {
  const UnconfiguredRosterServices();

  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async => const [];

  @override
  Future<String> createPerson({
    required String clubId,
    required String teamId,
    required String displayName,
    required String ageClass,
    required DateTime startsAt,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<int> updatePerson({
    required String clubId,
    required String teamId,
    required String personId,
    required String displayName,
    required String ageClass,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<String> issueTargetedInvitation({
    required String personId,
    required String intendedEmail,
    required String token,
    required DateTime expiresAt,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<String> issueGuardianInvitation({
    required String guardianPersonId,
    required String childPersonId,
    required String token,
    required DateTime expiresAt,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<String> issueTeamCode({
    required String clubId,
    required String teamId,
    required String requestedRole,
    required String token,
    required DateTime expiresAt,
    required int maxUses,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<String> claimTeamCode({
    required String token,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<List<InvitationAdminItem>> listInvitationAdmin({
    required String clubId,
    required String teamId,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> revokeInvitation({
    required String kind,
    required String invitationId,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> endGuardianRelation({
    required String relationId,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<List<PlayEligibilitySummary>> listPlayEligibilities({
    required String clubId,
    required String teamId,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<String> createPlayEligibility({
    required String clubId,
    required String teamId,
    required String personId,
    required String kind,
    required String validityKind,
    required DateTime startsAt,
    DateTime? endsAt,
    DateTime? seasonEndsOn,
    DateTime? reviewDueAt,
    required String sourceNote,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> endPlayEligibility({
    required String eligibilityId,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<IntraClubMoveOptions> getIntraClubMoveOptions({
    required String clubId,
    required String sourceTeamId,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> movePlayerWithinClub({
    required String clubId,
    required String sourceTeamId,
    required String targetTeamId,
    required String personId,
    required String assignmentId,
    required DateTime effectiveAt,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<RosterLifecycleOptions> getRosterLifecycle({
    required String clubId,
    required String teamId,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> archiveTeamAssignment({
    required String clubId,
    required String teamId,
    required String personId,
    required String assignmentId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<String> requestClubPersonErasure({
    required String clubId,
    required String teamId,
    required String personId,
    required String reason,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> approveClubPersonErasure({
    required String requestId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<String> requestGlobalPersonErasure({
    required String reason,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<String> claim({
    required String token,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<String> acceptGuardianInvite({
    required String token,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<InvitationPreview> previewInvitation({required String token}) =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<InvitationClaimResult> claimInvitation({
    required String token,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
}

class SupabaseRosterServices implements RosterServices {
  SupabaseRosterServices(this._client);

  final SupabaseClient _client;

  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_team_overview', params: {'target_team_id': teamId});
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Team overview response is invalid.');
    }
    return TeamOverview.fromJson(value);
  }

  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_roster_person_details',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
          },
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Roster person response is invalid.');
    }
    return RosterPersonDetails.fromJson(value);
  }

  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_club_people',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! List) {
      throw const FormatException('Roster response is not a list.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(RosterPersonSummary.fromJson)
        .toList(growable: false);
  }

  @override
  Future<String> createPerson({
    required String clubId,
    required String teamId,
    required String displayName,
    required String ageClass,
    required DateTime startsAt,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'create_roster_person',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'display_name': displayName,
            'age_class': ageClass,
            'starts_at': startsAt.toUtc().toIso8601String(),
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) {
      throw const FormatException('Create roster person response is invalid.');
    }
    return value;
  }

  @override
  Future<int> updatePerson({
    required String clubId,
    required String teamId,
    required String personId,
    required String displayName,
    required String ageClass,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'update_roster_person',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
            'display_name': displayName,
            'age_class': ageClass,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Update roster person response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<String> issueTargetedInvitation({
    required String personId,
    required String intendedEmail,
    required String token,
    required DateTime expiresAt,
    required String idempotencyKey,
  }) async => _uuidRpc('issue_roster_invitation_v2', {
    'target_club_person_id': personId,
    'intended_email': intendedEmail,
    'raw_token': token,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<String> issueGuardianInvitation({
    required String guardianPersonId,
    required String childPersonId,
    required String token,
    required DateTime expiresAt,
    required String idempotencyKey,
  }) async => _uuidRpc('issue_guardian_invite', {
    'guardian_person_id': guardianPersonId,
    'child_person_id': childPersonId,
    'raw_token': token,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<String> issueTeamCode({
    required String clubId,
    required String teamId,
    required String requestedRole,
    required String token,
    required DateTime expiresAt,
    required int maxUses,
    required String idempotencyKey,
  }) async => _uuidRpc('issue_team_join_code', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'requested_role': requestedRole,
    'raw_token': token,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'max_uses': maxUses,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<String> claimTeamCode({
    required String token,
    required String idempotencyKey,
  }) async => _uuidRpc('claim_team_join_code', {
    'raw_token': token,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<List<InvitationAdminItem>> listInvitationAdmin({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_invitation_admin',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! List) {
      throw const FormatException('Invitation list response is invalid.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(InvitationAdminItem.fromJson)
        .toList(growable: false);
  }

  @override
  Future<int> revokeInvitation({
    required String kind,
    required String invitationId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'revoke_invitation',
          params: {
            'invite_kind': kind,
            'invite_id': invitationId,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Invitation revoke response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<int> endGuardianRelation({
    required String relationId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'end_guardian_relation',
          params: {
            'relation_id': relationId,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Guardian relation response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<List<PlayEligibilitySummary>> listPlayEligibilities({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_play_eligibilities',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! List) {
      throw const FormatException('Eligibility list response is invalid.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(PlayEligibilitySummary.fromJson)
        .toList(growable: false);
  }

  @override
  Future<String> createPlayEligibility({
    required String clubId,
    required String teamId,
    required String personId,
    required String kind,
    required String validityKind,
    required DateTime startsAt,
    DateTime? endsAt,
    DateTime? seasonEndsOn,
    DateTime? reviewDueAt,
    required String sourceNote,
    required String idempotencyKey,
  }) async => _uuidRpc('create_play_eligibility', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'target_club_person_id': personId,
    'eligibility_kind': kind,
    'validity_kind': validityKind,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'season_ends_on': seasonEndsOn?.toIso8601String().substring(0, 10),
    'review_due_at': reviewDueAt?.toUtc().toIso8601String(),
    'source_note': sourceNote,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<int> endPlayEligibility({
    required String eligibilityId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'end_play_eligibility',
          params: {
            'eligibility_id': eligibilityId,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Eligibility end response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<IntraClubMoveOptions> getIntraClubMoveOptions({
    required String clubId,
    required String sourceTeamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_intra_club_move_options',
          params: {
            'target_club_id': clubId,
            'target_source_team_id': sourceTeamId,
          },
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Move options response is invalid.');
    }
    return IntraClubMoveOptions.fromJson(value);
  }

  @override
  Future<void> movePlayerWithinClub({
    required String clubId,
    required String sourceTeamId,
    required String targetTeamId,
    required String personId,
    required String assignmentId,
    required DateTime effectiveAt,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'move_player_within_club',
          params: {
            'target_club_id': clubId,
            'target_source_team_id': sourceTeamId,
            'target_target_team_id': targetTeamId,
            'target_club_person_id': personId,
            'target_assignment_id': assignmentId,
            'effective_at': effectiveAt.toUtc().toIso8601String(),
            'expected_revision': expectedRevision,
            'reason': reason,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! Map<String, dynamic> ||
        value['target_assignment_id'] is! String) {
      throw const FormatException('Move response is invalid.');
    }
  }

  @override
  Future<RosterLifecycleOptions> getRosterLifecycle({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_roster_lifecycle',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Roster lifecycle response is invalid.');
    }
    return RosterLifecycleOptions.fromJson(value);
  }

  @override
  Future<int> archiveTeamAssignment({
    required String clubId,
    required String teamId,
    required String personId,
    required String assignmentId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'archive_team_assignment',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
            'target_assignment_id': assignmentId,
            'expected_revision': expectedRevision,
            'reason': reason,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Archive response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<String> requestClubPersonErasure({
    required String clubId,
    required String teamId,
    required String personId,
    required String reason,
    required String idempotencyKey,
  }) => _uuidRpc('request_club_person_erasure', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'target_club_person_id': personId,
    'reason': reason,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<int> approveClubPersonErasure({
    required String requestId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'approve_club_person_erasure',
          params: {
            'target_request_id': requestId,
            'expected_revision': expectedRevision,
            'reason': reason,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Erasure approval response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<String> requestGlobalPersonErasure({
    required String reason,
    required String idempotencyKey,
  }) => _uuidRpc('request_global_person_erasure', {
    'reason': reason,
    'idempotency_key': idempotencyKey,
  });

  Future<String> _uuidRpc(String function, Map<String, Object?> params) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(function, params: params);
    if (value is! String) {
      throw FormatException('$function response is invalid.');
    }
    return value;
  }

  @override
  Future<String> claim({
    required String token,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'claim_club_person',
          params: {'raw_token': token, 'idempotency_key': idempotencyKey},
        );
    if (value is! String) {
      throw const FormatException('Claim response is invalid.');
    }
    return value;
  }

  @override
  Future<String> acceptGuardianInvite({
    required String token,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'accept_guardian_invite',
          params: {'raw_token': token, 'idempotency_key': idempotencyKey},
        );
    if (value is! String) {
      throw const FormatException('Guardian claim response is invalid.');
    }
    return value;
  }

  @override
  Future<InvitationPreview> previewInvitation({required String token}) async {
    final response = await _client.functions.invoke(
      'invitation-preview',
      body: {'token': token},
    );
    final value = response.data;
    if (response.status != 200) {
      return const InvitationPreview(status: InvitationPreviewStatus.invalid);
    }
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invitation preview response is invalid.');
    }
    return InvitationPreview.fromJson(value);
  }

  @override
  Future<InvitationClaimResult> claimInvitation({
    required String token,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'claim_roster_invitation_v2',
          params: {'raw_token': token, 'idempotency_key': idempotencyKey},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invitation claim response is invalid.');
    }
    return InvitationClaimResult.fromJson(value);
  }
}
