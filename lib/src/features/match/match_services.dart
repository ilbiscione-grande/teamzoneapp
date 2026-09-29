import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/supabase/measured_rpc.dart';
import 'package:teamzone_app/src/features/match/match_models.dart';

abstract interface class MatchServices {
  Future<WrittenMatchReport> getReport(String eventId);
  Future<void> saveReport(
    String commandId,
    String eventId,
    int revision,
    String body,
    bool publish,
  );
  Future<void> registerResult(
    String commandId,
    String eventId, {
    required int expectedRevision,
    required int expectedEventRevision,
    required int scoreUs,
    required int scoreOpponent,
    String? reason,
  });
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
    int minute, {
    String? scorerId,
    String? assistId,
  });
  Future<void> complete(String commandId, String eventId, int minute);
  Future<void> unlock(String commandId, String eventId, String reason);
  Future<void> recordNote(
    String commandId,
    String eventId,
    int minute,
    String text,
  );

  /// Changes minute, scorer/assist or note text of a goal or note. Side and
  /// type are fixed so the derived score cannot drift from its goals.
  Future<void> correctEvent(
    String commandId,
    String factId, {
    required int minute,
    String? scorerId,
    String? assistId,
    String? text,
  });
  Future<void> voidEvent(String commandId, String factId);
  Future<void> adjustScore(
    String commandId,
    String eventId,
    String side,
    int delta,
    int minute,
  );
  Future<void> configurePeriods(
    String commandId,
    String eventId,
    List<int> periodMinutes,
  );
  Future<void> adjustClock(
    String commandId,
    String eventId,
    int elapsedSeconds,
  );
}

class UnconfiguredMatchServices implements MatchServices {
  const UnconfiguredMatchServices();
  @override
  Future<WrittenMatchReport> getReport(String eventId) => _fail();
  @override
  Future<void> saveReport(
    String commandId,
    String eventId,
    int revision,
    String body,
    bool publish,
  ) => _fail();
  @override
  Future<void> registerResult(
    String commandId,
    String eventId, {
    required int expectedRevision,
    required int expectedEventRevision,
    required int scoreUs,
    required int scoreOpponent,
    String? reason,
  }) => _fail();
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
  Future<void> recordGoal(
    String a,
    String b,
    String c,
    int d, {
    String? scorerId,
    String? assistId,
  }) => _fail();
  @override
  Future<void> complete(String a, String b, int c) => _fail();
  @override
  Future<void> unlock(String a, String b, String c) => _fail();
  @override
  Future<void> recordNote(String a, String b, int c, String d) => _fail();
  @override
  Future<void> correctEvent(
    String a,
    String b, {
    required int minute,
    String? scorerId,
    String? assistId,
    String? text,
  }) => _fail();
  @override
  Future<void> voidEvent(String a, String b) => _fail();
  @override
  Future<void> adjustScore(String a, String b, String c, int d, int e) =>
      _fail();
  @override
  Future<void> configurePeriods(String a, String b, List<int> c) => _fail();
  @override
  Future<void> adjustClock(String a, String b, int c) => _fail();
}

class SupabaseMatchServices implements MatchServices {
  SupabaseMatchServices(this._client);
  final SupabaseClient _client;
  @override
  Future<WrittenMatchReport> getReport(String eventId) async {
    final value = await _client
        .schema('api')
        .rpc<Map<String, dynamic>>(
          'get_match_report',
          params: {'p_event_id': eventId},
        );
    return WrittenMatchReport.fromJson(value);
  }

  @override
  Future<void> saveReport(
    String commandId,
    String eventId,
    int revision,
    String body,
    bool publish,
  ) async => measuredRpc(
    _client,
    operation: 'save_match_report',
    params: {
      'p_command_id': commandId,
      'p_event_id': eventId,
      'p_expected_revision': revision,
      'p_body': body,
      'p_publish': publish,
    },
  );
  @override
  Future<void> registerResult(
    String commandId,
    String eventId, {
    required int expectedRevision,
    required int expectedEventRevision,
    required int scoreUs,
    required int scoreOpponent,
    String? reason,
  }) async => measuredRpc(
    _client,
    operation: 'register_match_result',
    params: {
      'p_command_id': commandId,
      'p_event_id': eventId,
      'p_expected_revision': expectedRevision,
      'p_expected_event_revision': expectedEventRevision,
      'p_score_us': scoreUs,
      'p_score_opponent': scoreOpponent,
      'p_reason': reason,
    },
  );
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
    int minute, {
    String? scorerId,
    String? assistId,
  }) async => measuredRpc(
    _client,
    operation: 'record_match_event_v2',
    params: {
      'p_command_id': id,
      'p_event_id': eventId,
      'p_minute': minute,
      'p_type': 'goal',
      'p_side': side,
      'p_player_id': scorerId,
      'p_secondary_player_id': assistId,
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

  Future<void> _command(String name, Map<String, Object?> params) async {
    await _client.schema('api').rpc<Object?>(name, params: params);
  }

  @override
  Future<void> recordNote(String id, String eventId, int minute, String text) =>
      _command('record_match_note_v2', {
        'p_command_id': id,
        'p_event_id': eventId,
        'p_minute': minute,
        'p_text': text,
      });
  @override
  Future<void> correctEvent(
    String id,
    String factId, {
    required int minute,
    String? scorerId,
    String? assistId,
    String? text,
  }) => _command('correct_match_event_v2', {
    'p_command_id': id,
    'p_match_event_id': factId,
    'p_minute': minute,
    'p_player_id': scorerId,
    'p_secondary_player_id': assistId,
    'p_text': text,
  });
  @override
  Future<void> voidEvent(String id, String factId) => _command(
    'void_match_event_v2',
    {'p_command_id': id, 'p_match_event_id': factId},
  );
  @override
  Future<void> adjustScore(
    String id,
    String eventId,
    String side,
    int delta,
    int minute,
  ) => _command('adjust_match_score_v2', {
    'p_command_id': id,
    'p_event_id': eventId,
    'p_side': side,
    'p_delta': delta,
    'p_minute': minute,
  });
  @override
  Future<void> configurePeriods(
    String id,
    String eventId,
    List<int> periodMinutes,
  ) => _command('configure_match_periods_v2', {
    'p_command_id': id,
    'p_event_id': eventId,
    'p_period_minutes': periodMinutes,
  });
  @override
  Future<void> adjustClock(String id, String eventId, int elapsedSeconds) =>
      _command('adjust_match_clock_v2', {
        'p_command_id': id,
        'p_event_id': eventId,
        'p_elapsed_seconds': elapsedSeconds,
      });
}
