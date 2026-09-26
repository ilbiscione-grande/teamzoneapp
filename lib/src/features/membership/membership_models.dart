enum MembershipRole { player, leader, guardian, clubFunctionary }

class ProtectedNameSupportCase {
  const ProtectedNameSupportCase({
    required this.id,
    required this.requesterProfileId,
    required this.clubName,
    required this.teamName,
    required this.status,
    required this.message,
    required this.resolutionNote,
    required this.revision,
    required this.createdAt,
  });

  final String id;
  final String requesterProfileId;
  final String clubName;
  final String teamName;
  final String status;
  final String message;
  final String? resolutionNote;
  final int revision;
  final DateTime createdAt;

  factory ProtectedNameSupportCase.fromJson(Map<String, dynamic> json) =>
      ProtectedNameSupportCase(
        id: json['case_id'] as String,
        requesterProfileId: json['requester_profile_id'] as String,
        clubName: json['candidate_club_name'] as String,
        teamName: json['candidate_team_name'] as String,
        status: json['status'] as String,
        message: json['message'] as String,
        resolutionNote: json['resolution_note'] as String?,
        revision: (json['revision'] as num).toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class GlobalPersonErasureCase {
  const GlobalPersonErasureCase({
    required this.id,
    required this.requesterName,
    required this.state,
    required this.reason,
    required this.requestedAt,
    required this.reviewedAt,
    required this.completedAt,
    required this.revision,
  });

  final String id;
  final String requesterName;
  final String state;
  final String reason;
  final DateTime requestedAt;
  final DateTime? reviewedAt;
  final DateTime? completedAt;
  final int revision;

  factory GlobalPersonErasureCase.fromJson(Map<String, dynamic> json) =>
      GlobalPersonErasureCase(
        id: json['request_id'] as String,
        requesterName: json['requester_name'] as String,
        state: json['state'] as String,
        reason: json['reason'] as String,
        requestedAt: DateTime.parse(json['requested_at'] as String),
        reviewedAt: json['reviewed_at'] == null
            ? null
            : DateTime.parse(json['reviewed_at'] as String),
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.parse(json['completed_at'] as String),
        revision: (json['revision'] as num).toInt(),
      );
}

extension MembershipRoleWire on MembershipRole {
  String get wireName => switch (this) {
    MembershipRole.player => 'player',
    MembershipRole.leader => 'leader',
    MembershipRole.guardian => 'guardian',
    MembershipRole.clubFunctionary => 'club_functionary',
  };
}

class ClubTeamSearchResult {
  const ClubTeamSearchResult({
    required this.clubId,
    required this.clubName,
    required this.clubIsOfficial,
    required this.teamId,
    required this.teamName,
  });

  final String clubId, clubName, teamId, teamName;
  final bool clubIsOfficial;

  factory ClubTeamSearchResult.fromJson(Map<String, dynamic> json) =>
      ClubTeamSearchResult(
        clubId: json['club_id'] as String,
        clubName: json['club_name'] as String,
        clubIsOfficial: json['club_is_official'] as bool? ?? false,
        teamId: json['team_id'] as String,
        teamName: json['team_name'] as String,
      );
}

enum MembershipApplicationStatus { pending, approved, rejected, withdrawn }

class MembershipApplication {
  const MembershipApplication({
    required this.id,
    required this.clubName,
    required this.teamName,
    required this.role,
    required this.status,
    required this.createdAt,
  });

  final String id, clubName, teamName;
  final MembershipRole role;
  final MembershipApplicationStatus status;
  final DateTime createdAt;

  factory MembershipApplication.fromJson(Map<String, dynamic> json) =>
      MembershipApplication(
        id: json['application_id'] as String,
        clubName: json['club_name'] as String,
        teamName: json['team_name'] as String,
        role: MembershipRole.values.firstWhere(
          (role) => role.wireName == json['requested_role'],
        ),
        status: MembershipApplicationStatus.values.firstWhere(
          (status) => status.name == json['status'],
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class MembershipReviewItem {
  const MembershipReviewItem({
    required this.id,
    required this.applicantDisplayName,
    required this.teamName,
    required this.role,
    required this.createdAt,
  });

  final String id, applicantDisplayName, teamName;
  final MembershipRole role;
  final DateTime createdAt;

  factory MembershipReviewItem.fromJson(Map<String, dynamic> json) =>
      MembershipReviewItem(
        id: json['application_id'] as String,
        applicantDisplayName: json['applicant_display_name'] as String,
        teamName: json['team_name'] as String,
        role: MembershipRole.values.firstWhere(
          (role) => role.wireName == json['requested_role'],
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ClubCreationResult {
  const ClubCreationResult({
    required this.clubId,
    required this.teamId,
    required this.contextId,
  });

  final String clubId, teamId, contextId;

  factory ClubCreationResult.fromJson(Map<String, dynamic> json) =>
      ClubCreationResult(
        clubId: json['club_id'] as String,
        teamId: json['team_id'] as String,
        contextId: json['context_id'] as String,
      );
}

class TeamCreationRequest {
  const TeamCreationRequest({
    required this.id,
    required this.teamName,
    required this.requesterName,
    required this.state,
    required this.revision,
  });
  final String id, teamName, requesterName, state;
  final int revision;
  factory TeamCreationRequest.fromJson(Map<String, dynamic> json) =>
      TeamCreationRequest(
        id: json['request_id'] as String,
        teamName: json['team_name'] as String,
        requesterName: json['requester_name'] as String,
        state: json['state'] as String,
        revision: (json['revision'] as num).toInt(),
      );
}

enum ClubNameCheckStatus { available, reviewRequired, invalid }

class ClubNameCheck {
  const ClubNameCheck(this.status);
  final ClubNameCheckStatus status;

  factory ClubNameCheck.fromJson(Map<String, dynamic> json) =>
      ClubNameCheck(switch (json['status']) {
        'available' => ClubNameCheckStatus.available,
        'review_required' => ClubNameCheckStatus.reviewRequired,
        _ => ClubNameCheckStatus.invalid,
      });
}

class ClubVerificationStatus {
  const ClubVerificationStatus({
    required this.clubId,
    required this.status,
    this.requestedAt,
    this.resolvedAt,
  });

  final String clubId, status;
  final DateTime? requestedAt, resolvedAt;

  factory ClubVerificationStatus.fromJson(Map<String, dynamic> json) =>
      ClubVerificationStatus(
        clubId: json['club_id'] as String,
        status: json['status'] as String,
        requestedAt: DateTime.tryParse(json['requested_at'] as String? ?? ''),
        resolvedAt: DateTime.tryParse(json['resolved_at'] as String? ?? ''),
      );
}
