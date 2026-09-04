class RosterPersonSummary {
  const RosterPersonSummary({
    required this.id,
    required this.displayName,
    required this.safeguardingRequired,
    this.ageClass,
    this.teamId,
    this.teamName,
    this.assignmentState,
  });

  final String id;
  final String displayName;
  final String? ageClass;
  final bool safeguardingRequired;
  final String? teamId;
  final String? teamName;
  final String? assignmentState;

  factory RosterPersonSummary.fromJson(Map<String, dynamic> json) {
    return RosterPersonSummary(
      id: json['club_person_id'] as String,
      displayName: json['display_name'] as String,
      ageClass: json['age_class'] as String?,
      safeguardingRequired: json['safeguarding_required'] as bool? ?? false,
      teamId: json['team_id'] as String?,
      teamName: json['team_name'] as String?,
      assignmentState: json['assignment_state'] as String?,
    );
  }
}

class TeamLeaderSummary {
  const TeamLeaderSummary({required this.personId, required this.displayName});
  final String personId, displayName;
  factory TeamLeaderSummary.fromJson(Map<String, dynamic> json) =>
      TeamLeaderSummary(
        personId: json['person_id'] as String,
        displayName: json['display_name'] as String,
      );
}

class TeamOverview {
  const TeamOverview({
    required this.teamId,
    required this.clubId,
    required this.teamName,
    required this.clubName,
    required this.leaders,
    required this.memberCount,
    required this.canManage,
    required this.activeInvitationCount,
    required this.pendingApplicationCount,
    this.teamType,
    this.ageClass,
    this.summary,
    this.imageUrl,
  });

  final String teamId, clubId, teamName, clubName;
  final String? teamType, ageClass, summary, imageUrl;
  final List<TeamLeaderSummary> leaders;
  final int memberCount, activeInvitationCount, pendingApplicationCount;
  final bool canManage;
  int get actionCount => activeInvitationCount + pendingApplicationCount;

  factory TeamOverview.fromJson(Map<String, dynamic> json) => TeamOverview(
    teamId: json['team_id'] as String,
    clubId: json['club_id'] as String,
    teamName: json['team_name'] as String,
    clubName: json['club_name'] as String,
    teamType: json['team_type'] as String?,
    ageClass: json['age_class'] as String?,
    summary: json['summary'] as String?,
    imageUrl: json['image_url'] as String?,
    leaders: (json['leaders'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TeamLeaderSummary.fromJson)
        .toList(growable: false),
    memberCount: (json['member_count'] as num? ?? 0).toInt(),
    canManage: json['can_manage'] as bool? ?? false,
    activeInvitationCount: (json['active_invitation_count'] as num? ?? 0)
        .toInt(),
    pendingApplicationCount: (json['pending_application_count'] as num? ?? 0)
        .toInt(),
  );
}

class TeamProfileEditData {
  const TeamProfileEditData({
    required this.teamId,
    required this.revision,
    this.teamType,
    this.ageClass,
    this.summary,
    this.imageUrl,
  });

  final String teamId;
  final int revision;
  final String? teamType, ageClass, summary, imageUrl;

  factory TeamProfileEditData.fromJson(Map<String, dynamic> json) =>
      TeamProfileEditData(
        teamId: json['team_id'] as String,
        revision: (json['revision'] as num? ?? 0).toInt(),
        teamType: json['team_type'] as String?,
        ageClass: json['age_class'] as String?,
        summary: json['summary'] as String?,
        imageUrl: json['image_url'] as String?,
      );
}

class RosterPersonDetails {
  const RosterPersonDetails({
    required this.id,
    required this.displayName,
    required this.teamId,
    required this.teamName,
    required this.assignmentState,
    this.ageClass,
    this.safeguardingRequired,
    this.provenance,
    this.assignmentStartsAt,
    this.assignmentEndsAt,
    this.assignmentRevision,
    this.personRevision,
  });
  final String id, displayName, teamId, teamName, assignmentState;
  final String? ageClass, provenance;
  final bool? safeguardingRequired;
  final DateTime? assignmentStartsAt, assignmentEndsAt;
  final int? assignmentRevision;
  final int? personRevision;

  bool get hasManagementDetails => provenance != null;

  factory RosterPersonDetails.fromJson(Map<String, dynamic> json) {
    final management = json['management'];
    final manager = management is Map<String, dynamic> ? management : null;
    return RosterPersonDetails(
      id: json['club_person_id'] as String,
      displayName: json['display_name'] as String,
      teamId: json['team_id'] as String,
      teamName: json['team_name'] as String,
      assignmentState: json['assignment_state'] as String,
      ageClass: json['age_class'] as String?,
      safeguardingRequired: json['safeguarding_required'] as bool?,
      provenance: manager?['provenance'] as String?,
      assignmentStartsAt: DateTime.tryParse(
        manager?['assignment_starts_at'] as String? ?? '',
      ),
      assignmentEndsAt: DateTime.tryParse(
        manager?['assignment_ends_at'] as String? ?? '',
      ),
      assignmentRevision: (manager?['assignment_revision'] as num?)?.toInt(),
      personRevision: (json['person_revision'] as num?)?.toInt(),
    );
  }
}

class InvitationAdminItem {
  const InvitationAdminItem({
    required this.id,
    required this.kind,
    required this.subjectName,
    required this.state,
    this.expiresAt,
    required this.revision,
  });
  final String id, kind, subjectName, state;
  final DateTime? expiresAt;
  final int revision;
  bool get canRevoke =>
      kind != 'guardian_relation' &&
      state == 'issued' &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());
  bool get canEndRelation => kind == 'guardian_relation' && state == 'active';

  factory InvitationAdminItem.fromJson(Map<String, dynamic> json) =>
      InvitationAdminItem(
        id: json['invite_id'] as String,
        kind: json['invite_kind'] as String,
        subjectName: json['subject_name'] as String,
        state: json['state'] as String,
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        revision: (json['revision'] as num).toInt(),
      );
}

class PlayEligibilitySummary {
  const PlayEligibilitySummary({
    required this.id,
    required this.personId,
    required this.personName,
    required this.targetTeamId,
    required this.targetTeamName,
    required this.kind,
    required this.validityKind,
    required this.state,
    required this.startsAt,
    required this.revision,
    this.endsAt,
    this.seasonEndsOn,
    this.reviewDueAt,
  });
  final String id, personId, personName, targetTeamId, targetTeamName;
  final String kind, validityKind, state;
  final DateTime startsAt;
  final DateTime? endsAt, seasonEndsOn, reviewDueAt;
  final int revision;
  bool get canEnd => state == 'active';

  factory PlayEligibilitySummary.fromJson(Map<String, dynamic> json) =>
      PlayEligibilitySummary(
        id: json['eligibility_id'] as String,
        personId: json['club_person_id'] as String,
        personName: json['person_name'] as String,
        targetTeamId:
            (json['eligibility_team_id'] ?? json['target_team_id']) as String,
        targetTeamName: json['target_team_name'] as String,
        kind: json['eligibility_kind'] as String,
        validityKind: json['validity_kind'] as String,
        state: json['state'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: DateTime.tryParse(json['ends_at'] as String? ?? ''),
        seasonEndsOn: DateTime.tryParse(
          json['season_ends_on'] as String? ?? '',
        ),
        reviewDueAt: DateTime.tryParse(json['review_due_at'] as String? ?? ''),
        revision: (json['revision'] as num).toInt(),
      );
}

class IntraClubMovePerson {
  const IntraClubMovePerson({
    required this.personId,
    required this.personName,
    required this.sourceTeamId,
    required this.sourceTeamName,
    required this.assignmentId,
    required this.assignmentStartsAt,
    required this.assignmentRevision,
  });
  final String personId, personName, sourceTeamId, sourceTeamName, assignmentId;
  final DateTime assignmentStartsAt;
  final int assignmentRevision;

  factory IntraClubMovePerson.fromJson(Map<String, dynamic> json) =>
      IntraClubMovePerson(
        personId: json['club_person_id'] as String,
        personName: json['display_name'] as String,
        sourceTeamId: json['source_team_id'] as String,
        sourceTeamName: json['source_team_name'] as String,
        assignmentId: json['assignment_id'] as String,
        assignmentStartsAt: DateTime.parse(
          json['assignment_starts_at'] as String,
        ),
        assignmentRevision: (json['assignment_revision'] as num).toInt(),
      );
}

class IntraClubMoveTeam {
  const IntraClubMoveTeam({required this.id, required this.name});
  final String id, name;
  factory IntraClubMoveTeam.fromJson(Map<String, dynamic> json) =>
      IntraClubMoveTeam(
        id: json['team_id'] as String,
        name: json['team_name'] as String,
      );
}

class IntraClubMoveOptions {
  const IntraClubMoveOptions({required this.people, required this.teams});
  final List<IntraClubMovePerson> people;
  final List<IntraClubMoveTeam> teams;
  bool get canMove => people.isNotEmpty && teams.isNotEmpty;

  factory IntraClubMoveOptions.fromJson(Map<String, dynamic> json) =>
      IntraClubMoveOptions(
        people: (json['people'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(IntraClubMovePerson.fromJson)
            .toList(growable: false),
        teams: (json['teams'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(IntraClubMoveTeam.fromJson)
            .toList(growable: false),
      );
}

class RosterLifecyclePerson {
  const RosterLifecyclePerson({
    required this.personId,
    required this.personName,
    required this.assignmentId,
    required this.assignmentState,
    required this.assignmentRevision,
  });
  final String personId, personName, assignmentId, assignmentState;
  final int assignmentRevision;
  bool get canArchive => assignmentState == 'active';
  factory RosterLifecyclePerson.fromJson(Map<String, dynamic> json) =>
      RosterLifecyclePerson(
        personId: json['club_person_id'] as String,
        personName: json['person_name'] as String,
        assignmentId: json['assignment_id'] as String,
        assignmentState: json['assignment_state'] as String,
        assignmentRevision: (json['assignment_revision'] as num).toInt(),
      );
}

class ClubErasureRequest {
  const ClubErasureRequest({
    required this.id,
    required this.personId,
    required this.personName,
    required this.state,
    required this.initiatedBy,
    required this.revision,
  });
  final String id, personId, personName, state, initiatedBy;
  final int revision;
  bool get canApprove => state == 'requested';
  factory ClubErasureRequest.fromJson(Map<String, dynamic> json) =>
      ClubErasureRequest(
        id: json['request_id'] as String,
        personId: json['club_person_id'] as String,
        personName: json['person_name'] as String,
        state: json['state'] as String,
        initiatedBy: json['initiated_by'] as String,
        revision: (json['revision'] as num).toInt(),
      );
}

class RosterLifecycleOptions {
  const RosterLifecycleOptions({required this.people, required this.requests});
  final List<RosterLifecyclePerson> people;
  final List<ClubErasureRequest> requests;
  factory RosterLifecycleOptions.fromJson(Map<String, dynamic> json) =>
      RosterLifecycleOptions(
        people: (json['people'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RosterLifecyclePerson.fromJson)
            .toList(growable: false),
        requests: (json['requests'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClubErasureRequest.fromJson)
            .toList(growable: false),
      );
}

enum InvitationPreviewStatus { valid, invalid }

class InvitationPreview {
  const InvitationPreview({
    required this.status,
    this.clubName,
    this.teamName,
    this.personName,
    this.rolePackage,
    this.expiresAt,
  });

  final InvitationPreviewStatus status;
  final String? clubName, teamName, personName, rolePackage;
  final DateTime? expiresAt;

  bool get isValid => status == InvitationPreviewStatus.valid;

  factory InvitationPreview.fromJson(Map<String, dynamic> json) {
    if (json['status'] != 'valid') {
      return const InvitationPreview(status: InvitationPreviewStatus.invalid);
    }
    return InvitationPreview(
      status: InvitationPreviewStatus.valid,
      clubName: json['club_name'] as String?,
      teamName: json['team_name'] as String?,
      personName: json['person_name'] as String?,
      rolePackage: json['role_package'] as String?,
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
    );
  }
}

enum InvitationClaimStatus { claimed, reviewRequired }

class InvitationClaimResult {
  const InvitationClaimResult({
    required this.status,
    this.clubPersonId,
    this.reviewId,
  });

  final InvitationClaimStatus status;
  final String? clubPersonId, reviewId;

  factory InvitationClaimResult.fromJson(Map<String, dynamic> json) {
    return switch (json['status']) {
      'claimed' => InvitationClaimResult(
        status: InvitationClaimStatus.claimed,
        clubPersonId: json['club_person_id'] as String?,
      ),
      'review_required' => InvitationClaimResult(
        status: InvitationClaimStatus.reviewRequired,
        reviewId: json['review_id'] as String?,
      ),
      _ => throw const FormatException('Invitation claim response is invalid.'),
    };
  }
}
