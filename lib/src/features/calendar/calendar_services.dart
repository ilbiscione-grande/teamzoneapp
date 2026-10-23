import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/preparation_services.dart';
import 'package:teamzone_app/src/features/calendar/referee_services.dart';
import 'package:teamzone_app/src/features/match_workspace/match_plan_services.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/tournaments/tournaments.dart';

export 'package:teamzone_app/src/features/calendar/preparation_services.dart';
export 'package:teamzone_app/src/features/calendar/referee_services.dart';

enum CalendarSyncStatus { connected, reconnecting, disconnected }

class CalendarSyncEvent {
  const CalendarSyncEvent.status(this.status) : invalidated = false;
  const CalendarSyncEvent.invalidation()
    : status = CalendarSyncStatus.connected,
      invalidated = true;

  final CalendarSyncStatus status;
  final bool invalidated;
}

/// Webtools Bokningshanterare: the bookings attached to an activity.
abstract interface class EventBookingServices {
  Future<List<EventBooking>> listEventBookings(String eventId);

  /// Where you can book for the activity: organisations linked to its club,
  /// with the activity's team you lead there, if any.
  Future<List<({String organizationId, String name, String? teamId})>>
  listEventBookingTargets(String eventId);

  /// Every active resource of the organisation for the time.
  Future<List<ResourceAvailability>> listBookingAvailability({
    required String organizationId,
    required DateTime startsAt,
    required DateTime endsAt,
  });

  /// Books the resources for the time, all or none; how many wait for
  /// approval.
  Future<int> createBookingGroup({
    required List<String> resourceIds,
    required DateTime startsAt,
    required DateTime endsAt,
    String? title,
    String? teamId,
    String? eventId,
  });

  /// Cancels one booking, or every active one in its group.
  Future<void> cancelEventBooking(
    EventBooking booking, {
    bool wholeGroup = false,
  });
}

abstract interface class CalendarServices {
  /// The event's Förberedelser workspace (items, note, files).
  EventPreparationServices get preparation;

  /// The Match module's match plans (decision package 11).
  MatchPlanServices get matchPlans;

  /// REF-01: referees on matches.
  RefereeServices get referees;
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  });
  Future<List<CalendarEventSummary>> listArchivedEvents({
    required List<String> contextIds,
  });
  Future<EventDetails> getEventDetails(String eventId);
  Future<EventSharingSettings> getEventSharing(String eventId);
  Future<int> updateEventSharing({
    required String eventId,
    required List<Map<String, dynamic>> sharedTeams,
    required List<Map<String, dynamic>> audiences,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<List<String>> listSavedLocations({
    required String clubId,
    required String teamId,
  });

  /// Saved places as facility/pitch/surface combinations.
  Future<List<SavedEventPlace>> listSavedPlaces({
    required String clubId,
    required String teamId,
  });
  Future<SquadDetails> getEventSquad(String eventId);
  Future<int> setEventCallupVisibility({
    required String eventId,
    required bool showToMembers,
    required int expectedRevision,
    required String idempotencyKey,
  });

  /// The event back to its team's default for who sees the callups.
  Future<void> clearEventCallupVisibility(String eventId);

  /// Without callups: someone cannot come, or can after all.
  Future<void> reportEventAbsence({
    required String eventId,
    required String personId,
    required String reasonCode,
    String? reasonText,
  });
  Future<void> withdrawEventAbsence({
    required String eventId,
    required String personId,
  });

  /// Whether the team's activities have callups, or everyone is expected
  /// and reports absence.
  Future<({bool callupsRequired, bool canChange})> getTeamEventSettings(
    String teamId,
  );
  Future<int> setTeamEventSettings(String teamId, bool callupsRequired);

  /// The starting line-up; null when not shown to you.
  Future<EventLineup?> getEventLineup(String eventId);
  Future<int> saveEventLineup({
    required String eventId,
    required String? formation,
    required List<({String personId, String? position})> starters,
    required List<String> substitutes,
    required bool published,
    required int expectedRevision,
  });

  /// Whether the team's members see who is called up by default.
  Future<({bool show, bool canChange})> getTeamCallupVisibility(String teamId);
  Future<void> setTeamCallupVisibility(String teamId, bool show);
  Future<List<SquadCandidate>> listSquadCandidates(String eventId);
  Future<void> saveSquadDraft({
    required String eventId,
    required List<String> memberIds,
    required String source,
    Map<String, dynamic> selectionContext = const {},
    int? expectedRevision,
    required String idempotencyKey,
  });
  Future<void> lockSquad({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<void> sendCallups({
    required String squadRevisionId,
    required DateTime expiry,
    required String idempotencyKey,
  });
  Future<void> manageCallup({
    required String callupId,
    required String action,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<void> respondCallup({
    required String callupId,
    required String response,
    String? actingAsPersonId,
    String? declineReasonCode,
    String? declineReasonText,
    required int expectedRevision,
    required String idempotencyKey,
  });

  /// Squad managers' correction of a person's callup, also after the event:
  /// [state] is accepted, declined, pending (no answer) or none (no callup).
  /// Adds a callup someone never got, without notifying anyone. Returns the
  /// callup's new revision (0 when there is none).
  Future<int> correctCallup({
    required String eventId,
    required String personId,
    required String state,
    String? declineReasonCode,
    String? declineReasonText,
    required int expectedRevision,
  });
  Future<void> recordAttendance({
    required String eventId,
    required List<Map<String, dynamic>> changes,
    String? correctionReason,
    required String idempotencyKey,
  });
  Future<AttendancePermissions> getAttendancePermissions(String eventId);
  Future<String> createEvent(CreateEventInput input, String idempotencyKey);

  /// The club's other active teams, offered when creating an event.
  Future<List<ShareableTeam>> listShareableTeams(String teamId);

  /// The team's match format key ("11v11" until set), for a new match's
  /// default length; null when it cannot be read.
  Future<String?> getTeamMatchFormat(String teamId);

  /// Format and periods of a match event (the team default until chosen).
  Future<EventMatchSettings?> getEventMatchSettings(String eventId);

  /// Saves a match's format and periods for [scope] (one, forward, all) of
  /// its series; a match still being planned in match mode follows.
  Future<int> setEventMatchSettings({
    required String eventId,
    required String format,
    required List<int> periodMinutes,
    required String scope,
    required String idempotencyKey,
  });

  /// Shares a just-created event (every occurrence of a new series) with
  /// [teamIds] ("Kan se", same recipients as the owning team).
  Future<int> shareNewEvent({
    required String eventId,
    required List<String> teamIds,
    required String idempotencyKey,
  });
  Future<int> reviseEvent({
    required String eventId,
    required String scope,
    required Map<String, dynamic> patch,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<int> transitionEvent({
    required String eventId,
    required String targetState,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  });
  Future<void> deleteEventDraft({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<int> archiveEvent({
    required String eventId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  });
  Future<int> restoreArchivedEvent({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  });

  Stream<CalendarSyncEvent> watchInvalidations({required Set<String> clubIds});
}

List<({DateTime from, DateTime to})> buildCalendarQueryWindows({
  required DateTime from,
  required DateTime to,
  required Duration maximumWindow,
}) {
  if (!to.isAfter(from)) {
    throw ArgumentError.value(to, 'to', 'Must be after from.');
  }
  if (maximumWindow <= Duration.zero) {
    throw ArgumentError.value(
      maximumWindow,
      'maximumWindow',
      'Must be positive.',
    );
  }
  final windows = <({DateTime from, DateTime to})>[];
  var windowStart = from;
  while (windowStart.isBefore(to)) {
    final candidateEnd = windowStart.add(maximumWindow);
    final windowEnd = candidateEnd.isBefore(to) ? candidateEnd : to;
    windows.add((from: windowStart, to: windowEnd));
    windowStart = windowEnd;
  }
  return windows;
}

class UnconfiguredCalendarServices implements CalendarServices {
  const UnconfiguredCalendarServices();
  StateError get _error => StateError('Supabase is not configured.');
  @override
  EventPreparationServices get preparation =>
      const UnconfiguredEventPreparationServices();
  @override
  MatchPlanServices get matchPlans => const UnconfiguredMatchPlanServices();
  @override
  RefereeServices get referees => const UnconfiguredRefereeServices();
  @override
  Future<String> createEvent(CreateEventInput input, String idempotencyKey) =>
      Future.error(_error);
  @override
  Future<List<ShareableTeam>> listShareableTeams(String teamId) async =>
      const [];
  @override
  Future<String?> getTeamMatchFormat(String teamId) async => null;
  @override
  Future<EventMatchSettings?> getEventMatchSettings(String eventId) async =>
      null;
  @override
  Future<int> setEventMatchSettings({
    required String eventId,
    required String format,
    required List<int> periodMinutes,
    required String scope,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<int> shareNewEvent({
    required String eventId,
    required List<String> teamIds,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<EventDetails> getEventDetails(String eventId) => Future.error(_error);
  @override
  Future<EventSharingSettings> getEventSharing(String eventId) =>
      Future.error(_error);
  @override
  Future<int> updateEventSharing({
    required String eventId,
    required List<Map<String, dynamic>> sharedTeams,
    required List<Map<String, dynamic>> audiences,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<List<String>> listSavedLocations({
    required String clubId,
    required String teamId,
  }) async => const [];
  @override
  Future<List<SavedEventPlace>> listSavedPlaces({
    required String clubId,
    required String teamId,
  }) async => [
    for (final name in await listSavedLocations(clubId: clubId, teamId: teamId))
      SavedEventPlace(name: name),
  ];
  @override
  Future<SquadDetails> getEventSquad(String eventId) => Future.error(_error);
  @override
  Future<int> setEventCallupVisibility({
    required String eventId,
    required bool showToMembers,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<void> clearEventCallupVisibility(String eventId) =>
      Future.error(_error);
  @override
  Future<void> reportEventAbsence({
    required String eventId,
    required String personId,
    required String reasonCode,
    String? reasonText,
  }) => Future.error(_error);
  @override
  Future<void> withdrawEventAbsence({
    required String eventId,
    required String personId,
  }) => Future.error(_error);
  @override
  Future<({bool callupsRequired, bool canChange})> getTeamEventSettings(
    String teamId,
  ) async => (callupsRequired: true, canChange: false);
  @override
  Future<int> setTeamEventSettings(String teamId, bool callupsRequired) =>
      Future.error(_error);
  @override
  Future<EventLineup?> getEventLineup(String eventId) async => null;
  @override
  Future<int> saveEventLineup({
    required String eventId,
    required String? formation,
    required List<({String personId, String? position})> starters,
    required List<String> substitutes,
    required bool published,
    required int expectedRevision,
  }) => Future.error(_error);
  @override
  Future<({bool show, bool canChange})> getTeamCallupVisibility(
    String teamId,
  ) async => (show: false, canChange: false);
  @override
  Future<void> setTeamCallupVisibility(String teamId, bool show) =>
      Future.error(_error);
  @override
  Future<List<SquadCandidate>> listSquadCandidates(String eventId) =>
      Future.error(_error);
  @override
  Future<void> saveSquadDraft({
    required String eventId,
    required List<String> memberIds,
    required String source,
    Map<String, dynamic> selectionContext = const {},
    int? expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<void> lockSquad({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<void> sendCallups({
    required String squadRevisionId,
    required DateTime expiry,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<void> manageCallup({
    required String callupId,
    required String action,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<void> respondCallup({
    required String callupId,
    required String response,
    String? actingAsPersonId,
    String? declineReasonCode,
    String? declineReasonText,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<int> correctCallup({
    required String eventId,
    required String personId,
    required String state,
    String? declineReasonCode,
    String? declineReasonText,
    required int expectedRevision,
  }) => Future.error(_error);
  @override
  Future<void> recordAttendance({
    required String eventId,
    required List<Map<String, dynamic>> changes,
    String? correctionReason,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<AttendancePermissions> getAttendancePermissions(String eventId) =>
      Future.error(_error);
  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async => const [];
  @override
  Future<List<CalendarEventSummary>> listArchivedEvents({
    required List<String> contextIds,
  }) async => const [];
  @override
  Future<int> reviseEvent({
    required String eventId,
    required String scope,
    required Map<String, dynamic> patch,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<int> transitionEvent({
    required String eventId,
    required String targetState,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<void> deleteEventDraft({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<int> archiveEvent({
    required String eventId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) => Future.error(_error);
  @override
  Future<int> restoreArchivedEvent({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  }) => Future.error(_error);

  @override
  Stream<CalendarSyncEvent> watchInvalidations({
    required Set<String> clubIds,
  }) => const Stream.empty();
}

class SupabaseCalendarServices
    implements CalendarServices, EventBookingServices, TournamentServices {
  @override
  String? get accountEmail => _client.auth.currentUser?.email;

  Future<Object?> _tournamentRpc(String name, [Map<String, dynamic>? params]) =>
      _client
          .schema('api')
          .rpc<Object?>(name, params: params)
          .timeout(const Duration(seconds: 15));

  List<T> _tournamentList<T>(
    Object? value,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (value is! List) throw const FormatException('Invalid tournaments.');
    return value
        .whereType<Map<String, dynamic>>()
        .map(parse)
        .toList(growable: false);
  }

  @override
  Future<List<TeamTournament>> listMyTeamTournaments() async => _tournamentList(
    await _tournamentRpc('list_my_team_tournaments'),
    TeamTournament.fromJson,
  );

  @override
  Future<List<LeaderTeam>> listLeaderTeams() async => _tournamentList(
    await _tournamentRpc('list_tournament_leader_teams'),
    LeaderTeam.fromJson,
  );

  @override
  Future<List<FoundTournament>> searchTournaments(String text) async =>
      _tournamentList(
        await _tournamentRpc('search_tournaments', {'search_text': text}),
        FoundTournament.fromJson,
      );

  @override
  Future<void> registerTeam({
    required String classId,
    required String teamId,
    required String teamName,
    required String clubName,
    required String contactName,
    required String contactEmail,
    String? contactPhone,
    String? notes,
  }) async {
    await _tournamentRpc('register_tournament_team_v2', {
      'target_class_id': classId,
      'target_team_id': teamId,
      'registration_team_name': teamName,
      'registration_club_name': clubName,
      'registration_contact_name': contactName,
      'registration_contact_email': contactEmail,
      'registration_contact_phone': contactPhone,
      'registration_notes': notes,
    });
  }

  @override
  Future<({int created, int moved})> syncTeamCalendar(
    String registrationId,
  ) async {
    final value = await _tournamentRpc('sync_tournament_team_calendar', {
      'target_registration_id': registrationId,
    });
    if (value is! Map) throw const FormatException('Invalid sync.');
    return (
      created: (value['created'] as num?)?.toInt() ?? 0,
      moved: (value['moved'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<EventTournament?> getEventTournament(String eventId) async {
    final value = await _tournamentRpc('get_event_tournament', {
      'target_event_id': eventId,
    });
    return value is Map<String, dynamic>
        ? EventTournament.fromJson(value)
        : null;
  }

  @override
  Future<List<ResourceAvailability>> listBookingAvailability({
    required String organizationId,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_booking_availability',
          params: {
            'target_organization_id': organizationId,
            'range_start': startsAt.toUtc().toIso8601String(),
            'range_end': endsAt.toUtc().toIso8601String(),
          },
        )
        .timeout(const Duration(seconds: 15));
    if (value is! List) {
      throw const FormatException('Invalid availability.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(ResourceAvailability.fromJson)
        .toList(growable: false);
  }

  @override
  Future<int> createBookingGroup({
    required List<String> resourceIds,
    required DateTime startsAt,
    required DateTime endsAt,
    String? title,
    String? teamId,
    String? eventId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'create_booking_group',
          params: {
            'target_resource_ids': resourceIds,
            'booking_starts_at': startsAt.toUtc().toIso8601String(),
            'booking_ends_at': endsAt.toUtc().toIso8601String(),
            'booking_title': title,
            'booking_notes': null,
            'target_team_id': teamId,
            'target_event_id': eventId,
            'dry_run': false,
          },
        )
        .timeout(const Duration(seconds: 15));
    if (value is! Map) throw const FormatException('Invalid booking.');
    return (value['pending'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> cancelEventBooking(
    EventBooking booking, {
    bool wholeGroup = false,
  }) async {
    final (name, params) = wholeGroup && booking.groupId != null
        ? ('cancel_booking_group', {'target_group_id': booking.groupId})
        : ('cancel_booking', {'target_booking_id': booking.id});
    await _client
        .schema('api')
        .rpc<Object?>(name, params: params)
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<List<({String organizationId, String name, String? teamId})>>
  listEventBookingTargets(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_event_booking_targets',
          params: {'target_event_id': eventId},
        )
        .timeout(const Duration(seconds: 15));
    if (value is! List) {
      throw const FormatException('Invalid booking targets.');
    }
    return [
      for (final row in value.whereType<Map<String, dynamic>>())
        (
          organizationId: row['organization_id'] as String,
          name: row['name'] as String,
          teamId: row['team_id'] as String?,
        ),
    ];
  }

  @override
  Future<List<EventBooking>> listEventBookings(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_event_bookings',
          params: {'target_event_id': eventId},
        )
        .timeout(const Duration(seconds: 15));
    if (value is! List) throw const FormatException('Invalid event bookings.');
    return value
        .whereType<Map<String, dynamic>>()
        .map(EventBooking.fromJson)
        .toList(growable: false);
  }

  SupabaseCalendarServices(this._client)
    : preparation = SupabaseEventPreparationServices(_client),
      matchPlans = SupabaseMatchPlanServices(_client),
      referees = SupabaseRefereeServices(_client);
  final SupabaseClient _client;
  @override
  final EventPreparationServices preparation;
  @override
  final MatchPlanServices matchPlans;
  @override
  final RefereeServices referees;

  static const _maximumQueryWindow = Duration(days: 399);

  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async {
    final eventsById = <String, CalendarEventSummary>{};
    for (final window in buildCalendarQueryWindows(
      from: from,
      to: to,
      maximumWindow: _maximumQueryWindow,
    )) {
      String? cursor;
      var complete = false;
      for (var page = 0; page < 20; page++) {
        final value = await _client
            .schema('api')
            .rpc<Object?>(
              'list_calendar_page_v2',
              params: {
                'context_ids': contextIds,
                'range_start': window.from.toUtc().toIso8601String(),
                'range_end': window.to.toUtc().toIso8601String(),
                'page_cursor': cursor,
                'page_limit': 200,
              },
            );
        if (value is! List) {
          throw const FormatException('Calendar response is not a list.');
        }
        final items = value
            .whereType<Map<String, dynamic>>()
            .map(CalendarEventSummary.fromJson)
            .toList(growable: false);
        for (final item in items) {
          eventsById[item.id] = item;
        }
        if (items.length < 200) {
          complete = true;
          break;
        }
        cursor = items.last.eventCursor;
        if (cursor == null || cursor.isEmpty) {
          throw const FormatException('Calendar cursor is missing.');
        }
      }
      // More than 20 pages in one window: fail rather than show a calendar
      // with events silently missing.
      if (!complete) {
        throw const FormatException('Calendar window has too many events.');
      }
    }
    final events = eventsById.values.toList(growable: false);
    events.sort((left, right) {
      final time = left.startsAt.compareTo(right.startsAt);
      return time == 0 ? left.id.compareTo(right.id) : time;
    });
    return events;
  }

  @override
  Future<List<CalendarEventSummary>> listArchivedEvents({
    required List<String> contextIds,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_archived_events',
          params: {'context_ids': contextIds, 'page_limit': 200},
        );
    if (value is! List) {
      throw const FormatException('Archived calendar response is not a list.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(CalendarEventSummary.fromJson)
        .toList(growable: false);
  }

  @override
  Future<EventDetails> getEventDetails(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_event_details',
          params: {'target_event_id': eventId},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Event details response is invalid.');
    }
    return EventDetails.fromJson(value);
  }

  @override
  Future<EventSharingSettings> getEventSharing(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_event_sharing',
          params: {'target_event_id': eventId},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Event sharing response is invalid.');
    }
    return EventSharingSettings.fromJson(value);
  }

  @override
  Future<int> updateEventSharing({
    required String eventId,
    required List<Map<String, dynamic>> sharedTeams,
    required List<Map<String, dynamic>> audiences,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'update_event_sharing',
          params: {
            'target_event_id': eventId,
            'shared_teams': sharedTeams,
            'audience_entries': audiences,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Event sharing update is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<List<String>> listSavedLocations({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_saved_event_locations',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! List) {
      throw const FormatException('Saved locations response is invalid.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map((row) => row['location_name'])
        .whereType<String>()
        .toList(growable: false);
  }

  @override
  Future<List<SavedEventPlace>> listSavedPlaces({
    required String clubId,
    required String teamId,
  }) async {
    try {
      final value = await _client
          .schema('api')
          .rpc<Object?>(
            'list_saved_event_places',
            params: {'target_club_id': clubId, 'target_team_id': teamId},
          );
      if (value is! List) {
        throw const FormatException('Saved places response is invalid.');
      }
      return value
          .whereType<Map<String, dynamic>>()
          .map(SavedEventPlace.fromJson)
          .toList(growable: false);
    } catch (error) {
      AppErrors.caught('calendar_services.listSavedPlaces', error);

      // Before the place migration only facility names exist.
      return [
        for (final name in await listSavedLocations(
          clubId: clubId,
          teamId: teamId,
        ))
          SavedEventPlace(name: name),
      ];
    }
  }

  @override
  Future<SquadDetails> getEventSquad(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_event_squad', params: {'target_event_id': eventId});
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid squad response.');
    }
    return SquadDetails.fromJson(value);
  }

  @override
  Future<int> setEventCallupVisibility({
    required String eventId,
    required bool showToMembers,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'set_event_callup_visibility',
          params: {
            'event_id': eventId,
            'show_to_members': showToMembers,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Invalid callup visibility revision.');
    }
    return value.toInt();
  }

  @override
  Future<void> reportEventAbsence({
    required String eventId,
    required String personId,
    required String reasonCode,
    String? reasonText,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'report_event_absence',
          params: {
            'target_event_id': eventId,
            'target_person_id': personId,
            'reason_code': reasonCode,
            'reason_text': reasonText,
          },
        );
  }

  @override
  Future<void> withdrawEventAbsence({
    required String eventId,
    required String personId,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'withdraw_event_absence',
          params: {'target_event_id': eventId, 'target_person_id': personId},
        );
  }

  @override
  Future<({bool callupsRequired, bool canChange})> getTeamEventSettings(
    String teamId,
  ) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_team_event_settings',
          params: {'target_team_id': teamId},
        );
    final map = value is Map ? value : const {};
    return (
      callupsRequired: map['callups_required'] != false,
      canChange: map['can_change'] == true,
    );
  }

  @override
  Future<int> setTeamEventSettings(String teamId, bool callupsRequired) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'set_team_event_settings',
          params: {
            'target_team_id': teamId,
            'callups_required': callupsRequired,
          },
        );
    return (value as num?)?.toInt() ?? 0;
  }

  @override
  Future<EventLineup?> getEventLineup(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_event_lineup', params: {'target_event_id': eventId});
    return value is Map
        ? EventLineup.fromJson(value.cast<String, dynamic>())
        : null;
  }

  @override
  Future<int> saveEventLineup({
    required String eventId,
    required String? formation,
    required List<({String personId, String? position})> starters,
    required List<String> substitutes,
    required bool published,
    required int expectedRevision,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'save_event_lineup',
          params: {
            'target_event_id': eventId,
            'formation': formation,
            'starters': [
              for (final item in starters)
                {
                  'person_id': item.personId,
                  if (item.position != null) 'position': item.position,
                },
            ],
            'substitutes': [
              for (final id in substitutes) {'person_id': id},
            ],
            'published': published,
            'expected_revision': expectedRevision,
          },
        );
    return (value as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> clearEventCallupVisibility(String eventId) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'clear_event_callup_visibility',
          params: {'target_event_id': eventId},
        );
  }

  @override
  Future<({bool show, bool canChange})> getTeamCallupVisibility(
    String teamId,
  ) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_team_callup_visibility',
          params: {'target_team_id': teamId},
        );
    final map = value is Map ? value : const {};
    return (
      show: map['show_to_members'] == true,
      canChange: map['can_change'] == true,
    );
  }

  @override
  Future<void> setTeamCallupVisibility(String teamId, bool show) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'set_team_callup_visibility',
          params: {'target_team_id': teamId, 'show_to_members': show},
        );
  }

  @override
  Future<List<SquadCandidate>> listSquadCandidates(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_squad_candidates',
          params: {'target_event_id': eventId},
        );
    if (value is! List) {
      throw const FormatException('Invalid candidates response.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(SquadCandidate.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> saveSquadDraft({
    required String eventId,
    required List<String> memberIds,
    required String source,
    Map<String, dynamic> selectionContext = const {},
    int? expectedRevision,
    required String idempotencyKey,
  }) async => _client
      .schema('api')
      .rpc<Object?>(
        'save_squad_draft_v2',
        params: {
          'target_event_id': eventId,
          'member_ids': memberIds,
          'selection_source': source,
          'selection_context': selectionContext,
          'expected_revision': expectedRevision,
          'idempotency_key': idempotencyKey,
        },
      );
  @override
  Future<void> lockSquad({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => _client
      .schema('api')
      .rpc<Object?>(
        'lock_squad',
        params: {
          'target_event_id': eventId,
          'expected_revision': expectedRevision,
          'idempotency_key': idempotencyKey,
        },
      );
  @override
  Future<void> sendCallups({
    required String squadRevisionId,
    required DateTime expiry,
    required String idempotencyKey,
  }) async => _client
      .schema('api')
      .rpc<Object?>(
        'send_callups',
        params: {
          'target_squad_revision_id': squadRevisionId,
          'expiry': expiry.toUtc().toIso8601String(),
          'idempotency_key': idempotencyKey,
        },
      );
  @override
  Future<void> manageCallup({
    required String callupId,
    required String action,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => _client
      .schema('api')
      .rpc<Object?>(
        'manage_callup',
        params: {
          'target_callup_id': callupId,
          'action': action,
          'expected_revision': expectedRevision,
          'idempotency_key': idempotencyKey,
        },
      );
  @override
  Future<void> respondCallup({
    required String callupId,
    required String response,
    String? actingAsPersonId,
    String? declineReasonCode,
    String? declineReasonText,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => _client
      .schema('api')
      .rpc<Object?>(
        'respond_callup',
        params: {
          'target_callup_id': callupId,
          'new_response': response,
          'acting_as_person_id': actingAsPersonId,
          'decline_reason_code': declineReasonCode,
          'decline_reason_text': declineReasonText,
          'expected_revision': expectedRevision,
          'idempotency_key': idempotencyKey,
        },
      );
  @override
  Future<int> correctCallup({
    required String eventId,
    required String personId,
    required String state,
    String? declineReasonCode,
    String? declineReasonText,
    required int expectedRevision,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'correct_callup',
          params: {
            'event_id': eventId,
            'person_id': personId,
            'state': state,
            'decline_reason_code': declineReasonCode,
            'decline_reason_text': declineReasonText,
            'expected_revision': expectedRevision,
          },
        );
    if (value is! Map) {
      throw const FormatException('Invalid callup correction.');
    }
    return (value['revision'] as num).toInt();
  }

  @override
  Future<void> recordAttendance({
    required String eventId,
    required List<Map<String, dynamic>> changes,
    String? correctionReason,
    required String idempotencyKey,
  }) async => _client
      .schema('api')
      .rpc<Object?>(
        'record_attendance_v2',
        params: {
          'target_event_id': eventId,
          'changes': changes,
          'correction_reason': correctionReason,
          'idempotency_key': idempotencyKey,
        },
      );

  @override
  Future<AttendancePermissions> getAttendancePermissions(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_attendance_permissions',
          params: {'target_event_id': eventId},
        );
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Attendance permissions are invalid.');
    }
    return AttendancePermissions.fromJson(value);
  }

  @override
  Future<List<ShareableTeam>> listShareableTeams(String teamId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_shareable_teams',
          params: {'target_team_id': teamId},
        );
    if (value is! List) {
      throw const FormatException('Shareable teams response is invalid.');
    }
    return [
      for (final row in value)
        if (row is Map) ShareableTeam.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<EventMatchSettings?> getEventMatchSettings(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_event_match_settings',
          params: {'target_event_id': eventId},
        );
    return value is Map
        ? EventMatchSettings.fromJson(Map<String, dynamic>.from(value))
        : null;
  }

  @override
  Future<int> setEventMatchSettings({
    required String eventId,
    required String format,
    required List<int> periodMinutes,
    required String scope,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'set_event_match_settings',
          params: {
            'target_event_id': eventId,
            'new_format': format,
            'new_period_minutes': periodMinutes,
            'change_scope': scope,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Match settings response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<String?> getTeamMatchFormat(String teamId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_team_match_format',
          params: {'target_team_id': teamId},
        );
    return value is Map ? value['effective'] as String? : null;
  }

  @override
  Future<int> shareNewEvent({
    required String eventId,
    required List<String> teamIds,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'share_new_event',
          params: {
            'target_event_id': eventId,
            'team_ids': teamIds,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Event sharing response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<String> createEvent(
    CreateEventInput input,
    String idempotencyKey,
  ) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'create_event_v2',
          params: {
            'target_club_id': input.clubId,
            'target_team_id': input.teamId,
            'new_title': input.title,
            'new_description': input.description,
            'new_event_type': input.type,
            'new_state': input.state,
            'new_starts_at': input.startsAt.toUtc().toIso8601String(),
            'new_ends_at': input.endsAt.toUtc().toIso8601String(),
            'new_all_day': input.allDay,
            'new_timezone': input.timezone,
            'audience_types': input.audiences,
            'location_name': input.locationName,
            'recurrence_frequency': input.recurrenceFrequency,
            'recurrence_interval': input.recurrenceInterval,
            'recurrence_count': input.recurrenceCount,
            'typed_fields': {
              'assembly_minutes_before': input.assemblyMinutesBefore,
              'training_theme': input.trainingTheme,
              'training_focus': input.trainingFocus,
              'training_plan': input.trainingPlan,
              'opponent_name': input.opponentName,
              'home_away': input.homeAway,
              'match_notes': input.matchNotes,
              'meeting_purpose': input.meetingPurpose,
              'meeting_agenda': input.meetingAgenda,
              'location_pitch': input.locationPitch,
              'location_surface': input.locationSurface,
            },
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! String) throw const FormatException('Invalid event id.');
    return value;
  }

  @override
  Future<int> reviseEvent({
    required String eventId,
    required String scope,
    required Map<String, dynamic> patch,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'revise_event_v3',
          params: {
            'target_event_id': eventId,
            'change_scope': scope,
            'patch': patch,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) throw const FormatException('Invalid revision.');
    return value.toInt();
  }

  @override
  Future<int> transitionEvent({
    required String eventId,
    required String targetState,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'transition_event',
          params: {
            'target_event_id': eventId,
            'target_state': targetState,
            'expected_revision': expectedRevision,
            'reason': reason,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) throw const FormatException('Invalid revision.');
    return value.toInt();
  }

  @override
  Future<void> deleteEventDraft({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => _client
      .schema('api')
      .rpc<Object?>(
        'delete_event_draft',
        params: {
          'target_event_id': eventId,
          'expected_revision': expectedRevision,
          'idempotency_key': idempotencyKey,
        },
      );

  @override
  Future<int> archiveEvent({
    required String eventId,
    required int expectedRevision,
    required String reason,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'archive_event',
          params: {
            'target_event_id': eventId,
            'expected_revision': expectedRevision,
            'reason': reason,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Event archive response is invalid.');
    }
    return value.toInt();
  }

  @override
  Future<int> restoreArchivedEvent({
    required String eventId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'restore_archived_event',
          params: {
            'target_event_id': eventId,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        );
    if (value is! num) {
      throw const FormatException('Event restore response is invalid.');
    }
    return value.toInt();
  }

  @override
  Stream<CalendarSyncEvent> watchInvalidations({required Set<String> clubIds}) {
    final channels = <RealtimeChannel>[];
    final connectedChannels = <RealtimeChannel>{};
    late final StreamController<CalendarSyncEvent> controller;

    Future<void> start() async {
      if (!controller.isClosed) {
        controller.add(
          const CalendarSyncEvent.status(CalendarSyncStatus.reconnecting),
        );
      }
      try {
        await _client.realtime.setAuth(
          _client.auth.currentSession?.accessToken,
        );
        for (final clubId in clubIds) {
          final channel = _client.channel(
            'calendar:club:$clubId',
            opts: const RealtimeChannelConfig(private: true),
          );
          channel
              .onBroadcast(
                event: 'invalidate',
                callback: (_) {
                  if (!controller.isClosed) {
                    controller.add(const CalendarSyncEvent.invalidation());
                  }
                },
              )
              .subscribe((status, _) {
                if (controller.isClosed) return;
                switch (status) {
                  case RealtimeSubscribeStatus.subscribed:
                    connectedChannels.add(channel);
                    if (connectedChannels.length == clubIds.length) {
                      controller.add(
                        const CalendarSyncEvent.status(
                          CalendarSyncStatus.connected,
                        ),
                      );
                    }
                    break;
                  case RealtimeSubscribeStatus.channelError:
                  case RealtimeSubscribeStatus.closed:
                  case RealtimeSubscribeStatus.timedOut:
                    connectedChannels.remove(channel);
                    controller.add(
                      const CalendarSyncEvent.status(
                        CalendarSyncStatus.disconnected,
                      ),
                    );
                    break;
                }
              });
          channels.add(channel);
        }
      } catch (error) {
        AppErrors.caught('calendar_services.start', error);

        if (!controller.isClosed) {
          controller.add(
            const CalendarSyncEvent.status(CalendarSyncStatus.disconnected),
          );
        }
      }
    }

    Future<void> stop() async {
      for (final channel in channels) {
        await _client.removeChannel(channel);
      }
      channels.clear();
      connectedChannels.clear();
    }

    controller = StreamController<CalendarSyncEvent>.broadcast(
      onListen: () => unawaited(start()),
      onCancel: () => unawaited(stop()),
    );
    return controller.stream;
  }
}

/// After [CalendarServices.respondCallup] throws, the write may still have
/// landed server-side — the command is idempotent, but this client never
/// heard back (e.g. a dropped response on a flaky mobile connection).
/// Re-fetches the event's squad and reports whether [callupId] still does
/// NOT show [intendedResponse], so callers only surface a hard "couldn't
/// save" failure when the response genuinely did not take effect. Mirrors
/// the read-back probe messaging already uses for ambiguous send failures.
Future<bool> callupResponseStillMismatched(
  CalendarServices calendar,
  String eventId,
  String callupId,
  String intendedResponse,
) async {
  try {
    final squad = await calendar.getEventSquad(eventId);
    final callup = squad.callups
        .where((callup) => callup.id == callupId)
        .firstOrNull;
    return callup?.state != intendedResponse;
  } catch (error) {
    AppErrors.caught('calendar_services.callupResponseStillMismatched', error);

    return true;
  }
}
