import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';
import '../assistant_coach/assistant_task_feedback.dart';
import '../assistant_coach/assistant_task_preferences.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';

abstract interface class OverviewServices {
  Future<MainSurfacesProjection> load({required List<String> contextIds});
  Future<LeaderHomeProjection> loadLeaderHome(String contextId);
  Future<PlayerHomeProjection> loadPlayerHome(String contextId);
  Future<GuardianHomeProjection> loadGuardianHome(
    String contextId, {
    String? childPersonId,
  });
}

/// Actions must not use a cached projection after authorization was revoked.
/// UX review: the Home of a club context without a team.
abstract interface class ClubHomeServices {
  Future<ClubHome> loadClubHome(String contextId);
}

/// Kontrollfrågor om domaren: the matches you manage whose referee
/// coordinator asks whether the referee refereed, one per match.
abstract interface class RefereeControlServices {
  Future<List<RefereeControlQuestion>> listMyRefereeControlQuestions();
}

class RefereeControlQuestion {
  const RefereeControlQuestion({
    required this.eventId,
    required this.clubId,
    required this.teamId,
    required this.title,
    required this.count,
    required this.name,
  });
  factory RefereeControlQuestion.fromJson(Map<String, dynamic> json) =>
      RefereeControlQuestion(
        eventId: json['event_id'] as String,
        clubId: json['club_id'] as String,
        teamId: json['team_id'] as String?,
        title: json['title'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 1,
        name: json['name'] as String? ?? '',
      );
  final String eventId, clubId, title, name;
  final String? teamId;
  final int count;
}

/// Ansökningar om lagsida: pending requests per club where you decide them,
/// keyed by club id.
abstract interface class TeamPageRequestServices {
  Future<Map<String, int>> listMyTeamPageRequests();
}

/// Webtools Bokningshanterare: the bookings waiting for your approval.
abstract interface class BookingApprovalServices {
  Future<List<BookingApproval>> listMyBookingApprovals();
}

/// Webtools Bokningshanterare: approve or decline the waiting bookings in
/// the app.
abstract interface class BookingDecisionServices {
  Future<List<PendingBooking>> listPendingBookings(String organizationId);

  /// Decides the booking, or its whole series or group.
  Future<void> decideBooking(PendingBooking booking, {required bool approve});
}

abstract interface class FreshLeaderOverviewServices {
  Future<LeaderHomeProjection> loadFreshLeaderHome(String contextId);
}

abstract interface class AssistantTaskStateServices {
  Future<void> setAssistantTaskState({
    required String contextId,
    required String kind,
    required String route,
    required String status,
    int? snoozeMinutes,
  });
}

abstract interface class PersonalCalendarConflictServices {
  Future<Map<String, dynamic>> loadPersonalCalendarConflicts();
}

class UnconfiguredOverviewServices implements OverviewServices {
  const UnconfiguredOverviewServices();
  @override
  Future<MainSurfacesProjection> load({required List<String> contextIds}) =>
      Future.error(StateError('Overview backend is not configured.'));
  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) =>
      Future.error(StateError('Overview backend is not configured.'));
  @override
  Future<PlayerHomeProjection> loadPlayerHome(String contextId) =>
      Future.error(StateError('Overview backend is not configured.'));
  @override
  Future<GuardianHomeProjection> loadGuardianHome(
    String contextId, {
    String? childPersonId,
  }) => Future.error(StateError('Overview backend is not configured.'));
}

class SupabaseOverviewServices
    implements
        OverviewServices,
        ClubHomeServices,
        BookingApprovalServices,
        BookingDecisionServices,
        TeamPageRequestServices,
        RefereeControlServices,
        FreshLeaderOverviewServices,
        PersonalCalendarConflictServices,
        AssistantTaskPreferencesServices,
        AssistantTaskStateServices,
        AssistantTaskFeedbackServices,
        AssistantTaskSupportServices {
  SupabaseOverviewServices(this._client);
  final SupabaseClient _client;
  MainSurfacesProjection? _cached;
  final Map<String, LeaderHomeProjection> _leaderCache = {};
  final Map<String, PlayerHomeProjection> _playerCache = {};
  final Map<String, GuardianHomeProjection> _guardianCache = {};

  @override
  Future<AssistantTaskPreferences> loadAssistantTaskPreferences() async =>
      AssistantTaskPreferences.fromJson(
        Map<String, dynamic>.from(
          await _client.schema('api').rpc('get_assistant_task_preferences')
              as Map,
        ),
      );

  @override
  Future<AssistantTaskPreferences> saveAssistantTaskPreferences(
    Set<String> hiddenKinds,
    int expectedRevision, {
    bool currentTeamOnly = false,
    bool welcomeMessageVisible = true,
  }) async => AssistantTaskPreferences.fromJson(
    Map<String, dynamic>.from(
      await _client
              .schema('api')
              .rpc(
                'set_assistant_task_preferences_v3',
                params: {
                  'hidden_kinds': hiddenKinds.toList()..sort(),
                  'expected_revision': expectedRevision,
                  'current_team_only': currentTeamOnly,
                  'welcome_message_visible': welcomeMessageVisible,
                },
              )
          as Map,
    ),
  );

  @override
  Future<bool> giveAssistantTaskFeedback({
    required String contextId,
    required String kind,
    required String route,
    required String reason,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'give_assistant_task_feedback',
          params: {
            'context_id': contextId,
            'task_kind': kind,
            'task_route': route,
            'feedback_reason': reason,
          },
        );
    return value is Map && value['offer_hide'] == true;
  }

  @override
  Future<List<AssistantTaskKindStatus>> listAssistantTaskKinds() async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('list_assistant_task_kinds_for_support');
    return [
      if (value is List)
        for (final row in value.whereType<Map<String, dynamic>>())
          AssistantTaskKindStatus.fromJson(row),
    ];
  }

  @override
  Future<void> setAssistantTaskKindSwitch({
    required String kind,
    required bool disabled,
    required String reason,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'set_assistant_task_kind_switch',
          params: {
            'task_kind': kind,
            'disable': disabled,
            'change_reason': reason,
          },
        );
  }

  @override
  Future<Map<String, dynamic>> loadPersonalCalendarConflicts() async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_personal_calendar_conflicts');
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid personal conflicts');
    }
    return value;
  }

  @override
  Future<void> setAssistantTaskState({
    required String contextId,
    required String kind,
    required String route,
    required String status,
    int? snoozeMinutes,
  }) async {
    await _client
        .schema('api')
        .rpc(
          'set_assistant_task_state',
          params: {
            'context_id': contextId,
            'task_kind': kind,
            'task_route': route,
            'new_status': status,
            'snooze_minutes': snoozeMinutes,
          },
        );
  }

  @override
  Future<MainSurfacesProjection> load({
    required List<String> contextIds,
  }) async {
    try {
      final value = await _client
          .schema('api')
          .rpc<Object?>(
            'get_main_surfaces',
            params: {'context_ids': contextIds.toSet().toList()},
          );
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid overview response.');
      }
      return _cached = MainSurfacesProjection.fromJson(value);
    } catch (error) {
      AppErrors.caught('overview_services.load', error);

      final cached = _cached;
      if (cached != null) return cached.asStale();
      rethrow;
    }
  }

  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async {
    try {
      return await loadFreshLeaderHome(contextId);
    } catch (error) {
      AppErrors.caught('overview_services.loadLeaderHome', error);

      final cached = _leaderCache[contextId];
      if (cached != null) return cached.asStale();
      rethrow;
    }
  }

  @override
  Future<LeaderHomeProjection> loadFreshLeaderHome(String contextId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_leader_home', params: {'context_id': contextId});
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid leader home response.');
    }
    return _leaderCache[contextId] = LeaderHomeProjection.fromJson(value);
  }

  @override
  Future<PlayerHomeProjection> loadPlayerHome(String contextId) async {
    try {
      final value = await _client
          .schema('api')
          .rpc<Object?>('get_player_home', params: {'context_id': contextId});
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid player home response.');
      }
      return _playerCache[contextId] = PlayerHomeProjection.fromJson(value);
    } catch (error) {
      AppErrors.caught('overview_services.loadPlayerHome', error);

      final cached = _playerCache[contextId];
      if (cached != null) return cached.asStale();
      rethrow;
    }
  }

  @override
  Future<List<BookingApproval>> listMyBookingApprovals() async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('list_my_booking_approvals')
        .timeout(const Duration(seconds: 15));
    if (value is! List) {
      throw const FormatException('Invalid booking approvals.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(BookingApproval.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<RefereeControlQuestion>> listMyRefereeControlQuestions() async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('list_my_referee_control_questions')
        .timeout(const Duration(seconds: 15));
    if (value is! List) {
      throw const FormatException('Invalid referee control questions.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(RefereeControlQuestion.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Map<String, int>> listMyTeamPageRequests() async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('list_my_team_page_requests')
        .timeout(const Duration(seconds: 15));
    if (value is! List) {
      throw const FormatException('Invalid team page requests.');
    }
    return {
      for (final row in value.whereType<Map<String, dynamic>>())
        row['club_id'] as String: (row['pending'] as num?)?.toInt() ?? 0,
    };
  }

  @override
  Future<List<PendingBooking>> listPendingBookings(
    String organizationId,
  ) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_pending_bookings',
          params: {'target_organization_id': organizationId},
        )
        .timeout(const Duration(seconds: 15));
    if (value is! List) {
      throw const FormatException('Invalid pending bookings.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(PendingBooking.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> decideBooking(
    PendingBooking booking, {
    required bool approve,
  }) async {
    final (name, params) = booking.seriesId != null
        ? ('decide_booking_series', {'target_series_id': booking.seriesId})
        : booking.groupId != null
        ? ('decide_booking_group', {'target_group_id': booking.groupId})
        : ('decide_booking', {'target_booking_id': booking.id});
    await _client
        .schema('api')
        .rpc<Object?>(name, params: {...params, 'approve': approve})
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<ClubHome> loadClubHome(String contextId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_club_home', params: {'target_context_id': contextId})
        .timeout(const Duration(seconds: 15));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid club home.');
    }
    return ClubHome.fromJson(value);
  }

  @override
  Future<GuardianHomeProjection> loadGuardianHome(
    String contextId, {
    String? childPersonId,
  }) async {
    final cacheKey = '$contextId:${childPersonId ?? 'default'}';
    try {
      final value = await _client
          .schema('api')
          .rpc<Object?>(
            'get_guardian_home',
            params: {'context_id': contextId, 'child_person_id': childPersonId},
          );
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid guardian home response.');
      }
      return _guardianCache[cacheKey] = GuardianHomeProjection.fromJson(value);
    } catch (error) {
      AppErrors.caught('overview_services.loadGuardianHome', error);

      final cached = _guardianCache[cacheKey];
      if (cached != null) return cached.asStale();
      rethrow;
    }
  }
}
