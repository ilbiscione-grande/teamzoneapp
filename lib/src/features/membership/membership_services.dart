import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/membership/membership_models.dart';

abstract interface class MembershipServices {
  Future<List<ClubTeamSearchResult>> search({required String query});
  Future<List<MembershipApplication>> listMine();
  Future<String> apply({
    required String teamId,
    required MembershipRole role,
    required String idempotencyKey,
  });
  Future<void> withdraw({
    required String applicationId,
    required String idempotencyKey,
  });
  Future<List<MembershipReviewItem>> listPendingReviews({
    required String clubId,
    String? teamId,
  });
  Future<void> decide({
    required String applicationId,
    required bool approve,
    MembershipRole? approvedRole,
    required String idempotencyKey,
  });
  Future<ClubCreationResult> createClubWithFirstTeam({
    required String clubName,
    required String teamName,
    required String idempotencyKey,
  });
  Future<String> createTeam({
    required String clubId,
    required String teamName,
    required String idempotencyKey,
  });
  Future<String> requestTeamCreation({
    required String clubId,
    required String sourceAssignmentId,
    required String teamName,
    required String idempotencyKey,
  });
  Future<List<TeamCreationRequest>> listTeamCreationRequests({
    required String clubId,
  });
  Future<void> decideTeamCreationRequest({
    required String requestId,
    required bool approve,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<ClubNameCheck> checkClubName({required String name});
  Future<String> submitProtectedNameSupportCase({
    required String clubName,
    required String teamName,
    required String message,
    required String idempotencyKey,
  });
  Future<bool> isSupportAdmin();
  Future<List<ProtectedNameSupportCase>> listProtectedNameSupportCases({
    String? status,
  });
  Future<int> updateProtectedNameSupportCase({
    required String caseId,
    required String status,
    required String resolutionNote,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<List<GlobalPersonErasureCase>> listGlobalPersonErasureCases();
  Future<String> decideGlobalPersonErasure({
    required String requestId,
    required bool approve,
    required String reason,
  });
  Future<String> requestClubVerification({
    required String clubId,
    required String evidenceSummary,
    required String idempotencyKey,
  });
  Future<ClubVerificationStatus> getClubVerificationStatus({
    required String clubId,
  });
}

class UnconfiguredMembershipServices implements MembershipServices {
  const UnconfiguredMembershipServices();

  @override
  Future<List<ClubTeamSearchResult>> search({required String query}) async =>
      const [];

  @override
  Future<List<MembershipApplication>> listMine() async => const [];

  @override
  Future<String> apply({
    required String teamId,
    required MembershipRole role,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<void> withdraw({
    required String applicationId,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<List<MembershipReviewItem>> listPendingReviews({
    required String clubId,
    String? teamId,
  }) async => const [];

  @override
  Future<void> decide({
    required String applicationId,
    required bool approve,
    MembershipRole? approvedRole,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<ClubCreationResult> createClubWithFirstTeam({
    required String clubName,
    required String teamName,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<String> createTeam({
    required String clubId,
    required String teamName,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<String> requestTeamCreation({
    required String clubId,
    required String sourceAssignmentId,
    required String teamName,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<List<TeamCreationRequest>> listTeamCreationRequests({
    required String clubId,
  }) async => const [];
  @override
  Future<void> decideTeamCreationRequest({
    required String requestId,
    required bool approve,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<ClubNameCheck> checkClubName({required String name}) =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<String> submitProtectedNameSupportCase({
    required String clubName,
    required String teamName,
    required String message,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<bool> isSupportAdmin() async => false;

  @override
  Future<List<ProtectedNameSupportCase>> listProtectedNameSupportCases({
    String? status,
  }) async => const [];

  @override
  Future<int> updateProtectedNameSupportCase({
    required String caseId,
    required String status,
    required String resolutionNote,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<List<GlobalPersonErasureCase>> listGlobalPersonErasureCases() async =>
      const [];

  @override
  Future<String> decideGlobalPersonErasure({
    required String requestId,
    required bool approve,
    required String reason,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<String> requestClubVerification({
    required String clubId,
    required String evidenceSummary,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<ClubVerificationStatus> getClubVerificationStatus({
    required String clubId,
  }) => Future.error(StateError('Supabase is not configured.'));
}

class SupabaseMembershipServices implements MembershipServices {
  const SupabaseMembershipServices(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ClubTeamSearchResult>> search({required String query}) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'search_joinable_club_teams',
          params: {'search_query': query},
        );
    if (value is! List) throw const FormatException('Invalid search response.');
    return value
        .whereType<Map<String, dynamic>>()
        .map(ClubTeamSearchResult.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<MembershipApplication>> listMine() async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('list_my_membership_applications');
    if (value is! List) {
      throw const FormatException('Invalid application list.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(MembershipApplication.fromJson)
        .toList(growable: false);
  }

  @override
  Future<String> apply({
    required String teamId,
    required MembershipRole role,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'request_team_membership',
          params: {
            'target_team_id': teamId,
            'requested_role': role.wireName,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) {
      throw const FormatException('Invalid application response.');
    }
    return value;
  }

  @override
  Future<void> withdraw({
    required String applicationId,
    required String idempotencyKey,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'withdraw_membership_application',
          params: {
            'application_id': applicationId,
            'idempotency_key': idempotencyKey,
          },
        );
  }

  @override
  Future<List<MembershipReviewItem>> listPendingReviews({
    required String clubId,
    String? teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_pending_membership_applications',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! List) {
      throw const FormatException('Invalid review queue.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(MembershipReviewItem.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> decide({
    required String applicationId,
    required bool approve,
    MembershipRole? approvedRole,
    required String idempotencyKey,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'decide_membership_application_v2',
          params: {
            'application_id': applicationId,
            'decision': approve ? 'approved' : 'rejected',
            'approved_role': approve ? approvedRole?.wireName : null,
            'idempotency_key': idempotencyKey,
          },
        );
  }

  @override
  Future<ClubCreationResult> createClubWithFirstTeam({
    required String clubName,
    required String teamName,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'create_club_with_first_team',
          params: {
            'club_name': clubName,
            'team_name': teamName,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid club creation response.');
    }
    return ClubCreationResult.fromJson(value);
  }

  @override
  Future<String> createTeam({
    required String clubId,
    required String teamName,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'create_team_in_club',
          params: {
            'target_club_id': clubId,
            'team_name': teamName,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) throw const FormatException('Invalid team response.');
    return value;
  }

  @override
  Future<String> requestTeamCreation({
    required String clubId,
    required String sourceAssignmentId,
    required String teamName,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'request_team_creation',
          params: {
            'target_club_id': clubId,
            'source_assignment_id': sourceAssignmentId,
            'team_name': teamName,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) {
      throw const FormatException('Invalid request response.');
    }
    return value;
  }

  @override
  Future<List<TeamCreationRequest>> listTeamCreationRequests({
    required String clubId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_team_creation_requests',
          params: {'target_club_id': clubId},
        );
    if (value is! List) throw const FormatException('Invalid request list.');
    return value
        .whereType<Map<String, dynamic>>()
        .map(TeamCreationRequest.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> decideTeamCreationRequest({
    required String requestId,
    required bool approve,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'decide_team_creation_request',
          params: {
            'request_id': requestId,
            'decision': approve ? 'approved' : 'rejected',
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
  }

  @override
  Future<ClubNameCheck> checkClubName({required String name}) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('check_club_name', params: {'candidate_name': name});
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid club name check.');
    }
    return ClubNameCheck.fromJson(value);
  }

  @override
  Future<String> submitProtectedNameSupportCase({
    required String clubName,
    required String teamName,
    required String message,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'submit_protected_name_support_case',
          params: {
            'candidate_club_name': clubName,
            'candidate_team_name': teamName,
            'message': message,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) {
      throw const FormatException('Invalid support case response.');
    }
    return value;
  }

  @override
  Future<bool> isSupportAdmin() async {
    final value = await _client.schema('api').rpc<Object?>('is_support_admin');
    return value == true;
  }

  @override
  Future<List<ProtectedNameSupportCase>> listProtectedNameSupportCases({
    String? status,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_protected_name_support_cases',
          params: {'requested_status': status},
        );
    if (value is! List) throw const FormatException('Invalid support queue.');
    return value
        .whereType<Map<String, dynamic>>()
        .map(ProtectedNameSupportCase.fromJson)
        .toList(growable: false);
  }

  @override
  Future<int> updateProtectedNameSupportCase({
    required String caseId,
    required String status,
    required String resolutionNote,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'update_protected_name_support_case',
          params: {
            'target_case_id': caseId,
            'new_status': status,
            'case_resolution_note': resolutionNote,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) throw const FormatException('Invalid support update.');
    return value.toInt();
  }

  @override
  Future<List<GlobalPersonErasureCase>> listGlobalPersonErasureCases() async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('list_global_person_erasure_cases');
    if (value is! List) {
      throw const FormatException('Invalid person erasure queue.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(GlobalPersonErasureCase.fromJson)
        .toList(growable: false);
  }

  @override
  Future<String> decideGlobalPersonErasure({
    required String requestId,
    required bool approve,
    required String reason,
  }) async {
    final response = await _client.functions.invoke(
      'person-erasure-worker',
      body: {
        'requestId': requestId,
        'decision': approve ? 'approved' : 'rejected',
        'reason': reason,
      },
    );
    final value = response.data;
    if (response.status != 200 || value is! Map || value['state'] is! String) {
      throw StateError('Person erasure decision failed.');
    }
    return value['state']! as String;
  }

  @override
  Future<String> requestClubVerification({
    required String clubId,
    required String evidenceSummary,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'request_club_verification',
          params: {
            'target_club_id': clubId,
            'evidence_summary': evidenceSummary,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) {
      throw const FormatException('Invalid verification request.');
    }
    return value;
  }

  @override
  Future<ClubVerificationStatus> getClubVerificationStatus({
    required String clubId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_club_verification_status',
          params: {'target_club_id': clubId},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid verification status.');
    }
    return ClubVerificationStatus.fromJson(value);
  }
}
