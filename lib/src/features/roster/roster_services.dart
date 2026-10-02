import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';

abstract interface class RosterServices {
  /// Replaces a leader's panel capabilities. [expected] is the set the
  /// caller saw; a different current set fails as stale. [template] records
  /// which template (or 'custom') the set came from.
  Future<void> setLeaderPermissions({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> capabilities,
    required List<String> expected,
    String? template,
    required String idempotencyKey,
  });

  /// Sets the team's sport, which selects its position catalog.
  Future<void> setTeamSport({
    required String clubId,
    required String teamId,
    required String sport,
    required String idempotencyKey,
  });
  Future<int> setTeamPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> titles,
    required List<String> positions,
    required List<String> customTitles,
    required List<String> customPositions,
    String? mainPosition,
    String? mainTitle,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<TeamOverview> getTeamOverview({required String teamId});

  /// Sign-up forms and the details sent through them (TEAM-15).
  Future<IntakeOverview> getIntakeOverview({required String clubId});

  /// The active contact page for the club (team null) or a team; a new one
  /// is valid for 14 days.
  Future<IntakeFormLink> createIntakeForm({
    required String clubId,
    String? teamId,
  });
  Future<void> closeIntakeForm({required String formId});

  /// Adds the person to the team as player or leader; returns their id.
  Future<String> acceptIntakeSubmission({
    required String submissionId,
    required String teamId,
    required String role,
    required String idempotencyKey,
  });
  Future<void> dismissIntakeSubmission({required String submissionId});

  /// Puts the sent phone, email and address on an existing person in the
  /// team instead of creating a new one.
  Future<void> updatePersonFromIntake({
    required String submissionId,
    required String teamId,
    required String personId,
  });
  Future<TeamProfileEditData> getTeamProfileEdit({required String teamId});
  Future<String> uploadTeamImage({
    required String teamId,
    required String mimeType,
    required Uint8List bytes,
    required String idempotencyKey,
  });
  Future<int> updateTeamProfile({
    required String teamId,
    required String teamType,
    required String ageClass,
    required String summary,
    required String imageAction,
    String? stagedImageId,
    required int expectedRevision,
    required String idempotencyKey,
  });
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
    required int birthYear,
    DateTime? birthDate,
    required DateTime startsAt,
    required String idempotencyKey,
  });
  Future<int> updatePerson({
    required String clubId,
    required String teamId,
    required String personId,
    required String displayName,
    required int birthYear,
    DateTime? birthDate,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<int> setGuardianRequirement({
    required String clubId,
    required String teamId,
    required String personId,
    required bool guardianRequired,
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
  Future<String> revealTeamCode({required String codeId});
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
  Future<List<RosterPersonSummary>> listPlayEligibilityCandidates({
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
  Future<int> setRepresentationAvailable({
    required String clubId,
    required String teamId,
    required String personId,
    required bool available,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<int> decidePlayEligibility({
    required String eligibilityId,
    required bool approve,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<PersonAttendanceSummary> getPersonAttendanceSummary({
    required String clubId,
    required String teamId,
    required String personId,
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
  Future<String> restoreArchivedTeamAssignment({
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
  Future<TeamRoles> listTeamRoles({
    required String clubId,
    required String teamId,
  });
  Future<List<LeaderCandidate>> listLeaderCandidates({
    required String clubId,
    required String teamId,
  });

  /// Adds, changes or removes a player/leader role. Pass [fromRole] null to
  /// add and [toRole] null to remove. Idempotent per [idempotencyKey].
  Future<void> setTeamRole({
    required String clubId,
    required String teamId,
    required String personId,
    String? fromRole,
    String? toRole,
    required String idempotencyKey,
  });
}

class UnconfiguredRosterServices implements RosterServices {
  @override
  Future<IntakeOverview> getIntakeOverview({required String clubId}) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<IntakeFormLink> createIntakeForm({
    required String clubId,
    String? teamId,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> closeIntakeForm({required String formId}) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<String> acceptIntakeSubmission({
    required String submissionId,
    required String teamId,
    required String role,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> dismissIntakeSubmission({required String submissionId}) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> updatePersonFromIntake({
    required String submissionId,
    required String teamId,
    required String personId,
  }) => Future.error(StateError('Supabase is not configured.'));

  const UnconfiguredRosterServices();

  @override
  Future<void> setLeaderPermissions({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> capabilities,
    required List<String> expected,
    String? template,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<void> setTeamSport({
    required String clubId,
    required String teamId,
    required String sport,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<int> setTeamPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> titles,
    required List<String> positions,
    required List<String> customTitles,
    required List<String> customPositions,
    String? mainPosition,
    String? mainTitle,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<TeamRoles> listTeamRoles({
    required String clubId,
    required String teamId,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<List<LeaderCandidate>> listLeaderCandidates({
    required String clubId,
    required String teamId,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<void> setTeamRole({
    required String clubId,
    required String teamId,
    required String personId,
    String? fromRole,
    String? toRole,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<TeamProfileEditData> getTeamProfileEdit({required String teamId}) =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<String> uploadTeamImage({
    required String teamId,
    required String mimeType,
    required Uint8List bytes,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<int> updateTeamProfile({
    required String teamId,
    required String teamType,
    required String ageClass,
    required String summary,
    required String imageAction,
    String? stagedImageId,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

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
    required int birthYear,
    DateTime? birthDate,
    required DateTime startsAt,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<int> updatePerson({
    required String clubId,
    required String teamId,
    required String personId,
    required String displayName,
    required int birthYear,
    DateTime? birthDate,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> setGuardianRequirement({
    required String clubId,
    required String teamId,
    required String personId,
    required bool guardianRequired,
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
  Future<String> revealTeamCode({required String codeId}) =>
      Future.error(StateError('Supabase is not configured.'));
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
  Future<List<RosterPersonSummary>> listPlayEligibilityCandidates({
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
  Future<int> setRepresentationAvailable({
    required String clubId,
    required String teamId,
    required String personId,
    required bool available,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> decidePlayEligibility({
    required String eligibilityId,
    required bool approve,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<PersonAttendanceSummary> getPersonAttendanceSummary({
    required String clubId,
    required String teamId,
    required String personId,
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
  Future<String> restoreArchivedTeamAssignment({
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
  @override
  Future<IntakeOverview> getIntakeOverview({required String clubId}) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_intake_overview', params: {'target_club_id': clubId});
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Intake overview is invalid.');
    }
    return IntakeOverview.fromJson(value);
  }

  @override
  Future<IntakeFormLink> createIntakeForm({
    required String clubId,
    String? teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'create_intake_form',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Contact page is invalid.');
    }
    return IntakeFormLink(
      id: value['id'] as String,
      token: value['token'] as String,
      expiresAt: DateTime.parse(value['expires_at'] as String),
      teamId: teamId,
    );
  }

  @override
  Future<void> closeIntakeForm({required String formId}) async {
    await _client
        .schema('api')
        .rpc<Object?>('close_intake_form', params: {'target_form_id': formId});
  }

  @override
  Future<String> acceptIntakeSubmission({
    required String submissionId,
    required String teamId,
    required String role,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'accept_intake_submission',
          params: {
            'target_submission_id': submissionId,
            'target_team_id': teamId,
            'new_role': role,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) {
      throw const FormatException('Intake acceptance is invalid.');
    }
    return value;
  }

  @override
  Future<void> updatePersonFromIntake({
    required String submissionId,
    required String teamId,
    required String personId,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'update_person_from_intake',
          params: {
            'target_submission_id': submissionId,
            'target_team_id': teamId,
            'target_person_id': personId,
          },
        );
  }

  @override
  Future<void> dismissIntakeSubmission({required String submissionId}) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'dismiss_intake_submission',
          params: {'target_submission_id': submissionId},
        );
  }

  SupabaseRosterServices(this._client);

  @override
  Future<void> setLeaderPermissions({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> capabilities,
    required List<String> expected,
    String? template,
    required String idempotencyKey,
  }) async {
    try {
      await _client
          .schema('api')
          .rpc<Object?>(
            'set_leader_permissions',
            params: {
              'target_club_id': clubId,
              'target_team_id': teamId,
              'target_person_id': personId,
              'new_capabilities': capabilities,
              'expected_capabilities': expected,
              'template': template,
              'idempotency_key': idempotencyKey,
            },
          );
    } on PostgrestException catch (error) {
      const known = {
        'own_leaders_permission',
        'not_grantable',
        'stale_permissions',
        'last_leaders_manager',
      };
      if (known.contains(error.message)) {
        throw TeamRoleException(error.message);
      }
      rethrow;
    }
  }

  @override
  Future<void> setTeamSport({
    required String clubId,
    required String teamId,
    required String sport,
    required String idempotencyKey,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'set_team_sport',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'new_sport': sport,
            'idempotency_key': idempotencyKey,
          },
        );
  }

  @override
  Future<int> setTeamPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
    required List<String> titles,
    required List<String> positions,
    required List<String> customTitles,
    required List<String> customPositions,
    String? mainPosition,
    String? mainTitle,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final result = await _client
        .schema('api')
        .rpc<Object?>(
          'set_team_person_details_v4',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_person_id': personId,
            'new_titles': titles,
            'new_positions': positions,
            'new_custom_titles': customTitles,
            'new_custom_positions': customPositions,
            'new_main_position': mainPosition,
            'new_main_title': mainTitle,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    return (result as num).toInt();
  }

  final SupabaseClient _client;

  @override
  Future<TeamRoles> listTeamRoles({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_team_roles',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! Map) throw const FormatException('Invalid team roles.');
    return TeamRoles.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<List<LeaderCandidate>> listLeaderCandidates({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_club_leader_candidates',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    return (value as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LeaderCandidate.fromJson)
        .toList();
  }

  @override
  Future<void> setTeamRole({
    required String clubId,
    required String teamId,
    required String personId,
    String? fromRole,
    String? toRole,
    required String idempotencyKey,
  }) async {
    final (name, params) = switch ((fromRole, toRole)) {
      (null, final String to) => ('add_team_role', {'role': to}),
      (final String from, null) => ('remove_team_role', {'role': from}),
      (final String from, final String to) => (
        'change_team_role',
        {'from_role': from, 'to_role': to},
      ),
      _ => throw ArgumentError('A role change needs a from or to role.'),
    };
    try {
      await _client
          .schema('api')
          .rpc<Object?>(
            name,
            params: {
              'target_club_id': clubId,
              'target_team_id': teamId,
              'target_person_id': personId,
              ...params,
              'idempotency_key': idempotencyKey,
            },
          );
    } on PostgrestException catch (error) {
      const known = {'own_leader_role', 'home_in_other_team', 'stale_role'};
      if (known.contains(error.message)) {
        throw TeamRoleException(error.message);
      }
      rethrow;
    }
  }

  @override
  Future<TeamOverview> getTeamOverview({required String teamId}) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_team_overview', params: {'target_team_id': teamId});
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Team overview response is invalid.');
    }
    final json = Map<String, dynamic>.from(value);
    await _resolveTeamImage(json);
    return TeamOverview.fromJson(json);
  }

  @override
  Future<TeamProfileEditData> getTeamProfileEdit({
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_team_profile_edit',
          params: {'target_team_id': teamId},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Team profile response is invalid.');
    }
    final json = Map<String, dynamic>.from(value);
    await _resolveTeamImage(json);
    return TeamProfileEditData.fromJson(json);
  }

  Future<void> _resolveTeamImage(Map<String, dynamic> json) async {
    final assetId = json['image_asset_id'];
    if (assetId is! String || assetId.isEmpty) return;
    final authorization = await _client
        .schema('api')
        .rpc<Object?>(
          'authorize_team_profile_image',
          params: {'target_image_id': assetId},
        )
        .timeout(const Duration(seconds: 15));
    if (authorization is! Map ||
        authorization['bucket_id'] != 'team-profile-images' ||
        authorization['object_key'] is! String ||
        authorization['expires_in_seconds'] != 3600) {
      throw const FormatException('Invalid team image authorization.');
    }
    json['image_url'] = await _client.storage
        .from(authorization['bucket_id']! as String)
        .createSignedUrl(authorization['object_key']! as String, 3600)
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<String> uploadTeamImage({
    required String teamId,
    required String mimeType,
    required Uint8List bytes,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'stage_team_profile_image',
          params: {
            'target_team_id': teamId,
            'target_mime_type': mimeType,
            'target_size_bytes': bytes.length,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid staged team image response.');
    }
    final staged = StagedTeamImage.fromJson(value);
    if (staged.bucketId != 'team-profile-images') {
      throw const FormatException('Unexpected team image bucket.');
    }
    await _client.storage
        .from(staged.bucketId)
        .uploadBinary(
          staged.objectKey,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return staged.imageId;
  }

  @override
  Future<int> updateTeamProfile({
    required String teamId,
    required String teamType,
    required String ageClass,
    required String summary,
    required String imageAction,
    String? stagedImageId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'update_team_profile_v2',
          params: {
            'target_team_id': teamId,
            'new_team_type': teamType,
            'new_age_class': ageClass,
            'new_summary': summary,
            'image_action': imageAction,
            'staged_image_id': stagedImageId,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) throw const FormatException('Invalid team revision.');
    return value.toInt();
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
          'get_roster_person_details_v3',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
          },
        );
    if (value is! Map) {
      throw const FormatException('Roster person response is invalid.');
    }
    return RosterPersonDetails.fromJson(Map<String, dynamic>.from(value));
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
    required int birthYear,
    DateTime? birthDate,
    required DateTime startsAt,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'create_roster_person_v3',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'display_name': displayName,
            'birth_year': birthYear,
            'birth_date': birthDate == null ? null : _dateOnly(birthDate),
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
    required int birthYear,
    DateTime? birthDate,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'update_roster_person_v3',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
            'display_name': displayName,
            'birth_year': birthYear,
            'birth_date': birthDate == null ? null : _dateOnly(birthDate),
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
  Future<int> setGuardianRequirement({
    required String clubId,
    required String teamId,
    required String personId,
    required bool guardianRequired,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'set_guardian_requirement',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
            'guardian_required': guardianRequired,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Guardian requirement response is invalid.');
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
  Future<String> revealTeamCode({required String codeId}) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('reveal_team_join_code', params: {'code_id': codeId});
    if (value is! String || value.length < 32) {
      throw const FormatException('Team code response is invalid.');
    }
    return value;
  }

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
  Future<List<RosterPersonSummary>> listPlayEligibilityCandidates({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_play_eligibility_candidates',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! List) {
      throw const FormatException(
        'Eligibility candidates response is invalid.',
      );
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(RosterPersonSummary.fromJson)
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
  Future<int> setRepresentationAvailable({
    required String clubId,
    required String teamId,
    required String personId,
    required bool available,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'set_representation_available',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
            'available': available,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException(
        'Representation availability response is invalid.',
      );
    }
    return value.toInt();
  }

  @override
  Future<int> decidePlayEligibility({
    required String eligibilityId,
    required bool approve,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'decide_play_eligibility',
          params: {
            'target_eligibility_id': eligibilityId,
            'approve': approve,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Eligibility decision response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<PersonAttendanceSummary> getPersonAttendanceSummary({
    required String clubId,
    required String teamId,
    required String personId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_person_attendance_summary',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
          },
        );
    final row = value is List ? value.firstOrNull : value;
    if (row is! Map<String, dynamic>) {
      throw const FormatException('Attendance summary response is invalid.');
    }
    return PersonAttendanceSummary.fromJson(row);
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
    if (value is! Map || value['target_assignment_id'] is! String) {
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
  Future<String> restoreArchivedTeamAssignment({
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
          'restore_archived_team_assignment',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'target_club_person_id': personId,
            'archived_assignment_id': assignmentId,
            'expected_revision': expectedRevision,
            'reason': reason,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) {
      throw const FormatException('Invalid restore response.');
    }
    return value;
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
    final revision = switch (value) {
      final num number => number.toInt(),
      final String text => int.tryParse(text),
      _ => null,
    };
    if (revision == null) {
      throw const FormatException('Erasure approval response is invalid.');
    }
    return revision;
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

String _dateOnly(DateTime value) {
  final date = value.toLocal();
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
