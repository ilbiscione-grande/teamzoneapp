import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/leader_groups/leader_group_models.dart';

abstract interface class LeaderGroupServices {
  Future<LeaderGroupsOverview> list(String clubId);

  /// Creates a group when [groupId] is null, otherwise replaces its name,
  /// teams and people. Throws [LeaderGroupException] on a known refusal.
  Future<void> save({
    required String clubId,
    String? groupId,
    required String name,
    required List<String> teamIds,
    required List<String> personIds,
    int? expectedRevision,
  });
  Future<void> archive({
    required String groupId,
    required int expectedRevision,
  });
}

class UnconfiguredLeaderGroupServices implements LeaderGroupServices {
  const UnconfiguredLeaderGroupServices();
  Future<T> _fail<T>() =>
      Future.error(StateError('Leader group backend is not configured.'));
  @override
  Future<LeaderGroupsOverview> list(String clubId) => _fail();
  @override
  Future<void> save({
    required String clubId,
    String? groupId,
    required String name,
    required List<String> teamIds,
    required List<String> personIds,
    int? expectedRevision,
  }) => _fail();
  @override
  Future<void> archive({
    required String groupId,
    required int expectedRevision,
  }) => _fail();
}

class SupabaseLeaderGroupServices implements LeaderGroupServices {
  SupabaseLeaderGroupServices(this._client);
  final SupabaseClient _client;

  static const _known = {
    'name_taken',
    'stale_revision',
    'empty_group',
    'invalid_name',
  };

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    try {
      return await _client.schema('api').rpc<Object?>(name, params: params);
    } on PostgrestException catch (error) {
      if (_known.contains(error.message)) {
        throw LeaderGroupException(error.message);
      }
      rethrow;
    }
  }

  @override
  Future<LeaderGroupsOverview> list(String clubId) async {
    final value = await _rpc('list_leader_groups', {'target_club_id': clubId});
    if (value is! Map) {
      throw const FormatException('Invalid leader group response.');
    }
    return LeaderGroupsOverview.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> save({
    required String clubId,
    String? groupId,
    required String name,
    required List<String> teamIds,
    required List<String> personIds,
    int? expectedRevision,
  }) => _rpc('save_leader_group', {
    'target_club_id': clubId,
    'target_group_id': groupId,
    'group_name': name,
    'team_ids': teamIds,
    'person_ids': personIds,
    'expected_revision': expectedRevision,
  });

  @override
  Future<void> archive({
    required String groupId,
    required int expectedRevision,
  }) => _rpc('archive_leader_group', {
    'target_group_id': groupId,
    'expected_revision': expectedRevision,
  });
}
