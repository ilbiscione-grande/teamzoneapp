import 'dart:math';

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

  /// Books a meeting for the group; returns the new activity's id.
  Future<String> createMeeting({
    required String groupId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? agenda,
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
  @override
  Future<String> createMeeting({
    required String groupId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? agenda,
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
    'no_team',
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

  @override
  Future<String> createMeeting({
    required String groupId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? location,
    String? agenda,
  }) async {
    final value = await _rpc('create_leader_group_meeting', {
      'target_group_id': groupId,
      'new_title': title,
      'new_starts_at': startsAt.toUtc().toIso8601String(),
      'new_ends_at': endsAt.toUtc().toIso8601String(),
      'new_timezone': 'Europe/Stockholm',
      'location_name': location,
      'new_agenda': agenda,
      'idempotency_key': _uuid(),
    });
    if (value is! Map || value['event_id'] == null) {
      throw const FormatException('Invalid meeting response.');
    }
    return '${value['event_id']}';
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
