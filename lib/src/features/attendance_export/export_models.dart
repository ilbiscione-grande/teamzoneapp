// Provider-neutral models for the temporary attendance export.
//
// Nothing here knows any receiver's file format; receivers (laget.se first)
// live in their own adapter. See docs/implementation/attendance_export_laget_se.md.

/// Explicit, actually recorded attendance. Only [present] and [absent] may be
/// exported; [unknown] (nothing recorded yet) is never turned into absent.
enum ExplicitAttendance { present, absent, unknown }

/// Maps Teamzone's recorded status (core.attendance_facts) to explicit
/// attendance. Late and partial count as present, as everywhere else in
/// Teamzone's attendance statistics. Callup answers are never used here.
ExplicitAttendance explicitAttendanceFromStatus(String? status) =>
    switch (status) {
      'present' || 'late' || 'partial' => ExplicitAttendance.present,
      'absent' => ExplicitAttendance.absent,
      _ => ExplicitAttendance.unknown,
    };

/// How a person relates to the team being exported.
enum ExportMembership {
  /// Player/leader assignment in the team at the time of the event.
  team,

  /// Belongs to another team sharing the event.
  otherTeam,

  /// Added to the event without any assignment on its teams.
  guest,
}

/// Link between a Teamzone person and a person in an external system,
/// scoped to one team and one receiver.
class ExternalMemberLink {
  const ExternalMemberLink({
    required this.teamId,
    required this.personId,
    required this.externalId,
    required this.externalName,
    required this.externalRole,
    this.id,
    this.personName,
    this.source = 'manual',
    this.revision = 1,
  });
  final String? id, personName;
  final String teamId, personId, externalId, externalName, externalRole;

  /// manual, or import (reserved for a future member-list import).
  final String source;
  final int revision;

  factory ExternalMemberLink.fromJson(Map<String, dynamic> json) =>
      ExternalMemberLink(
        id: json['id'] as String?,
        teamId: json['team_id'] as String,
        personId: json['person_id'] as String,
        personName: json['person_name'] as String?,
        externalId: json['external_id'] as String,
        externalName: json['external_name'] as String,
        externalRole: json['external_role'] as String,
        source: json['source'] as String? ?? 'manual',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
      );
}

/// Link between a Teamzone event and an activity in an external system.
class ExternalActivityLink {
  const ExternalActivityLink({
    required this.teamId,
    required this.externalActivityId,
    this.revision = 1,
  });
  final String teamId, externalActivityId;
  final int revision;

  factory ExternalActivityLink.fromJson(Map<String, dynamic> json) =>
      ExternalActivityLink(
        teamId: json['team_id'] as String,
        externalActivityId: json['external_activity_id'] as String,
        revision: (json['revision'] as num?)?.toInt() ?? 1,
      );
}

/// Export state as shown to the administrator. A created file is NOT a
/// synchronization; [verified]/[rejected] are reserved for future feedback
/// from the external sync tool.
enum ExportState { notExported, fileCreated, failed, verified, rejected }

ExportState exportStateFromString(String? value) => switch (value) {
  'file_created' => ExportState.fileCreated,
  'failed' => ExportState.failed,
  'verified' => ExportState.verified,
  'rejected' => ExportState.rejected,
  _ => ExportState.notExported,
};

class ExportRecord {
  const ExportRecord({
    required this.id,
    required this.state,
    required this.createdAt,
    this.externalActivityId,
    this.payloadSha256,
    this.errorCode,
    this.summary = const {},
  });
  final String id;
  final ExportState state;
  final DateTime createdAt;
  final String? externalActivityId, payloadSha256, errorCode;
  final Map<String, dynamic> summary;

  factory ExportRecord.fromJson(Map<String, dynamic> json) => ExportRecord(
    id: json['id'] as String,
    state: exportStateFromString(json['state'] as String?),
    createdAt: DateTime.parse(json['created_at'] as String),
    externalActivityId: json['external_activity_id'] as String?,
    payloadSha256: json['payload_sha256'] as String?,
    errorCode: json['error_code'] as String?,
    summary: Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
  );
}

/// Integration-side context for exporting one event for one team.
class ExportContext {
  const ExportContext({
    required this.eventId,
    required this.teamId,
    required this.teamName,
    required this.provider,
    required this.enabled,
    required this.teamRoster,
    required this.links,
    this.activityLink,
    this.exports = const [],
    this.syncJobs = const [],
    this.externalTeamRef,
    this.agent,
  });
  final String eventId, teamId, teamName, provider;
  final bool enabled;
  final ExternalActivityLink? activityLink;

  /// The team's path segment on admin.laget.se; needed by the sync agent.
  final String? externalTeamRef;

  /// Newest first.
  final List<SyncJob> syncJobs;

  /// The caller's own sync agent, if it has ever been started.
  final SyncAgentStatus? agent;

  SyncJob? get latestSyncJob => syncJobs.firstOrNull;

  /// person id -> the person's player/leader roles in the team at the event.
  final Map<String, Set<String>> teamRoster;
  final List<ExternalMemberLink> links;

  /// Newest first.
  final List<ExportRecord> exports;

  ExportState get state =>
      exports.isEmpty ? ExportState.notExported : exports.first.state;

  ExportRecord? get lastFileCreated => exports
      .where((record) => record.state == ExportState.fileCreated)
      .firstOrNull;

  factory ExportContext.fromJson(Map<String, dynamic> json) {
    final roster = <String, Set<String>>{};
    for (final row in json['team_roster'] as List? ?? const []) {
      if (row is! Map) continue;
      roster
          .putIfAbsent(row['person_id'] as String, () => <String>{})
          .add(row['role_package'] as String);
    }
    final link = json['activity_link'];
    final agent = json['agent'];
    return ExportContext(
      externalTeamRef: json['external_team_ref'] as String?,
      agent: agent is Map
          ? SyncAgentStatus.fromJson(Map<String, dynamic>.from(agent))
          : null,
      syncJobs: [
        for (final row in json['sync_jobs'] as List? ?? const [])
          if (row is Map) SyncJob.fromJson(Map<String, dynamic>.from(row)),
      ],
      eventId: json['event_id'] as String,
      teamId: json['team_id'] as String,
      teamName: json['team_name'] as String? ?? '',
      provider: json['provider'] as String,
      enabled: json['enabled'] as bool? ?? false,
      activityLink: link is Map
          ? ExternalActivityLink.fromJson(Map<String, dynamic>.from(link))
          : null,
      teamRoster: roster,
      links: [
        for (final row in json['links'] as List? ?? const [])
          if (row is Map)
            ExternalMemberLink.fromJson(Map<String, dynamic>.from(row)),
      ],
      exports: [
        for (final row in json['exports'] as List? ?? const [])
          if (row is Map) ExportRecord.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }
}

/// A team member as listed in the integration settings.
class IntegrationTeamMember {
  const IntegrationTeamMember({
    required this.personId,
    required this.name,
    required this.roles,
  });
  final String personId, name;
  final Set<String> roles;
}

class TeamIntegrationSettings {
  const TeamIntegrationSettings({
    required this.teamId,
    required this.provider,
    required this.enabled,
    required this.revision,
    required this.members,
    required this.links,
    this.externalTeamRef,
    this.settings = const {},
  });
  final String teamId, provider;
  final bool enabled;
  final String? externalTeamRef;
  final Map<String, dynamic> settings;
  final int revision;
  final List<IntegrationTeamMember> members;
  final List<ExternalMemberLink> links;

  ExternalMemberLink? linkFor(String personId) =>
      links.where((link) => link.personId == personId).firstOrNull;

  factory TeamIntegrationSettings.fromJson(Map<String, dynamic> json) =>
      TeamIntegrationSettings(
        teamId: json['team_id'] as String,
        provider: json['provider'] as String,
        enabled: json['enabled'] as bool? ?? false,
        externalTeamRef: json['external_team_ref'] as String?,
        settings: Map<String, dynamic>.from(
          json['settings'] as Map? ?? const {},
        ),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        members: [
          for (final row in json['members'] as List? ?? const [])
            if (row is Map)
              IntegrationTeamMember(
                personId: row['person_id'] as String,
                name: row['name'] as String,
                roles: {
                  for (final role in row['role_packages'] as List? ?? const [])
                    if (role is String) role,
                },
              ),
        ],
        links: [
          for (final row in json['links'] as List? ?? const [])
            if (row is Map)
              ExternalMemberLink.fromJson(Map<String, dynamic>.from(row)),
        ],
      );
}

/// One person who took part in the event (recorded attendance or an active
/// callup), as seen from the exported team.
class ExportCandidate {
  const ExportCandidate({
    required this.personId,
    required this.name,
    required this.membership,
    required this.teamRoles,
    required this.attendance,
    this.recordedStatus,
  });
  final String personId, name;
  final ExportMembership membership;

  /// player/leader roles in the exported team; empty for guests/other teams.
  final Set<String> teamRoles;
  final ExplicitAttendance attendance;

  /// Raw Teamzone status (present, late, partial, absent, unknown).
  final String? recordedStatus;
}

/// Teamzone's own export basis for one event and one team: event facts and
/// every participant with explicit attendance — no receiver format.
class AttendanceExportBasis {
  const AttendanceExportBasis({
    required this.eventId,
    required this.teamId,
    required this.eventTitle,
    required this.eventType,
    required this.eventState,
    required this.startsAt,
    required this.endsAt,
    required this.eventTeamIds,
    required this.ended,
    required this.candidates,
  });
  final String eventId, teamId, eventTitle, eventType, eventState;
  final DateTime startsAt, endsAt;
  final Set<String> eventTeamIds;

  /// The event's end has passed and it was not cancelled.
  final bool ended;
  final List<ExportCandidate> candidates;

  bool get belongsToTeam => eventTeamIds.contains(teamId);
}

/// State of a sync through the local sync agent.
enum SyncJobState {
  queued,

  /// The agent is looking for the activity in the receiver's calendar.
  locating,
  previewing,
  awaitingApproval,
  approved,
  applying,
  verified,
  failed,

  /// No single matching activity; the administrator chooses one.
  needsActivity,
  cancelled,
}

/// An activity on the receiver offered when no single match was found.
class SyncActivityCandidate {
  const SyncActivityCandidate({
    required this.id,
    required this.date,
    required this.label,
  });
  final String id, date, label;
}

SyncJobState syncJobStateFromString(String? value) => switch (value) {
  'locating' => SyncJobState.locating,
  'needs_activity' => SyncJobState.needsActivity,
  'previewing' => SyncJobState.previewing,
  'awaiting_approval' => SyncJobState.awaitingApproval,
  'approved' => SyncJobState.approved,
  'applying' => SyncJobState.applying,
  'verified' => SyncJobState.verified,
  'failed' => SyncJobState.failed,
  'cancelled' => SyncJobState.cancelled,
  _ => SyncJobState.queued,
};

/// One planned change on the receiver, as read by the agent.
class SyncPreviewChange {
  const SyncPreviewChange({
    required this.name,
    required this.role,
    required this.from,
    required this.to,
  });
  final String name, role, from, to;
}

/// What the agent read on the receiver and plans to change.
class SyncPreview {
  const SyncPreview({
    required this.changes,
    required this.unchanged,
    required this.problems,
    this.pageTitle,
  });
  final List<SyncPreviewChange> changes;
  final int unchanged;
  final List<String> problems;
  final String? pageTitle;

  factory SyncPreview.fromJson(Map<String, dynamic> json) => SyncPreview(
    pageTitle: json['pageTitle'] as String?,
    unchanged: (json['unchanged'] as num?)?.toInt() ?? 0,
    problems: [
      for (final problem in json['problems'] as List? ?? const [])
        if (problem is String) problem,
    ],
    changes: [
      for (final row in json['changes'] as List? ?? const [])
        if (row is Map)
          SyncPreviewChange(
            name: row['name'] as String? ?? '',
            role: row['role'] as String? ?? 'player',
            from: row['from'] as String? ?? 'unknown',
            to: row['to'] as String? ?? 'unknown',
          ),
    ],
  );
}

class SyncJob {
  const SyncJob({
    required this.id,
    required this.state,
    required this.requestedAt,
    this.preview,
    this.previewSha256,
    this.message,
    this.finishedAt,
    this.result = const {},
    this.candidates = const [],
  });
  final String id;
  final SyncJobState state;
  final DateTime requestedAt;
  final DateTime? finishedAt;
  final SyncPreview? preview;
  final String? previewSha256, message;
  final Map<String, dynamic> result;

  /// When the agent could not find exactly one activity: the receiver's
  /// activities that day, for the administrator to choose from.
  final List<SyncActivityCandidate> candidates;

  /// Waiting for the agent or being processed by it.
  bool get isRunning => const {
    SyncJobState.queued,
    SyncJobState.locating,
    SyncJobState.previewing,
    SyncJobState.approved,
    SyncJobState.applying,
  }.contains(state);

  factory SyncJob.fromJson(Map<String, dynamic> json) {
    final preview = json['preview'];
    return SyncJob(
      id: json['id'] as String,
      state: syncJobStateFromString(json['state'] as String?),
      requestedAt: DateTime.parse(json['requested_at'] as String),
      finishedAt: json['finished_at'] == null
          ? null
          : DateTime.parse(json['finished_at'] as String),
      preview: preview is Map
          ? SyncPreview.fromJson(Map<String, dynamic>.from(preview))
          : null,
      previewSha256: json['preview_sha256'] as String?,
      message: json['message'] as String?,
      result: Map<String, dynamic>.from(json['result'] as Map? ?? const {}),
      candidates: [
        for (final row in json['candidates'] as List? ?? const [])
          if (row is Map && row['id'] is String)
            SyncActivityCandidate(
              id: row['id'] as String,
              date: row['date'] as String? ?? '',
              label: row['label'] as String? ?? '',
            ),
      ],
    );
  }
}

class SyncAgentStatus {
  const SyncAgentStatus({required this.lastSeenAt, this.lagetSessionOk});
  final DateTime lastSeenAt;
  final bool? lagetSessionOk;

  /// The agent reports every few seconds while it runs.
  bool isOnline(DateTime now) =>
      now.difference(lastSeenAt) < const Duration(minutes: 2);

  factory SyncAgentStatus.fromJson(Map<String, dynamic> json) =>
      SyncAgentStatus(
        lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
        lagetSessionOk: json['laget_session_ok'] as bool?,
      );
}
