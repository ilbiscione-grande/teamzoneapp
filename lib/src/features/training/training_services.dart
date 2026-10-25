import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/team_development/team_development_services.dart';
import 'package:teamzone_app/src/features/training/training_models.dart';

export 'package:teamzone_app/src/features/training/training_models.dart';

/// The session changed elsewhere since it was read.
class TrainingSessionConflict implements Exception {
  const TrainingSessionConflict();
}

abstract interface class TrainingServices {
  /// The session, or null when a player has nothing published to see.
  /// Throws when the club has no Training module or it is not a training.
  Future<TrainingSession?> getSession(String eventId);

  /// Saves the whole session on [expectedRevision] (0 for a new one) and
  /// returns it as saved.
  Future<TrainingSession> saveSession({
    required String eventId,
    required int expectedRevision,
    required String theme,
    required String goal,
    required bool published,
    required List<TrainingBlock> blocks,
  });
  Future<List<ModuleTraining>> listTrainings({
    required String teamId,
    required DateTime from,
    required DateTime to,
  });

  /// The leaders' evaluation after the session (step 3).
  Future<TrainingEvaluation> getEvaluation(String eventId);

  /// Saves the evaluation on [expectedRevision] (0 for a new one).
  Future<TrainingEvaluation> saveEvaluation({
    required String eventId,
    required int expectedRevision,
    int? rating,
    GoalReached? goalReached,
    required String wentWell,
    required String doDifferently,
    required String nextTime,
    required List<EvaluatedBlock> blocks,
  });
}

class UnconfiguredTrainingServices implements TrainingServices {
  const UnconfiguredTrainingServices();
  StateError get _error => StateError('Supabase is not configured.');
  @override
  Future<TrainingSession?> getSession(String eventId) => Future.error(_error);
  @override
  Future<TrainingSession> saveSession({
    required String eventId,
    required int expectedRevision,
    required String theme,
    required String goal,
    required bool published,
    required List<TrainingBlock> blocks,
  }) => Future.error(_error);
  @override
  Future<List<ModuleTraining>> listTrainings({
    required String teamId,
    required DateTime from,
    required DateTime to,
  }) => Future.error(_error);
  @override
  Future<TrainingEvaluation> getEvaluation(String eventId) =>
      Future.error(_error);
  @override
  Future<TrainingEvaluation> saveEvaluation({
    required String eventId,
    required int expectedRevision,
    int? rating,
    GoalReached? goalReached,
    required String wentWell,
    required String doDifferently,
    required String nextTime,
    required List<EvaluatedBlock> blocks,
  }) => Future.error(_error);
}

class SupabaseTrainingServices
    implements TrainingServices, TeamPlanSuggestionServices {
  SupabaseTrainingServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, Map<String, Object?> params) => _client
      .schema('api')
      .rpc<Object?>(name, params: params)
      .timeout(const Duration(seconds: 15));

  @override
  Future<TeamPlanSuggestion?> teamPlanSuggestion(String eventId) =>
      loadTeamPlanSuggestion(_client, eventId);

  @override
  Future<TrainingSession?> getSession(String eventId) async {
    final value = await _rpc('get_training_session', {
      'target_event_id': eventId,
    });
    return value is Map<String, dynamic>
        ? TrainingSession.fromJson(value)
        : null;
  }

  @override
  Future<TrainingSession> saveSession({
    required String eventId,
    required int expectedRevision,
    required String theme,
    required String goal,
    required bool published,
    required List<TrainingBlock> blocks,
  }) async {
    try {
      final value = await _rpc('save_training_session', {
        'target_event_id': eventId,
        'expected_revision': expectedRevision,
        'session_theme': theme,
        'session_goal': goal,
        'is_published': published,
        'session_blocks': [for (final block in blocks) block.toJson()],
      });
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid training session.');
      }
      return TrainingSession.fromJson(value);
    } on PostgrestException catch (error) {
      if (error.message.contains('stale_revision')) {
        throw const TrainingSessionConflict();
      }
      rethrow;
    }
  }

  @override
  Future<List<ModuleTraining>> listTrainings({
    required String teamId,
    required DateTime from,
    required DateTime to,
  }) async {
    final value = await _rpc('list_module_trainings', {
      'target_team_id': teamId,
      'from_time': from.toUtc().toIso8601String(),
      'to_time': to.toUtc().toIso8601String(),
    });
    if (value is! List) {
      throw const FormatException('Invalid trainings.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(ModuleTraining.fromJson)
        .toList(growable: false);
  }

  @override
  Future<TrainingEvaluation> getEvaluation(String eventId) async {
    final value = await _rpc('get_training_evaluation', {
      'target_event_id': eventId,
    });
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid training evaluation.');
    }
    return TrainingEvaluation.fromJson(value);
  }

  @override
  Future<TrainingEvaluation> saveEvaluation({
    required String eventId,
    required int expectedRevision,
    int? rating,
    GoalReached? goalReached,
    required String wentWell,
    required String doDifferently,
    required String nextTime,
    required List<EvaluatedBlock> blocks,
  }) async {
    try {
      final value = await _rpc('save_training_evaluation', {
        'target_event_id': eventId,
        'expected_revision': expectedRevision,
        'session_rating': rating,
        'reached': goalReached?.name,
        'well': wentWell,
        'differently': doDifferently,
        'next_session': nextTime,
        'block_ratings': [for (final block in blocks) block.toJson()],
      });
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid training evaluation.');
      }
      return TrainingEvaluation.fromJson(value);
    } on PostgrestException catch (error) {
      if (error.message.contains('stale_revision')) {
        throw const TrainingSessionConflict();
      }
      rethrow;
    }
  }
}
