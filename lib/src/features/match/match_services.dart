import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/supabase/measured_rpc.dart';
import 'package:teamzone_app/src/features/match/match_models.dart';

abstract interface class MatchServices {
  Future<MatchSnapshot?> getSnapshot(String eventId);
  Future<void> freezeRoster(String commandId, String eventId, String reason);
  Future<void> transition(String commandId, String eventId, String action);
  Future<void> transitionPeriod(
    String commandId,
    String eventId,
    String action,
  );
  Future<void> recordGoal(
    String commandId,
    String eventId,
    String side,
    int minute,
  );
  Future<void> complete(String commandId, String eventId, int minute);
  Future<void> unlock(String commandId, String eventId, String reason);
}

class UnconfiguredMatchServices implements MatchServices {
  const UnconfiguredMatchServices();
  Future<T> _fail<T>() =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<MatchSnapshot?> getSnapshot(String eventId) => _fail();
  @override
  Future<void> freezeRoster(String a, String b, String c) => _fail();
  @override
  Future<void> transition(String a, String b, String c) => _fail();
  @override
  Future<void> transitionPeriod(String a, String b, String c) => _fail();
  @override
  Future<void> recordGoal(String a, String b, String c, int d) => _fail();
  @override
  Future<void> complete(String a, String b, int c) => _fail();
  @override
  Future<void> unlock(String a, String b, String c) => _fail();
}

class SupabaseMatchServices implements MatchServices {
  SupabaseMatchServices(this._client);
  final SupabaseClient _client;
  @override
  Future<MatchSnapshot?> getSnapshot(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('get_match_v2_snapshot', params: {'p_event_id': eventId});
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid match snapshot.');
    }
    return MatchSnapshot.fromJson(value);
  }

  @override
  Future<void> freezeRoster(String id, String eventId, String reason) async =>
      measuredRpc(
        _client,
        operation: 'freeze_match_roster',
        params: {
          'p_command_id': id,
          'p_event_id': eventId,
          'p_reason_code': reason,
        },
      );
  @override
  Future<void> transition(String id, String eventId, String action) async =>
      measuredRpc(
        _client,
        operation: 'transition_match_clock_v2',
        params: {'p_command_id': id, 'p_event_id': eventId, 'p_action': action},
      );
  @override
  Future<void> transitionPeriod(
    String id,
    String eventId,
    String action,
  ) async => measuredRpc(
    _client,
    operation: 'transition_match_period_v2',
    params: {'p_command_id': id, 'p_event_id': eventId, 'p_action': action},
  );
  @override
  Future<void> recordGoal(
    String id,
    String eventId,
    String side,
    int minute,
  ) async => measuredRpc(
    _client,
    operation: 'record_match_event_v2',
    params: {
      'p_command_id': id,
      'p_event_id': eventId,
      'p_minute': minute,
      'p_type': 'goal',
      'p_side': side,
      'p_detail': <String, dynamic>{},
    },
  );
  @override
  Future<void> complete(String id, String eventId, int minute) async =>
      measuredRpc(
        _client,
        operation: 'complete_match_v2',
        params: {'p_command_id': id, 'p_event_id': eventId, 'p_minute': minute},
      );
  @override
  Future<void> unlock(String id, String eventId, String reason) async =>
      measuredRpc(
        _client,
        operation: 'unlock_match_v2',
        params: {'p_command_id': id, 'p_event_id': eventId, 'p_reason': reason},
      );
}
