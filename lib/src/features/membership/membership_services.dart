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
  Future<ClubNameCheck> checkClubName({required String name});
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
  Future<ClubNameCheck> checkClubName({required String name}) =>
      Future.error(StateError('Supabase is not configured.'));

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
    required String idempotencyKey,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'decide_membership_application',
          params: {
            'application_id': applicationId,
            'decision': approve ? 'approved' : 'rejected',
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
