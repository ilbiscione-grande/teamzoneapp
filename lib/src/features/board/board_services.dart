import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/supabase/measured_rpc.dart';
import 'package:teamzone_app/src/features/board/board_models.dart';

abstract interface class BoardServices {
  Future<BoardOverview> getOverview(String clubId);
  Future<void> createChange({
    required String clubId,
    required String assignmentId,
    String? mandateId,
    required String action,
    required String office,
    DateTime? startsAt,
    DateTime? endsAt,
    required String reason,
    required String idempotencyKey,
  });
  Future<void> approve({
    required String changeId,
    required String decision,
    required String reason,
    required String idempotencyKey,
  });
  Future<void> apply({
    required String changeId,
    required String idempotencyKey,
  });
}

class UnconfiguredBoardServices implements BoardServices {
  const UnconfiguredBoardServices();
  Future<T> _fail<T>() =>
      Future.error(StateError('Board backend is not configured.'));
  @override
  Future<BoardOverview> getOverview(String clubId) => _fail();
  @override
  Future<void> createChange({
    required String clubId,
    required String assignmentId,
    String? mandateId,
    required String action,
    required String office,
    DateTime? startsAt,
    DateTime? endsAt,
    required String reason,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> approve({
    required String changeId,
    required String decision,
    required String reason,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> apply({
    required String changeId,
    required String idempotencyKey,
  }) => _fail();
}

class SupabaseBoardServices implements BoardServices {
  SupabaseBoardServices(this._client);
  final SupabaseClient _client;
  Future<Object?> _rpc(String name, Map<String, Object?> params) =>
      _client.schema('api').rpc<Object?>(name, params: params);
  Future<Object?> _command(String name, Map<String, Object?> params) =>
      measuredRpc(_client, operation: name, params: params);
  @override
  Future<BoardOverview> getOverview(String clubId) async {
    final value = await _rpc('get_board', {'target_club_id': clubId});
    if (value is! Map) throw const FormatException('Invalid board response.');
    return BoardOverview.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> createChange({
    required String clubId,
    required String assignmentId,
    String? mandateId,
    required String action,
    required String office,
    DateTime? startsAt,
    DateTime? endsAt,
    required String reason,
    required String idempotencyKey,
  }) async => _command('create_board_mandate_change', {
    'target_club_id': clubId,
    'target_assignment_id': assignmentId,
    'target_mandate_id': mandateId,
    'new_action': action,
    'new_office': office,
    'new_starts_at': startsAt?.toUtc().toIso8601String(),
    'new_ends_at': endsAt?.toUtc().toIso8601String(),
    'new_reason': reason,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<void> approve({
    required String changeId,
    required String decision,
    required String reason,
    required String idempotencyKey,
  }) async => _command('approve_board_mandate_change', {
    'target_change_id': changeId,
    'new_decision': decision,
    'new_reason': reason,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<void> apply({
    required String changeId,
    required String idempotencyKey,
  }) async => _command('apply_board_mandate_change', {
    'target_change_id': changeId,
    'idempotency_key': idempotencyKey,
  });
}
