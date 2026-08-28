import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/development/development_models.dart';

abstract interface class DevelopmentServices {
  Future<List<DevelopmentPlan>> listPlans({
    required String clubId,
    required String teamId,
  });
  Future<void> createPlan({
    required String clubId,
    required String teamId,
    required String planType,
    String? subjectClubPersonId,
    required String title,
    required String focus,
    required String idempotencyKey,
  });
  Future<void> addAction({
    required String planId,
    required String title,
    required String description,
    DateTime? dueAt,
    required int expectedPlanRevision,
    required String idempotencyKey,
  });
}

class UnconfiguredDevelopmentServices implements DevelopmentServices {
  const UnconfiguredDevelopmentServices();

  @override
  Future<List<DevelopmentPlan>> listPlans({
    required String clubId,
    required String teamId,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<void> createPlan({
    required String clubId,
    required String teamId,
    required String planType,
    String? subjectClubPersonId,
    required String title,
    required String focus,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));

  @override
  Future<void> addAction({
    required String planId,
    required String title,
    required String description,
    DateTime? dueAt,
    required int expectedPlanRevision,
    required String idempotencyKey,
  }) => Future.error(StateError('Supabase is not configured.'));
}

class SupabaseDevelopmentServices implements DevelopmentServices {
  SupabaseDevelopmentServices(this._client);

  final SupabaseClient _client;

  @override
  Future<void> createPlan({
    required String clubId,
    required String teamId,
    required String planType,
    String? subjectClubPersonId,
    required String title,
    required String focus,
    required String idempotencyKey,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'create_development_plan',
          params: {
            'target_club_id': clubId,
            'target_team_id': teamId,
            'plan_type': planType,
            'subject_club_person_id': subjectClubPersonId,
            'title': title,
            'focus': focus,
            'idempotency_key': idempotencyKey,
          },
        );
  }

  @override
  Future<void> addAction({
    required String planId,
    required String title,
    required String description,
    DateTime? dueAt,
    required int expectedPlanRevision,
    required String idempotencyKey,
  }) async {
    await _client
        .schema('api')
        .rpc<Object?>(
          'add_development_action',
          params: {
            'target_plan_id': planId,
            'title': title,
            'description': description,
            'due_at': dueAt?.toUtc().toIso8601String(),
            'expected_plan_revision': expectedPlanRevision,
            'idempotency_key': idempotencyKey,
          },
        );
  }

  @override
  Future<List<DevelopmentPlan>> listPlans({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_development_plans',
          params: {'target_club_id': clubId, 'target_team_id': teamId},
        );
    if (value is! List) {
      throw const FormatException('Development response is not a list.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(DevelopmentPlan.fromJson)
        .toList(growable: false);
  }
}
