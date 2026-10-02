class RosterPersonSummary {
  const RosterPersonSummary({
    required this.id,
    required this.displayName,
    required this.safeguardingRequired,
    this.ageClass,
    this.teamId,
    this.teamName,
    this.assignmentState,
    this.accountLinked = false,
  });

  final String id;
  final String displayName;
  final String? ageClass;
  final bool safeguardingRequired;
  final String? teamId;
  final String? teamName;
  final String? assignmentState;
  // Already has an active core.person_account_links row — re-inviting them
  // to claim this identity would be meaningless, so pickers that offer a
  // roster person to invite as a new claim should exclude these.
  final bool accountLinked;

  factory RosterPersonSummary.fromJson(Map<String, dynamic> json) {
    return RosterPersonSummary(
      id: json['club_person_id'] as String,
      displayName: json['display_name'] as String,
      ageClass: json['age_class'] as String?,
      safeguardingRequired: json['safeguarding_required'] as bool? ?? false,
      teamId: json['team_id'] as String?,
      teamName: json['team_name'] as String?,
      assignmentState: json['assignment_state'] as String?,
      accountLinked: json['account_linked'] as bool? ?? false,
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
    this.imageAssetId,
  });

  final String teamId, clubId, teamName, clubName;
  final String? teamType, ageClass, summary, imageUrl, imageAssetId;
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
    imageAssetId: json['image_asset_id'] as String?,
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
    this.imageAssetId,
  });

  final String teamId;
  final int revision;
  final String? teamType, ageClass, summary, imageUrl, imageAssetId;

  factory TeamProfileEditData.fromJson(Map<String, dynamic> json) =>
      TeamProfileEditData(
        teamId: json['team_id'] as String,
        revision: (json['revision'] as num? ?? 0).toInt(),
        teamType: json['team_type'] as String?,
        ageClass: json['age_class'] as String?,
        summary: json['summary'] as String?,
        imageUrl: json['image_url'] as String?,
        imageAssetId: json['image_asset_id'] as String?,
      );
}

class StagedTeamImage {
  const StagedTeamImage({
    required this.imageId,
    required this.bucketId,
    required this.objectKey,
  });

  final String imageId, bucketId, objectKey;

  factory StagedTeamImage.fromJson(Map<String, dynamic> json) =>
      StagedTeamImage(
        imageId: json['image_id'] as String,
        bucketId: json['bucket_id'] as String,
        objectKey: json['object_key'] as String,
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
    this.birthDate,
    this.birthYear,
    this.safeguardingRequired,
    this.representationAvailable,
    this.accountLinked,
    this.isSelf = false,
    this.homeMember = true,
    this.provenance,
    this.assignmentStartsAt,
    this.assignmentEndsAt,
    this.assignmentRevision,
    this.personRevision,
  });
  final String id, displayName, teamId, teamName, assignmentState;
  final String? ageClass, provenance;
  final DateTime? birthDate;
  final int? birthYear;
  final bool? safeguardingRequired;
  final bool? representationAvailable;
  final bool? accountLinked;
  final bool isSelf;

  /// Whether the person belongs to the team as a player (home team). Leaders
  /// and functionaries are found through their role and are not.
  final bool homeMember;
  final DateTime? assignmentStartsAt, assignmentEndsAt;
  final int? assignmentRevision;
  final int? personRevision;

  bool get hasManagementDetails => provenance != null;

  factory RosterPersonDetails.fromJson(Map<String, dynamic> json) {
    final management = json['management'];
    final manager = management is Map
        ? Map<String, dynamic>.from(management)
        : null;
    return RosterPersonDetails(
      id: json['club_person_id'] as String,
      displayName: json['display_name'] as String,
      teamId: json['team_id'] as String,
      teamName: json['team_name'] as String,
      assignmentState: json['assignment_state'] as String,
      ageClass: json['age_class'] as String?,
      birthDate: DateTime.tryParse(manager?['birth_date'] as String? ?? ''),
      birthYear: (manager?['birth_year'] as num?)?.toInt(),
      safeguardingRequired: json['safeguarding_required'] as bool?,
      representationAvailable: json['representation_available'] as bool?,
      accountLinked: json['account_linked'] as bool?,
      isSelf: json['is_self'] as bool? ?? false,
      homeMember: json['home_member'] as bool? ?? true,
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

class PersonAttendanceSummary {
  const PersonAttendanceSummary({
    required this.trainingsTotal,
    required this.trainingsAttended,
    required this.matchesTotal,
    required this.matchesPlayed,
  });
  final int trainingsTotal, trainingsAttended, matchesTotal, matchesPlayed;

  factory PersonAttendanceSummary.fromJson(Map<String, dynamic> json) =>
      PersonAttendanceSummary(
        trainingsTotal: (json['trainings_total'] as num? ?? 0).toInt(),
        trainingsAttended: (json['trainings_attended'] as num? ?? 0).toInt(),
        matchesTotal: (json['matches_total'] as num? ?? 0).toInt(),
        matchesPlayed: (json['matches_played'] as num? ?? 0).toInt(),
      );
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
  bool get isExpired =>
      state == 'issued' &&
      expiresAt != null &&
      !expiresAt!.isAfter(DateTime.now());
  String get displayState => isExpired ? 'expired' : state;
  bool get canRevoke =>
      kind != 'guardian_relation' &&
      state == 'issued' &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());
  bool get canEndRelation => kind == 'guardian_relation' && state == 'active';
  bool get isActive => canRevoke || canEndRelation;

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
    this.homeTeamId,
    this.homeTeamName,
    this.canDecide = false,
    this.endsAt,
    this.seasonEndsOn,
    this.reviewDueAt,
  });
  final String id, personId, personName, targetTeamId, targetTeamName;
  final String kind, validityKind, state;
  final DateTime startsAt;
  final DateTime? endsAt, seasonEndsOn, reviewDueAt;
  final int revision;
  // Null for eligibilities created before the home-team approval workflow
  // existed -- those rows are already 'active' and were never 'pending'.
  final String? homeTeamId;
  final String? homeTeamName;
  // Whether the acting team is this row's home team AND the row is still
  // 'pending' -- the only combination that may approve or reject it.
  final bool canDecide;
  bool get canEnd => state == 'active';
  bool get isPendingApproval => state == 'pending';

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
        homeTeamId: json['home_team_id'] as String?,
        homeTeamName: json['home_team_name'] as String?,
        canDecide: json['can_decide'] as bool? ?? false,
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
    this.canReactivate = false,
  });
  final String personId, personName, assignmentId, assignmentState;
  final int assignmentRevision;
  final bool canReactivate;
  bool get canArchive => assignmentState == 'active';
  factory RosterLifecyclePerson.fromJson(Map<String, dynamic> json) =>
      RosterLifecyclePerson(
        personId: json['club_person_id'] as String,
        personName: json['person_name'] as String,
        assignmentId: json['assignment_id'] as String,
        assignmentState: json['assignment_state'] as String,
        assignmentRevision: (json['assignment_revision'] as num).toInt(),
        canReactivate: json['can_reactivate'] as bool? ?? false,
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

/// One active role a person holds in a team (TEAM-09).
class TeamRole {
  const TeamRole({
    required this.personId,
    required this.name,
    required this.role,
    this.isSelf = false,
    this.titles = const [],
    this.positions = const [],
    this.customTitles = const [],
    this.customPositions = const [],
    this.mainPosition,
    this.mainTitle,
    this.detailsRevision = 0,
    this.permissions,
    this.permissionTemplate,
  });
  final String personId, name, role;
  final bool isSelf;

  /// Descriptive only (never permissions). [titles] are catalog keys such as
  /// head_coach and belong to leader roles; [positions] are keys from the
  /// team sport's catalog and belong to player roles. The custom lists hold
  /// the team's own labels.
  final List<String> titles, positions, customTitles, customPositions;

  /// The main playing position: one of [positions] or [customPositions];
  /// the others are alternatives.
  final String? mainPosition;

  /// The main title: one of [titles] or [customTitles], shown instead of the
  /// leader role.
  final String? mainTitle;
  final int detailsRevision;

  /// A leader's panel capabilities in this team; only sent to viewers who
  /// manage leaders (null otherwise, and for non-leader rows).
  final List<String>? permissions;
  final String? permissionTemplate;

  factory TeamRole.fromJson(Map<String, dynamic> json) => TeamRole(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    role: json['role'] as String? ?? 'player',
    isSelf: json['is_self'] == true,
    titles: _strings(json['functions']),
    positions: _strings(json['positions']),
    customTitles: _strings(json['custom_titles']),
    customPositions: _strings(json['custom_positions']),
    mainPosition: json['main_position'] as String?,
    mainTitle: json['main_title'] as String?,
    detailsRevision: (json['details_revision'] as num?)?.toInt() ?? 0,
    permissions: json['permissions'] is List
        ? _strings(json['permissions'])
        : null,
    permissionTemplate: json['permission_template'] as String?,
  );
}

List<String> _strings(Object? value) =>
    (value as List? ?? const []).whereType<String>().toList();

/// One position in a sport's catalog: general (e.g. defender) or
/// detailed with its general [parent] (e.g. centre_back → defender).
class SportPosition {
  const SportPosition({required this.key, required this.level, this.parent});
  final String key, level;
  final String? parent;
  bool get isGeneral => level == 'general';

  factory SportPosition.fromJson(Map<String, dynamic> json) => SportPosition(
    key: json['key'] as String,
    level: json['level'] as String? ?? 'general',
    parent: json['parent'] as String?,
  );
}

class TeamRoles {
  const TeamRoles({
    required this.canManage,
    required this.roles,
    this.sport = 'football',
    this.positionCatalog = const [],
    bool? canEditDetails,
    this.grantable = const [],
    this.canSetSport = false,
  }) : canEditDetails = canEditDetails ?? canManage;

  /// Club administrator: may change which sport the team plays.
  final bool canSetSport;

  /// Manages leaders: adds/changes leader roles and edits permissions.
  final bool canManage;

  /// May edit titles and positions (roster or leader management).
  final bool canEditDetails;

  /// Panel capabilities the viewer holds and can therefore give or remove.
  final List<String> grantable;
  final List<TeamRole> roles;
  final String sport;
  final List<SportPosition> positionCatalog;

  List<String> rolesOf(String personId) => [
    for (final role in roles)
      if (role.personId == personId) role.role,
  ];

  factory TeamRoles.fromJson(Map<String, dynamic> json) => TeamRoles(
    canManage: json['can_manage'] == true,
    canEditDetails: json['can_edit_details'] as bool?,
    canSetSport: json['can_set_sport'] == true,
    grantable: _strings(json['grantable']),
    roles: (json['roles'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TeamRole.fromJson)
        .toList(growable: false),
    sport: json['sport'] as String? ?? 'football',
    positionCatalog: (json['position_catalog'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SportPosition.fromJson)
        .toList(growable: false),
  );
}

/// A leader or functionary elsewhere in the club who could also lead this team.
class LeaderCandidate {
  const LeaderCandidate({
    required this.personId,
    required this.name,
    required this.context,
    this.isSelf = false,
  });
  final String personId, name, context;
  final bool isSelf;

  factory LeaderCandidate.fromJson(Map<String, dynamic> json) =>
      LeaderCandidate(
        personId: json['person_id'] as String,
        name: json['name'] as String? ?? '',
        context: json['context'] as String? ?? '',
        isSelf: json['is_self'] == true,
      );
}

/// A role command the server refused for a known reason
/// (`own_leader_role`, `home_in_other_team`, `stale_role`).
class TeamRoleException implements Exception {
  const TeamRoleException(this.code);
  final String code;
}
