import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

enum CalendarSyncStatus { connected, reconnecting, disconnected }

class CalendarSyncEvent {
  const CalendarSyncEvent.status(this.status) : invalidated = false;
  const CalendarSyncEvent.invalidation()
    : status = CalendarSyncStatus.connected,
      invalidated = true;

  final CalendarSyncStatus status;
  final bool invalidated;
}

abstract interface class CalendarServices {
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
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
  Future<SquadDetails> getEventSquad(String eventId);
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
  Future<void> recordAttendance({
    required String eventId,
    required List<Map<String, dynamic>> changes,
    String? correctionReason,
    required String idempotencyKey,
  });
  Future<AttendancePermissions> getAttendancePermissions(String eventId);
  Future<String> createEvent(CreateEventInput input, String idempotencyKey);
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

  Stream<CalendarSyncEvent> watchInvalidations({required Set<String> clubIds});
}

class UnconfiguredCalendarServices implements CalendarServices {
  const UnconfiguredCalendarServices();
  StateError get _error => StateError('Supabase is not configured.');
  @override
  Future<String> createEvent(CreateEventInput input, String idempotencyKey) =>
      Future.error(_error);
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
  Future<SquadDetails> getEventSquad(String eventId) => Future.error(_error);
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
  Stream<CalendarSyncEvent> watchInvalidations({
    required Set<String> clubIds,
  }) => const Stream.empty();
}

class SupabaseCalendarServices implements CalendarServices {
  SupabaseCalendarServices(this._client);
  final SupabaseClient _client;
  @override
  Future<List<CalendarEventSummary>> listCalendar({
    required List<String> contextIds,
    required DateTime from,
    required DateTime to,
  }) async {
    final events = <CalendarEventSummary>[];
    String? cursor;
    for (var page = 0; page < 20; page++) {
      final value = await _client
          .schema('api')
          .rpc<Object?>(
            'list_calendar_page',
            params: {
              'context_ids': contextIds,
              'range_start': from.toUtc().toIso8601String(),
              'range_end': to.toUtc().toIso8601String(),
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
      events.addAll(items);
      if (items.length < 200) break;
      cursor = items.last.eventCursor;
      if (cursor == null || cursor.isEmpty) {
        throw const FormatException('Calendar cursor is missing.');
      }
    }
    events.sort((left, right) {
      final time = left.startsAt.compareTo(right.startsAt);
      return time == 0 ? left.id.compareTo(right.id) : time;
    });
    return events;
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
  Future<String> createEvent(
    CreateEventInput input,
    String idempotencyKey,
  ) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'create_event',
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
          'revise_event_v2',
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
      } catch (_) {
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
