import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/supabase/measured_rpc.dart';
import 'package:teamzone_app/src/features/economy/economy_models.dart';

abstract interface class EconomyServices {
  Future<EconomyOverview> getOverview(String clubId);
  Future<void> createAccount({
    required String clubId,
    String? teamId,
    required String name,
    required String idempotencyKey,
  });
  Future<void> createEntry({
    required String clubId,
    required String accountId,
    required int amountMinor,
    required String direction,
    required String category,
    required String reason,
    required String idempotencyKey,
  });
  Future<void> approve({
    required String entryId,
    required String decision,
    required String reason,
    required String idempotencyKey,
  });
  Future<void> post({required String entryId, required String idempotencyKey});
  Future<void> reverse({
    required String entryId,
    required String reason,
    required String idempotencyKey,
  });
}

class UnconfiguredEconomyServices implements EconomyServices {
  const UnconfiguredEconomyServices();
  Future<T> _fail<T>() =>
      Future.error(StateError('Economy backend is not configured.'));
  @override
  Future<EconomyOverview> getOverview(String clubId) => _fail();
  @override
  Future<void> createAccount({
    required String clubId,
    String? teamId,
    required String name,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> createEntry({
    required String clubId,
    required String accountId,
    required int amountMinor,
    required String direction,
    required String category,
    required String reason,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> approve({
    required String entryId,
    required String decision,
    required String reason,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> post({
    required String entryId,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> reverse({
    required String entryId,
    required String reason,
    required String idempotencyKey,
  }) => _fail();
}

class SupabaseEconomyServices implements EconomyServices {
  SupabaseEconomyServices(this._client);
  final SupabaseClient _client;
  Future<Object?> _rpc(String name, Map<String, Object?> params) =>
      _client.schema('api').rpc<Object?>(name, params: params);
  Future<Object?> _command(String name, Map<String, Object?> params) =>
      measuredRpc(_client, operation: name, params: params);
  @override
  Future<EconomyOverview> getOverview(String clubId) async {
    final value = await _rpc('get_economy', {'target_club_id': clubId});
    if (value is! Map) throw const FormatException('Invalid economy response.');
    return EconomyOverview.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> createAccount({
    required String clubId,
    String? teamId,
    required String name,
    required String idempotencyKey,
  }) async => _command('create_economy_account', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'new_name': name,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<void> createEntry({
    required String clubId,
    required String accountId,
    required int amountMinor,
    required String direction,
    required String category,
    required String reason,
    required String idempotencyKey,
  }) async => _command('create_economy_entry', {
    'target_club_id': clubId,
    'target_account_id': accountId,
    'new_amount_minor': amountMinor,
    'new_direction': direction,
    'new_category': category,
    'new_reason': reason,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<void> approve({
    required String entryId,
    required String decision,
    required String reason,
    required String idempotencyKey,
  }) async => _command('approve_economy_entry', {
    'target_entry_id': entryId,
    'new_decision': decision,
    'new_reason': reason,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<void> post({
    required String entryId,
    required String idempotencyKey,
  }) async => _command('post_economy_entry', {
    'target_entry_id': entryId,
    'idempotency_key': idempotencyKey,
  });
  @override
  Future<void> reverse({
    required String entryId,
    required String reason,
    required String idempotencyKey,
  }) async => _command('reverse_economy_entry', {
    'target_entry_id': entryId,
    'new_reason': reason,
    'idempotency_key': idempotencyKey,
  });
}
