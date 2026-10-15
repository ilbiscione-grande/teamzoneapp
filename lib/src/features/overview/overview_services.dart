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
