import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/overview/overview_models.dart';

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
        AssistantTaskStateServices {
  SupabaseOverviewServices(this._client);
  final SupabaseClient _client;
  MainSurfacesProjection? _cached;
  final Map<String, LeaderHomeProjection> _leaderCache = {};
  final Map<String, PlayerHomeProjection> _playerCache = {};
  final Map<String, GuardianHomeProjection> _guardianCache = {};

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
    } catch (_) {
      final cached = _cached;
      if (cached != null) return cached.asStale();
      rethrow;
    }
  }

  @override
  Future<LeaderHomeProjection> loadLeaderHome(String contextId) async {
    try {
      return await loadFreshLeaderHome(contextId);
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
      final cached = _guardianCache[cacheKey];
      if (cached != null) return cached.asStale();
      rethrow;
    }
  }
}
