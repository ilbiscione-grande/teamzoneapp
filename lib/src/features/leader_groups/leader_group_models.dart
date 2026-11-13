/// Ledargrupper: a club's groups of leaders across teams (e.g. a
/// herrsektion). A group holds teams, whose leaders belong while they lead
/// the team, and single people; each group has a chat of its own.
class LeaderGroupRef {
  const LeaderGroupRef({required this.id, required this.name});
  factory LeaderGroupRef.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return LeaderGroupRef(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? ''}',
    );
  }
  final String id;
  final String name;
}

class LeaderGroup {
  const LeaderGroup({
    required this.id,
    required this.name,
    required this.revision,
    required this.threadId,
    required this.teams,
    required this.people,
    required this.memberCount,
    this.meetings = const [],
    this.isMember = false,
  });
  factory LeaderGroup.fromJson(Map<String, dynamic> json) => LeaderGroup(
    id: '${json['id']}',
    name: '${json['name'] ?? ''}',
    revision: (json['revision'] as num?)?.toInt() ?? 1,
    threadId: json['thread_id'] as String?,
    teams: _refs(json['teams']),
    people: _refs(json['people']),
    memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    isMember: json['is_member'] == true,
    meetings: [
      for (final item in (json['meetings'] as List? ?? const []))
        if (item is Map)
          LeaderGroupMeeting.fromJson(Map<String, dynamic>.from(item)),
    ],
  );
  final String id;
  final String name;
  final int revision;
  final String? threadId;
  final List<LeaderGroupRef> teams;
  final List<LeaderGroupRef> people;

  /// Everyone in the group right now: the teams' leaders and the people.
  final int memberCount;

  /// Whether the viewer is in the group; only members can open its chat.
  final bool isMember;

  /// Coming meetings, soonest first; cancelled ones are left out.
  final List<LeaderGroupMeeting> meetings;

  /// A meeting is held by one of the group's teams, so a group of single
  /// people only cannot book one.
  bool get canBookMeetings => teams.isNotEmpty;
}

/// A group meeting: an activity in the members' calendars.
class LeaderGroupMeeting {
  const LeaderGroupMeeting({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.location,
  });
  factory LeaderGroupMeeting.fromJson(Map<String, dynamic> json) =>
      LeaderGroupMeeting(
        id: '${json['id']}',
        title: '${json['title'] ?? ''}',
        startsAt: DateTime.parse('${json['starts_at']}').toLocal(),
        endsAt: DateTime.parse('${json['ends_at']}').toLocal(),
        location: json['location'] as String?,
      );
  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? location;
}

/// Someone who can be added on their own: a leader or club functionary.
class LeaderGroupCandidate {
  const LeaderGroupCandidate({
    required this.id,
    required this.name,
    required this.teams,
    required this.offices,
    required this.functionary,
  });
  factory LeaderGroupCandidate.fromJson(Map<String, dynamic> json) =>
      LeaderGroupCandidate(
        id: '${json['id']}',
        name: '${json['name'] ?? ''}',
        teams: _strings(json['teams']),
        offices: _strings(json['offices']),
        functionary: json['functionary'] == true,
      );
  final String id;
  final String name;

  /// The teams they lead.
  final List<String> teams;

  /// Their running board offices (chair, treasurer …).
  final List<String> offices;
  final bool functionary;
}

class LeaderGroupsOverview {
  const LeaderGroupsOverview({
    required this.groups,
    required this.teams,
    required this.people,
  });
  factory LeaderGroupsOverview.fromJson(Map<String, dynamic> json) =>
      LeaderGroupsOverview(
        groups: [
          for (final item in (json['groups'] as List? ?? const []))
            if (item is Map)
              LeaderGroup.fromJson(Map<String, dynamic>.from(item)),
        ],
        teams: _refs(json['teams']),
        people: [
          for (final item in (json['people'] as List? ?? const []))
            if (item is Map)
              LeaderGroupCandidate.fromJson(Map<String, dynamic>.from(item)),
        ],
      );
  final List<LeaderGroup> groups;

  /// The club's active teams.
  final List<LeaderGroupRef> teams;
  final List<LeaderGroupCandidate> people;
}

/// A save or archive the server refused.
class LeaderGroupException implements Exception {
  const LeaderGroupException(this.code);

  /// name_taken, stale_revision, empty_group, invalid_name or no_team.
  final String code;
  @override
  String toString() => 'LeaderGroupException($code)';
}

List<LeaderGroupRef> _refs(Object? value) => [
  for (final item in (value is List ? value : const []))
    LeaderGroupRef.fromJson(item),
];

List<String> _strings(Object? value) => [
  for (final item in (value is List ? value : const [])) '$item',
];
