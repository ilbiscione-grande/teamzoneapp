import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/match_workspace/match_lineup_models.dart';
import 'package:teamzone_app/src/features/match_workspace/match_live_models.dart';
import 'package:teamzone_app/src/features/match_workspace/match_plan_models.dart';

export 'package:teamzone_app/src/features/match_workspace/match_analysis_models.dart';
export 'package:teamzone_app/src/features/match_workspace/match_formations.dart';
export 'package:teamzone_app/src/features/match_workspace/match_lineup_models.dart';
export 'package:teamzone_app/src/features/match_workspace/match_live_models.dart';
export 'package:teamzone_app/src/features/match_workspace/match_plan_models.dart';
export 'package:teamzone_app/src/features/match_workspace/match_report_text.dart';

/// The plan changed elsewhere since it was read.
class MatchPlanConflict implements Exception {
  const MatchPlanConflict();
}

abstract interface class MatchPlanServices {
  /// The plan, or null when a player has nothing published to see.
  /// Throws when the club has no Match module or the event is not a match.
  Future<MatchPlan?> getPlan(String eventId);
  Future<int> savePlan({
    required String eventId,
    required int expectedRevision,
    required String tactics,
    required String setPieces,
    required String opponent,
    required bool showTactics,
    required bool showSetPieces,
    required bool showOpponent,
    required bool published,
  });
  Future<MatchPlanLink> addLink({
    required String eventId,
    required String title,
    required String url,
    required bool visible,
  });

  /// Shown to the players or not; `visible: null` removes the link.
  Future<void> changeLink(String linkId, {required bool? visible});
  Future<List<ModuleMatch>> listMatches({
    required String teamId,
    required DateTime from,
    required DateTime to,
  });

  /// The line-up in the module, or null when a player has nothing
  /// published to see.
  Future<MatchLineup?> getLineup(String eventId);
  Future<int> saveLineup({
    required String eventId,
    required int expectedRevision,
    required String? formation,
    required List<LineupStarter> starters,
    required List<String> substitutes,
    required List<PlannedSubstitution> plan,
    required bool published,
  });

  /// The team's own Live buttons and this leader's Min vy.
  Future<MatchButtons> getButtons(String eventId);
  Future<int> saveButtons(
    String eventId,
    List<MatchButton> buttons,
    int expectedRevision,
  );

  /// The keys to show; null shows every button again.
  Future<void> saveMyView(String eventId, Set<String>? keys);

  /// A tap on an own button: +1 counts, −1 takes the latest back.
  Future<void> recordButton(
    String commandId,
    String eventId,
    String buttonId,
    int delta,
    int minute,
  );
}

class UnconfiguredMatchPlanServices implements MatchPlanServices {
  const UnconfiguredMatchPlanServices();
  StateError get _error => StateError('Supabase is not configured.');
  @override
  Future<MatchPlan?> getPlan(String eventId) => Future.error(_error);
  @override
  Future<int> savePlan({
    required String eventId,
    required int expectedRevision,
    required String tactics,
    required String setPieces,
    required String opponent,
    required bool showTactics,
    required bool showSetPieces,
    required bool showOpponent,
    required bool published,
  }) => Future.error(_error);
  @override
  Future<MatchPlanLink> addLink({
    required String eventId,
    required String title,
    required String url,
    required bool visible,
  }) => Future.error(_error);
  @override
  Future<void> changeLink(String linkId, {required bool? visible}) =>
      Future.error(_error);
  @override
  Future<List<ModuleMatch>> listMatches({
    required String teamId,
    required DateTime from,
    required DateTime to,
  }) => Future.error(_error);
  @override
  Future<MatchLineup?> getLineup(String eventId) => Future.error(_error);
  @override
  Future<int> saveLineup({
    required String eventId,
    required int expectedRevision,
    required String? formation,
    required List<LineupStarter> starters,
    required List<String> substitutes,
    required List<PlannedSubstitution> plan,
    required bool published,
  }) => Future.error(_error);
  @override
  Future<MatchButtons> getButtons(String eventId) => Future.error(_error);
  @override
  Future<int> saveButtons(String a, List<MatchButton> b, int c) =>
      Future.error(_error);
  @override
  Future<void> saveMyView(String a, Set<String>? b) => Future.error(_error);
  @override
  Future<void> recordButton(String a, String b, String c, int d, int e) =>
      Future.error(_error);
}

class SupabaseMatchPlanServices implements MatchPlanServices {
  SupabaseMatchPlanServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, Map<String, Object?> params) =>
      _client.schema('api').rpc<Object?>(name, params: params);

  @override
  Future<MatchPlan?> getPlan(String eventId) async {
    final value = await _rpc('get_match_plan', {'target_event_id': eventId});
    return value is Map<String, dynamic> ? MatchPlan.fromJson(value) : null;
  }

  @override
  Future<int> savePlan({
    required String eventId,
    required int expectedRevision,
    required String tactics,
    required String setPieces,
    required String opponent,
    required bool showTactics,
    required bool showSetPieces,
    required bool showOpponent,
    required bool published,
  }) async {
    try {
      final value = await _rpc('save_match_plan', {
        'target_event_id': eventId,
        'expected_revision': expectedRevision,
        'tactics_text': tactics,
        'set_pieces_text': setPieces,
        'opponent_text': opponent,
        'show_tactics': showTactics,
        'show_set_pieces': showSetPieces,
        'show_opponent': showOpponent,
        'is_published': published,
      });
      return (value as num).toInt();
    } on PostgrestException catch (error) {
      if (error.message.contains('stale_revision')) {
        throw const MatchPlanConflict();
      }
      rethrow;
    }
  }

  @override
  Future<MatchPlanLink> addLink({
    required String eventId,
    required String title,
    required String url,
    required bool visible,
  }) async {
    final value = await _rpc('add_match_plan_link', {
      'target_event_id': eventId,
      'link_title': title,
      'link_url': url,
      'show_players': visible,
    });
    return MatchPlanLink.fromJson(Map<String, dynamic>.from(value as Map));
  }

  @override
  Future<void> changeLink(String linkId, {required bool? visible}) => _rpc(
    'change_match_plan_link',
    {'target_link_id': linkId, 'show_players': visible},
  );

  @override
  Future<List<ModuleMatch>> listMatches({
    required String teamId,
    required DateTime from,
    required DateTime to,
  }) async {
    final value = await _rpc('list_module_matches', {
      'target_team_id': teamId,
      'from_time': from.toUtc().toIso8601String(),
      'to_time': to.toUtc().toIso8601String(),
    });
    return [
      for (final row in (value as List? ?? const []).whereType<Map>())
        ModuleMatch.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<MatchLineup?> getLineup(String eventId) async {
    final value = await _rpc('get_match_lineup', {'target_event_id': eventId});
    return value is Map<String, dynamic> ? MatchLineup.fromJson(value) : null;
  }

  @override
  Future<int> saveLineup({
    required String eventId,
    required int expectedRevision,
    required String? formation,
    required List<LineupStarter> starters,
    required List<String> substitutes,
    required List<PlannedSubstitution> plan,
    required bool published,
  }) async {
    try {
      final value = await _rpc('save_match_lineup', {
        'target_event_id': eventId,
        'expected_revision': expectedRevision,
        'formation': formation,
        'starters': [
          for (final starter in starters)
            {
              'person_id': starter.personId,
              'slot': ?starter.slot,
              'position': ?starter.position,
              'x': ?starter.x,
              'y': ?starter.y,
            },
        ],
        'substitutes': [
          for (final id in substitutes) {'person_id': id},
        ],
        'substitution_plan': [for (final item in plan) item.toJson()],
        'published': published,
      });
      return (value as num).toInt();
    } on PostgrestException catch (error) {
      if (error.message.contains('stale_revision')) {
        throw const MatchPlanConflict();
      }
      rethrow;
    }
  }

  @override
  Future<MatchButtons> getButtons(String eventId) async {
    final value = await _rpc('get_match_buttons', {'target_event_id': eventId});
    return MatchButtons.fromJson(Map<String, dynamic>.from(value as Map));
  }

  @override
  Future<int> saveButtons(
    String eventId,
    List<MatchButton> buttons,
    int expectedRevision,
  ) async {
    try {
      final value = await _rpc('save_match_buttons', {
        'target_event_id': eventId,
        'new_buttons': [for (final button in buttons) button.toJson()],
        'expected_revision': expectedRevision,
      });
      return (value as num).toInt();
    } on PostgrestException catch (error) {
      if (error.message.contains('stale_revision')) {
        throw const MatchPlanConflict();
      }
      rethrow;
    }
  }

  @override
  Future<void> saveMyView(String eventId, Set<String>? keys) => _rpc(
    'save_my_match_view',
    {'target_event_id': eventId, 'shown_keys': keys?.toList()},
  );

  @override
  Future<void> recordButton(
    String commandId,
    String eventId,
    String buttonId,
    int delta,
    int minute,
  ) => _rpc('record_match_button', {
    'p_command_id': commandId,
    'p_event_id': eventId,
    'p_button_id': buttonId,
    'p_delta': delta,
    'p_minute': minute,
  });
}
