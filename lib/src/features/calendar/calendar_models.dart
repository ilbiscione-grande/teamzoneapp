class CalendarEventSummary {
  const CalendarEventSummary({
    required this.id,
    required this.clubId,
    required this.owningTeamId,
    required this.teamName,
    required this.title,
    required this.type,
    required this.state,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.timezone,
    required this.revision,
    this.locationName,
    this.eventCursor,
  });
  final String id, clubId, owningTeamId, teamName, title, type, state, timezone;
  final DateTime startsAt, endsAt;
  final bool allDay;
  final String? locationName;
  final String? eventCursor;
  final int revision;
  factory CalendarEventSummary.fromJson(Map<String, dynamic> json) =>
      CalendarEventSummary(
        id: json['event_id'] as String,
        clubId: json['club_id'] as String,
        owningTeamId: json['owning_team_id'] as String,
        teamName: json['team_name'] as String,
        title: json['title'] as String,
        type: json['event_type'] as String,
        state: json['state'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
        allDay: json['all_day'] as bool? ?? false,
        timezone: json['timezone'] as String,
        locationName: json['location_name'] as String?,
        eventCursor: json['event_cursor'] as String?,
        revision: (json['revision'] as num).toInt(),
      );
}

enum CalendarViewMode { agenda, month, week, day }

/// Actions that are implemented and may be exposed from EventDetails today.
///
/// Later planning features are deliberately not represented here until their
/// data contract and complete user flow exist. This keeps the core UI free of
/// placeholders while giving future additions one explicit integration point.
enum EventPreparationAction { matchSpace, participants, editEvent }

class CalendarProjection {
  const CalendarProjection({
    required this.events,
    required this.mode,
    required this.selectedDate,
    this.teamId,
    this.eventType,
  });
  final List<CalendarEventSummary> events;
  final CalendarViewMode mode;
  final DateTime selectedDate;
  final String? teamId, eventType;

  DateTime get dayStart =>
      DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
  DateTime get weekStart =>
      dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
  DateTime get rangeStart => switch (mode) {
    CalendarViewMode.agenda || CalendarViewMode.day => dayStart,
    CalendarViewMode.week => weekStart,
    CalendarViewMode.month => DateTime(selectedDate.year, selectedDate.month),
  };
  DateTime? get rangeEnd => switch (mode) {
    CalendarViewMode.agenda => null,
    CalendarViewMode.day => dayStart.add(const Duration(days: 1)),
    CalendarViewMode.week => weekStart.add(const Duration(days: 7)),
    CalendarViewMode.month => DateTime(
      selectedDate.year,
      selectedDate.month + 1,
    ),
  };

  List<CalendarEventSummary> get visibleEvents {
    final result = events
        .where((event) {
          if (teamId != null && event.owningTeamId != teamId) return false;
          if (eventType != null && event.type != eventType) return false;
          final localStart = event.startsAt.toLocal();
          final localEnd = event.endsAt.toLocal();
          if (mode == CalendarViewMode.agenda) {
            return localEnd.isAfter(rangeStart);
          }
          return localEnd.isAfter(rangeStart) && localStart.isBefore(rangeEnd!);
        })
        .toList(growable: false);
    return result..sort((left, right) {
      final time = left.startsAt.compareTo(right.startsAt);
      return time == 0 ? left.id.compareTo(right.id) : time;
    });
  }

  List<CalendarEventSummary> eventsOn(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return visibleEvents
        .where(
          (event) =>
              event.endsAt.toLocal().isAfter(start) &&
              event.startsAt.toLocal().isBefore(end),
        )
        .toList(growable: false);
  }
}

class EventDetails {
  const EventDetails({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.state,
    required this.startsAt,
    required this.endsAt,
    required this.allDay,
    required this.timezone,
    required this.revision,
    required this.callerActions,
    required this.teams,
    required this.audiences,
    this.locationName,
    this.recurrenceId,
    this.archivedAt,
    this.archiveReason,
  });
  final String id, title, type, state, timezone;
  final String? description, locationName;
  final String? recurrenceId;
  final DateTime? archivedAt;
  final String? archiveReason;
  final DateTime startsAt, endsAt;
  final bool allDay;
  final int revision;
  final Set<String> callerActions;
  final List<Map<String, dynamic>> teams, audiences;
  bool can(String action) => callerActions.contains(action);

  Set<EventPreparationAction> get preparationActions => {
    if (type == 'match') EventPreparationAction.matchSpace,
    if (can('manage_roster')) EventPreparationAction.participants,
    if (can('revise')) EventPreparationAction.editEvent,
  };
  factory EventDetails.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    return EventDetails(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      type: json['event_type'] as String,
      state: json['state'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      allDay: json['all_day'] as bool? ?? false,
      timezone: json['timezone'] as String,
      revision: (json['revision'] as num).toInt(),
      callerActions: (json['caller_actions'] as List? ?? const [])
          .whereType<String>()
          .toSet(),
      teams: (json['teams'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
      audiences: (json['audiences'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
      locationName: location is Map<String, dynamic>
          ? location['name'] as String?
          : null,
      recurrenceId: json['recurrence_id'] as String?,
      archivedAt: json['archived_at'] == null
          ? null
          : DateTime.parse(json['archived_at'] as String),
      archiveReason: json['archive_reason'] as String?,
    );
  }
}

class EventSharingTeam {
  const EventSharingTeam({
    required this.teamId,
    required this.name,
    required this.selected,
    required this.capabilities,
  });
  final String teamId, name;
  final bool selected;
  final Set<String> capabilities;
  factory EventSharingTeam.fromJson(Map<String, dynamic> json) =>
      EventSharingTeam(
        teamId: json['team_id'] as String,
        name: json['name'] as String,
        selected: json['selected'] as bool? ?? false,
        capabilities: (json['capabilities'] as List? ?? const [])
            .whereType<String>()
            .toSet(),
      );
}

class EventSharingSettings {
  const EventSharingSettings({
    required this.eventId,
    required this.revision,
    required this.teams,
    required this.audiences,
  });
  final String eventId;
  final int revision;
  final List<EventSharingTeam> teams;
  final List<Map<String, dynamic>> audiences;
  factory EventSharingSettings.fromJson(Map<String, dynamic> json) =>
      EventSharingSettings(
        eventId: json['event_id'] as String,
        revision: (json['revision'] as num).toInt(),
        teams: (json['teams'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EventSharingTeam.fromJson)
            .toList(growable: false),
        audiences: (json['audiences'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false),
      );
}

class CreateEventInput {
  const CreateEventInput({
    required this.clubId,
    required this.teamId,
    required this.title,
    required this.type,
    required this.startsAt,
    required this.endsAt,
    required this.timezone,
    this.description,
    this.locationName,
    this.state = 'scheduled',
    this.allDay = false,
    this.audiences = const ['players', 'leaders'],
    this.recurrenceFrequency,
    this.recurrenceInterval,
    this.recurrenceCount,
  });
  final String clubId, teamId, title, type, state, timezone;
  final String? description, locationName, recurrenceFrequency;
  final DateTime startsAt, endsAt;
  final bool allDay;
  final List<String> audiences;
  final int? recurrenceInterval, recurrenceCount;
}

class SquadMemberView {
  const SquadMemberView({
    required this.personId,
    required this.name,
    required this.state,
    required this.source,
  });
  final String personId, name, state, source;
  factory SquadMemberView.fromJson(Map<String, dynamic> json) =>
      SquadMemberView(
        personId: json['person_id'] as String,
        name: json['name'] as String,
        state: json['selection_state'] as String? ?? 'selected',
        source: json['source'] as String? ?? 'manual',
      );
}

class CallupView {
  const CallupView({
    required this.id,
    required this.personId,
    required this.name,
    required this.state,
    required this.deliveryState,
    required this.revision,
    required this.canRespond,
    required this.reminderCount,
    this.actingAsPersonId,
    this.responseRole,
    this.lastRemindedAt,
    this.reminderDeliveryState,
  });
  final String id, personId, name, state, deliveryState;
  final int revision;
  final int reminderCount;
  final bool canRespond;
  final String? actingAsPersonId, responseRole, reminderDeliveryState;
  final DateTime? lastRemindedAt;
  factory CallupView.fromJson(Map<String, dynamic> json) => CallupView(
    id: json['callup_id'] as String,
    personId: json['person_id'] as String,
    name: json['name'] as String,
    state: json['state'] as String,
    deliveryState: json['delivery_state'] as String? ?? 'pending',
    revision: (json['revision'] as num).toInt(),
    canRespond: json['can_respond'] as bool? ?? false,
    reminderCount: (json['reminder_count'] as num? ?? 0).toInt(),
    actingAsPersonId: json['acting_as_person_id'] as String?,
    responseRole: json['response_role'] as String?,
    lastRemindedAt: json['last_reminded_at'] == null
        ? null
        : DateTime.parse(json['last_reminded_at'] as String),
    reminderDeliveryState: json['reminder_delivery_state'] as String?,
  );
}

class AttendanceView {
  const AttendanceView({
    required this.personId,
    required this.name,
    required this.status,
    required this.revision,
    this.minutes,
  });
  final String personId, name, status;
  final int revision;
  final int? minutes;
  factory AttendanceView.fromJson(Map<String, dynamic> json) => AttendanceView(
    personId: json['person_id'] as String,
    name: json['name'] as String,
    status: json['status'] as String? ?? 'unknown',
    revision: (json['revision'] as num? ?? 0).toInt(),
    minutes: (json['minutes'] as num?)?.toInt(),
  );
}

class AttendancePermissions {
  const AttendancePermissions({
    required this.lateWindow,
    required this.canRecord,
    required this.canCorrectLate,
  });
  final bool lateWindow, canRecord, canCorrectLate;
  factory AttendancePermissions.fromJson(Map<String, dynamic> json) =>
      AttendancePermissions(
        lateWindow: json['late_window'] as bool? ?? false,
        canRecord: json['can_record'] as bool? ?? false,
        canCorrectLate: json['can_correct_late'] as bool? ?? false,
      );
}

class SquadDetails {
  const SquadDetails({
    required this.eventId,
    required this.state,
    required this.members,
    required this.callups,
    required this.attendance,
    required this.callerActions,
    required this.selectionSource,
    required this.selectionContext,
    required this.dispatchKind,
    this.showCallupsToMembers = false,
    this.callupVisibilityRevision = 0,
    this.squadRevisionId,
    this.revision,
  });
  final String eventId, state;
  final String? squadRevisionId;
  final int? revision;
  final List<SquadMemberView> members;
  final List<CallupView> callups;
  final List<AttendanceView> attendance;
  final Set<String> callerActions;
  final String selectionSource, dispatchKind;
  final Map<String, dynamic> selectionContext;
  final bool showCallupsToMembers;
  final int callupVisibilityRevision;
  bool can(String action) => callerActions.contains(action);
  factory SquadDetails.fromJson(Map<String, dynamic> json) => SquadDetails(
    eventId: json['event_id'] as String,
    state: json['squad_state'] as String? ?? 'empty',
    squadRevisionId: json['squad_revision_id'] as String?,
    revision: (json['squad_revision'] as num?)?.toInt(),
    members: (json['members'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SquadMemberView.fromJson)
        .toList(growable: false),
    callups: (json['callups'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CallupView.fromJson)
        .toList(growable: false),
    attendance: (json['attendance'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AttendanceView.fromJson)
        .toList(growable: false),
    callerActions: (json['caller_actions'] as List? ?? const [])
        .whereType<String>()
        .toSet(),
    selectionSource: json['selection_source'] as String? ?? 'manual',
    selectionContext:
        json['selection_context'] as Map<String, dynamic>? ?? const {},
    dispatchKind: json['dispatch_kind'] as String? ?? 'initial',
    showCallupsToMembers: json['show_callups_to_members'] as bool? ?? false,
    callupVisibilityRevision:
        (json['callup_visibility_revision'] as num?)?.toInt() ?? 0,
  );
}

class SquadCandidate {
  const SquadCandidate({
    required this.personId,
    required this.name,
    required this.eligibilityKind,
  });
  final String personId, name, eligibilityKind;
  factory SquadCandidate.fromJson(Map<String, dynamic> json) => SquadCandidate(
    personId: json['person_id'] as String,
    name: json['name'] as String,
    eligibilityKind: json['eligibility_kind'] as String? ?? 'team_assignment',
  );
}
