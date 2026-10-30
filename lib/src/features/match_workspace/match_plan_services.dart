import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/team_development/team_development_services.dart';
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
  /// Boards on the plan are changed the same way.
  Future<void> changeLink(String linkId, {required bool? visible});

  /// The Tacticsboard projects that may be put on the plan.
  Future<List<TacticsBoardChoice>> listBoardChoices(String eventId);

  /// A board of the project, or the whole project (`boardId` null).
  Future<MatchPlanBoard> addBoard({
    required String eventId,
    required String projectId,
    required String? boardId,
    required bool visible,
  });

  /// The shared view's path for a board on the plan, through a short link
  /// of the asker's own; prefixed with Webtools' address to open.
  Future<String> openBoard(String boardAttachmentId);
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

  /// Decision package 12: whether the match is reported live on the team's
  /// public page, and the match's own choice (null follows the team).
  Future<LiveReporting> getLiveReporting(String eventId);
  Future<LiveReporting> setLiveReporting(String eventId, bool? choice);
}

/// The match's public live reporting: the team's default, the match's own
/// choice (null follows the team), whether the match and team are published,
/// and whether it is reported live now.
class LiveReporting {
  const LiveReporting({
    required this.teamDefault,
    required this.published,
    required this.live,
    this.matchChoice,
  });
  factory LiveReporting.fromJson(Map<String, dynamic> json) => LiveReporting(
    teamDefault: json['team_default'] == true,
    published: json['published'] == true,
    live: json['live'] == true,
    matchChoice: json['match_choice'] as bool?,
  );
  final bool teamDefault, published, live;
  final bool? matchChoice;

  /// Reported live once the match is under way.
  bool get chosen => matchChoice ?? teamDefault;
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
  Future<List<TacticsBoardChoice>> listBoardChoices(String eventId) =>
      Future.error(_error);
  @override
  Future<MatchPlanBoard> addBoard({
    required String eventId,
    required String projectId,
    required String? boardId,
    required bool visible,
  }) => Future.error(_error);
  @override
  Future<String> openBoard(String boardAttachmentId) => Future.error(_error);
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
  @override
  Future<LiveReporting> getLiveReporting(String eventId) =>
      Future.error(_error);
  @override
  Future<LiveReporting> setLiveReporting(String eventId, bool? choice) =>
      Future.error(_error);
}

class SupabaseMatchPlanServices
    implements MatchPlanServices, TeamPlanSuggestionServices {
  SupabaseMatchPlanServices(this._client);
  final SupabaseClient _client;

  @override
  Future<TeamPlanSuggestion?> teamPlanSuggestion(String eventId) =>
      loadTeamPlanSuggestion(_client, eventId);

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
  Future<List<TacticsBoardChoice>> listBoardChoices(String eventId) async {
    final value = await _rpc('list_match_plan_board_choices', {
      'target_event_id': eventId,
    });
    return [
      for (final row in (value as List? ?? const []).whereType<Map>())
        TacticsBoardChoice.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<MatchPlanBoard> addBoard({
    required String eventId,
    required String projectId,
    required String? boardId,
    required bool visible,
  }) async {
    final value = await _rpc('add_match_plan_board', {
      'target_event_id': eventId,
      'target_project_id': projectId,
      'target_board_id': boardId,
      'show_players': visible,
    });
    return MatchPlanBoard.fromJson(Map<String, dynamic>.from(value as Map));
  }

  @override
  Future<String> openBoard(String boardAttachmentId) async =>
      await _rpc('open_match_plan_board', {
            'target_attachment_id': boardAttachmentId,
          })
          as String;

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

  @override
  Future<LiveReporting> getLiveReporting(String eventId) async {
    final value = await _rpc('get_match_live_reporting', {
      'target_event_id': eventId,
    });
    return LiveReporting.fromJson(Map<String, dynamic>.from(value as Map));
  }

  @override
  Future<LiveReporting> setLiveReporting(String eventId, bool? choice) async {
    final value = await _rpc('set_match_live_reporting', {
      'target_event_id': eventId,
      'choice': choice,
    });
    return LiveReporting.fromJson(Map<String, dynamic>.from(value as Map));
  }
}
