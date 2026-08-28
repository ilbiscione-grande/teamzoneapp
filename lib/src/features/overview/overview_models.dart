class MainSurfacesProjection {
  const MainSurfacesProjection({
    required this.schemaVersion,
    required this.generatedAt,
    required this.syncCursor,
    required this.contexts,
    required this.actions,
    required this.home,
    required this.inbox,
    required this.statistics,
    this.isStale = false,
  });

  final int schemaVersion;
  final DateTime generatedAt;
  final String syncCursor;
  final List<SurfaceContextSummary> contexts;
  final List<SurfaceAction> actions;
  final HomeProjection home;
  final InboxProjection inbox;
  final AttendanceStatistics statistics;
  final bool isStale;

  factory MainSurfacesProjection.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'];
    if (version != 1) throw const FormatException('Unsupported projection.');
    return MainSurfacesProjection(
      schemaVersion: version as int,
      generatedAt: DateTime.parse(json['generated_at'] as String),
      syncCursor: json['sync_cursor'] as String,
      contexts: _maps(
        json['contexts'],
      ).map(SurfaceContextSummary.fromJson).toList(),
      actions: _maps(json['actions']).map(SurfaceAction.fromJson).toList(),
      home: HomeProjection.fromJson(_map(json['home'])),
      inbox: InboxProjection.fromJson(_map(json['inbox'])),
      statistics: AttendanceStatistics.fromJson(_map(json['statistics'])),
    );
  }

  MainSurfacesProjection asStale() => MainSurfacesProjection(
    schemaVersion: schemaVersion,
    generatedAt: generatedAt,
    syncCursor: syncCursor,
    contexts: contexts,
    actions: actions,
    home: home,
    inbox: inbox,
    statistics: statistics,
    isStale: true,
  );
}

class SurfaceContextSummary {
  const SurfaceContextSummary({
    required this.contextId,
    required this.name,
    required this.memberCount,
  });
  final String contextId;
  final String name;
  final int memberCount;
  factory SurfaceContextSummary.fromJson(Map<String, dynamic> json) =>
      SurfaceContextSummary(
        contextId: json['context_id'] as String,
        name: (json['team_name'] ?? json['club_name']) as String,
        memberCount: (json['member_count'] as num).toInt(),
      );
}

class SurfaceAction {
  const SurfaceAction({
    required this.name,
    required this.route,
    required this.contextId,
  });
  final String name;
  final String route;
  final String contextId;
  factory SurfaceAction.fromJson(Map<String, dynamic> json) => SurfaceAction(
    name: json['action'] as String,
    route: json['route'] as String,
    contextId: json['context_id'] as String,
  );
}

class HomeProjection {
  const HomeProjection({
    required this.upcomingCount,
    required this.pendingCallupCount,
    this.nextEvent,
  });
  final int upcomingCount;
  final int pendingCallupCount;
  final NextEvent? nextEvent;
  factory HomeProjection.fromJson(Map<String, dynamic> json) => HomeProjection(
    upcomingCount: (json['upcoming_count'] as num).toInt(),
    pendingCallupCount: (json['pending_callup_count'] as num).toInt(),
    nextEvent: json['next_event'] == null
        ? null
        : NextEvent.fromJson(_map(json['next_event'])),
  );
}

class NextEvent {
  const NextEvent({
    required this.id,
    required this.title,
    required this.startsAt,
  });
  final String id;
  final String title;
  final DateTime startsAt;
  factory NextEvent.fromJson(Map<String, dynamic> json) => NextEvent(
    id: json['event_id'] as String,
    title: json['title'] as String,
    startsAt: DateTime.parse(json['starts_at'] as String),
  );
}

class InboxProjection {
  const InboxProjection({
    required this.messagesAvailable,
    required this.pendingNotificationCount,
  });
  final bool messagesAvailable;
  final int pendingNotificationCount;
  factory InboxProjection.fromJson(Map<String, dynamic> json) =>
      InboxProjection(
        messagesAvailable: json['messages_available'] as bool,
        pendingNotificationCount: (json['pending_notification_count'] as num)
            .toInt(),
      );
}

class AttendanceStatistics {
  const AttendanceStatistics({
    required this.present,
    required this.late,
    required this.partial,
    required this.absent,
    required this.unknown,
  });
  final int present, late, partial, absent, unknown;
  int get total => present + late + partial + absent + unknown;
  factory AttendanceStatistics.fromJson(Map<String, dynamic> json) =>
      AttendanceStatistics(
        present: (json['present'] as num).toInt(),
        late: (json['late'] as num).toInt(),
        partial: (json['partial'] as num).toInt(),
        absent: (json['absent'] as num).toInt(),
        unknown: (json['unknown'] as num).toInt(),
      );
}

class LeaderHomeProjection {
  const LeaderHomeProjection({
    required this.generatedAt,
    required this.todayEvents,
    required this.tasks,
    required this.planningActions,
    this.nextEvent,
  });
  final DateTime generatedAt;
  final List<LeaderHomeEvent> todayEvents;
  final List<LeaderHomeTask> tasks;
  final List<LeaderHomeAction> planningActions;
  final LeaderHomeEvent? nextEvent;
  factory LeaderHomeProjection.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 || json['role_package'] != 'leader') {
      throw const FormatException('Unsupported leader home projection.');
    }
    return LeaderHomeProjection(
      generatedAt: DateTime.parse(json['generated_at'] as String),
      todayEvents: _maps(
        json['today_events'],
      ).map(LeaderHomeEvent.fromJson).toList(growable: false),
      tasks: _maps(
        json['tasks'],
      ).map(LeaderHomeTask.fromJson).toList(growable: false),
      planningActions: _maps(json['planning_actions'])
          .map(LeaderHomeAction.fromJson)
          .where((action) => action.enabled)
          .toList(growable: false),
      nextEvent: json['next_event'] == null
          ? null
          : LeaderHomeEvent.fromJson(_map(json['next_event'])),
    );
  }
}

class LeaderHomeEvent {
  const LeaderHomeEvent({
    required this.id,
    required this.title,
    required this.type,
    required this.state,
    required this.startsAt,
    required this.endsAt,
    this.locationName,
    this.address,
  });
  final String id, title, type, state;
  final DateTime startsAt, endsAt;
  final String? locationName, address;
  factory LeaderHomeEvent.fromJson(Map<String, dynamic> json) =>
      LeaderHomeEvent(
        id: json['event_id'] as String,
        title: json['title'] as String,
        type: json['event_type'] as String,
        state: json['state'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
        locationName: json['location_name'] as String?,
        address: json['address'] as String?,
      );
}

class LeaderHomeTask {
  const LeaderHomeTask({
    required this.kind,
    required this.title,
    required this.count,
    required this.route,
    required this.priority,
  });
  final String kind, title, route;
  final int count, priority;
  factory LeaderHomeTask.fromJson(Map<String, dynamic> json) => LeaderHomeTask(
    kind: json['kind'] as String,
    title: json['title'] as String,
    count: (json['count'] as num).toInt(),
    route: json['route'] as String,
    priority: (json['priority'] as num).toInt(),
  );
}

class LeaderHomeAction {
  const LeaderHomeAction({
    required this.kind,
    required this.title,
    required this.route,
    required this.enabled,
  });
  final String kind, title, route;
  final bool enabled;
  factory LeaderHomeAction.fromJson(Map<String, dynamic> json) =>
      LeaderHomeAction(
        kind: json['kind'] as String,
        title: json['title'] as String,
        route: json['route'] as String,
        enabled: json['enabled'] as bool? ?? false,
      );
}

class PlayerHomeProjection {
  const PlayerHomeProjection({
    required this.generatedAt,
    required this.team,
    required this.callups,
    required this.unreadMessageCount,
    this.nextEvent,
  });
  final DateTime generatedAt;
  final PlayerHomeTeam team;
  final List<PlayerHomeCallup> callups;
  final int unreadMessageCount;
  final LeaderHomeEvent? nextEvent;
  factory PlayerHomeProjection.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 || json['role_package'] != 'player') {
      throw const FormatException('Unsupported player home projection.');
    }
    return PlayerHomeProjection(
      generatedAt: DateTime.parse(json['generated_at'] as String),
      team: PlayerHomeTeam.fromJson(_map(json['team'])),
      callups: _maps(
        json['own_callups'],
      ).map(PlayerHomeCallup.fromJson).toList(growable: false),
      unreadMessageCount: (json['unread_message_count'] as num?)?.toInt() ?? 0,
      nextEvent: json['next_event'] == null
          ? null
          : LeaderHomeEvent.fromJson(_map(json['next_event'])),
    );
  }
}

class PlayerHomeTeam {
  const PlayerHomeTeam({
    required this.teamId,
    required this.teamName,
    required this.clubName,
    required this.memberCount,
  });
  final String teamId, teamName, clubName;
  final int memberCount;
  factory PlayerHomeTeam.fromJson(Map<String, dynamic> json) => PlayerHomeTeam(
    teamId: json['team_id'] as String,
    teamName: json['team_name'] as String,
    clubName: json['club_name'] as String,
    memberCount: (json['member_count'] as num).toInt(),
  );
}

class PlayerHomeCallup {
  const PlayerHomeCallup({
    required this.id,
    required this.eventId,
    required this.state,
    required this.revision,
    required this.eventTitle,
    required this.eventType,
    required this.startsAt,
    required this.endsAt,
    required this.canRespond,
    required this.responseRole,
    this.expiresAt,
    this.locationName,
    this.address,
    this.actingAsPersonId,
  });
  final String id, eventId, state, eventTitle, eventType, responseRole;
  final int revision;
  final DateTime startsAt, endsAt;
  final DateTime? expiresAt;
  final String? locationName, address, actingAsPersonId;
  final bool canRespond;
  factory PlayerHomeCallup.fromJson(Map<String, dynamic> json) =>
      PlayerHomeCallup(
        id: json['callup_id'] as String,
        eventId: json['event_id'] as String,
        state: json['state'] as String,
        revision: (json['revision'] as num).toInt(),
        eventTitle: json['event_title'] as String,
        eventType: json['event_type'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String),
        locationName: json['location_name'] as String?,
        address: json['address'] as String?,
        canRespond: json['can_respond'] as bool? ?? false,
        actingAsPersonId: json['acting_as_person_id'] as String?,
        responseRole: json['response_role'] as String,
      );
}

class GuardianHomeProjection {
  const GuardianHomeProjection({
    required this.generatedAt,
    required this.team,
    required this.children,
    required this.selectedChildId,
    required this.callups,
    required this.unreadMessageCount,
    this.nextEvent,
  });
  final DateTime generatedAt;
  final PlayerHomeTeam team;
  final List<GuardianHomeChild> children;
  final String selectedChildId;
  final List<PlayerHomeCallup> callups;
  final int unreadMessageCount;
  final LeaderHomeEvent? nextEvent;
  GuardianHomeChild get selectedChild =>
      children.firstWhere((child) => child.id == selectedChildId);
  factory GuardianHomeProjection.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 || json['role_package'] != 'guardian') {
      throw const FormatException('Unsupported guardian home projection.');
    }
    return GuardianHomeProjection(
      generatedAt: DateTime.parse(json['generated_at'] as String),
      team: PlayerHomeTeam.fromJson(_map(json['team'])),
      children: _maps(
        json['children'],
      ).map(GuardianHomeChild.fromJson).toList(growable: false),
      selectedChildId: json['selected_child_id'] as String,
      callups: _maps(
        json['child_callups'],
      ).map(PlayerHomeCallup.fromJson).toList(growable: false),
      unreadMessageCount: (json['unread_message_count'] as num?)?.toInt() ?? 0,
      nextEvent: json['next_event'] == null
          ? null
          : LeaderHomeEvent.fromJson(_map(json['next_event'])),
    );
  }
}

class GuardianHomeChild {
  const GuardianHomeChild({
    required this.id,
    required this.displayName,
    required this.relationKind,
  });
  final String id, displayName, relationKind;
  factory GuardianHomeChild.fromJson(Map<String, dynamic> json) =>
      GuardianHomeChild(
        id: json['child_person_id'] as String,
        displayName: json['display_name'] as String,
        relationKind: json['relation_kind'] as String,
      );
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('Invalid projection object.');
}

Iterable<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) throw const FormatException('Invalid projection list.');
  return value.whereType<Map<String, dynamic>>();
}

int homeAttentionPriority(String kind) => switch (kind) {
  'missing_attendance' || 'callup_cancelled' => 10,
  'pending_callups' || 'pending_callup' || 'callup_reminder' || 'callup' => 20,
  'event_today' || 'next_event' || 'event' => 30,
  'unread_message' || 'message' => 40,
  _ => 50,
};

List<T> uniqueHomeAttention<T>(
  Iterable<T> items, {
  required String Function(T item) canonicalKey,
  required int Function(T item) priority,
}) {
  final byKey = <String, T>{};
  for (final item in items) {
    final key = canonicalKey(item);
    final current = byKey[key];
    if (current == null || priority(item) < priority(current)) {
      byKey[key] = item;
    }
  }
  final result = byKey.values.toList(growable: false);
  result.sort((a, b) => priority(a).compareTo(priority(b)));
  return result;
}
