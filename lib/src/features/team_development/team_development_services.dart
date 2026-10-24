import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/team_development/team_development_models.dart';

export 'package:teamzone_app/src/features/team_development/team_development_models.dart';

/// A change the server refused: `stale_revision` (changed elsewhere since it
/// was read), `overlapping_season`, `overlapping_period`, `outside_season`,
/// `too_many`, `invalid_input` or `not_allowed`.
class TeamDevelopmentException implements Exception {
  const TeamDevelopmentException(this.code);
  final String code;

  static const codes = [
    'stale_revision',
    'overlapping_season',
    'overlapping_period',
    'outside_season',
    'too_many',
    'invalid_input',
    'not_allowed',
  ];

  /// What to tell the leader.
  String get message => switch (code) {
    'stale_revision' =>
      'Planen har ändrats av någon annan. Den senaste visas nu.',
    'overlapping_season' => 'Datumen krockar med en annan säsong.',
    'overlapping_period' => 'Datumen krockar med en annan period.',
    'outside_season' =>
      'Datumen måste ligga inom säsongen, och säsongen måste rymma sina perioder och mål.',
    'too_many' => 'Planen har redan så många som får plats.',
    'not_allowed' => 'Planen kan inte ändras här.',
    _ => 'Kontrollera uppgifterna och försök igen.',
  };
}

/// The team's plan. Every change is made on the revision read and returns
/// the plan as it is after the change.
abstract interface class TeamDevelopmentServices {
  /// The team's seasons and one plan: [planId], else today's season.
  Future<TeamDevelopment> get(String teamId, {String? planId});
  Future<SeasonPlan> createPlan({
    required String teamId,
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
  });
  Future<SeasonPlan> savePlan(
    SeasonPlan plan, {
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
    int? checkinEveryDays,
  });

  /// A new period when [periodId] is null.
  Future<SeasonPlan> savePeriod(
    SeasonPlan plan, {
    String? periodId,
    required String name,
    required PeriodPhase phase,
    required DateTime startsOn,
    required DateTime endsOn,
    required String focus,
  });
  Future<SeasonPlan> deletePeriod(SeasonPlan plan, String periodId);

  /// A new goal when [goalId] is null.
  Future<SeasonPlan> saveGoal(
    SeasonPlan plan, {
    String? goalId,
    required GoalHorizon horizon,
    String? periodId,
    required String title,
    required String description,
    DateTime? targetOn,
    required GoalState state,
  });
  Future<SeasonPlan> deleteGoal(SeasonPlan plan, String goalId);

  /// A new principle when [principleId] is null.
  Future<SeasonPlan> savePrinciple(
    SeasonPlan plan, {
    String? principleId,
    required PrincipleArea area,
    required String title,
    required String description,
  });
  Future<SeasonPlan> deletePrinciple(SeasonPlan plan, String principleId);

  /// A new key figure when [kpiId] is null.
  Future<SeasonPlan> saveKpi(
    SeasonPlan plan, {
    String? kpiId,
    required String title,
    required String unit,
    double? target,
    required bool higherIsBetter,
  });
  Future<SeasonPlan> deleteKpi(SeasonPlan plan, String kpiId);

  /// A check-in on a goal ([status]) or a key figure ([value]).
  Future<SeasonPlan> addCheckin(
    SeasonPlan plan, {
    String? goalId,
    String? kpiId,
    required DateTime checkedOn,
    CheckinStatus? status,
    double? value,
    required String note,
  });
  Future<SeasonPlan> deleteCheckin(SeasonPlan plan, String checkinId);

  /// What the players and guardians see.
  Future<SeasonPlan> setSharing(SeasonPlan plan, PlanSharing sharing);
  Future<SeasonPlan> addGoalLink(
    SeasonPlan plan, {
    required String goalId,
    required String title,
    required String url,
    required bool visible,
  });

  /// Shown to the players or not; `visible: null` removes the link.
  Future<SeasonPlan> changeGoalLink(
    SeasonPlan plan,
    String linkId, {
    required bool? visible,
  });

  /// The shared parts of today's season (else the next) for the team's
  /// players and guardians; null when nothing is shared.
  Future<SharedTeamPlan?> getShared(String teamId);
}

class UnconfiguredTeamDevelopmentServices implements TeamDevelopmentServices {
  const UnconfiguredTeamDevelopmentServices();
  StateError get _error => StateError('Supabase is not configured.');
  @override
  Future<TeamDevelopment> get(String teamId, {String? planId}) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> createPlan({
    required String teamId,
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> savePlan(
    SeasonPlan plan, {
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
    int? checkinEveryDays,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> savePeriod(
    SeasonPlan plan, {
    String? periodId,
    required String name,
    required PeriodPhase phase,
    required DateTime startsOn,
    required DateTime endsOn,
    required String focus,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> deletePeriod(SeasonPlan plan, String periodId) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> saveGoal(
    SeasonPlan plan, {
    String? goalId,
    required GoalHorizon horizon,
    String? periodId,
    required String title,
    required String description,
    DateTime? targetOn,
    required GoalState state,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> deleteGoal(SeasonPlan plan, String goalId) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> savePrinciple(
    SeasonPlan plan, {
    String? principleId,
    required PrincipleArea area,
    required String title,
    required String description,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> deletePrinciple(SeasonPlan plan, String principleId) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> saveKpi(
    SeasonPlan plan, {
    String? kpiId,
    required String title,
    required String unit,
    double? target,
    required bool higherIsBetter,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> deleteKpi(SeasonPlan plan, String kpiId) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> addCheckin(
    SeasonPlan plan, {
    String? goalId,
    String? kpiId,
    required DateTime checkedOn,
    CheckinStatus? status,
    double? value,
    required String note,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> deleteCheckin(SeasonPlan plan, String checkinId) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> setSharing(SeasonPlan plan, PlanSharing sharing) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> addGoalLink(
    SeasonPlan plan, {
    required String goalId,
    required String title,
    required String url,
    required bool visible,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> changeGoalLink(
    SeasonPlan plan,
    String linkId, {
    required bool? visible,
  }) => Future.error(_error);
  @override
  Future<SharedTeamPlan?> getShared(String teamId) => Future.error(_error);
}

class SupabaseTeamDevelopmentServices implements TeamDevelopmentServices {
  SupabaseTeamDevelopmentServices(this._client);
  final SupabaseClient _client;

  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> _rpc(
    String name,
    Map<String, Object?> params,
  ) async {
    try {
      final value = await _client
          .schema('api')
          .rpc<Object?>(name, params: params)
          .timeout(const Duration(seconds: 15));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid team development response.');
      }
      return value;
    } on PostgrestException catch (error) {
      final code = TeamDevelopmentException.codes
          .where(error.message.contains)
          .firstOrNull;
      if (code != null) throw TeamDevelopmentException(code);
      rethrow;
    }
  }

  @override
  Future<TeamDevelopment> get(String teamId, {String? planId}) async =>
      TeamDevelopment.fromJson(
        await _rpc('get_team_development', {
          'target_team_id': teamId,
          'target_plan_id': planId,
        }),
      );

  @override
  Future<SeasonPlan> createPlan({
    required String teamId,
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
  }) async => SeasonPlan.fromJson(
    await _rpc('create_team_development_plan', {
      'target_team_id': teamId,
      'plan_title': title,
      'starts': _day(startsOn),
      'ends': _day(endsOn),
      'vision': vision,
    }),
  );

  @override
  Future<SeasonPlan> savePlan(
    SeasonPlan plan, {
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
    required String vision,
    int? checkinEveryDays,
  }) async => SeasonPlan.fromJson(
    await _rpc('save_team_development_plan', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'plan_title': title,
      'starts': _day(startsOn),
      'ends': _day(endsOn),
      'vision': vision,
      'checkin_days': checkinEveryDays,
    }),
  );

  @override
  Future<SeasonPlan> savePeriod(
    SeasonPlan plan, {
    String? periodId,
    required String name,
    required PeriodPhase phase,
    required DateTime startsOn,
    required DateTime endsOn,
    required String focus,
  }) async => SeasonPlan.fromJson(
    await _rpc('save_team_development_period', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'target_period_id': periodId,
      'period_name': name,
      'period_phase': phase.key,
      'starts': _day(startsOn),
      'ends': _day(endsOn),
      'period_focus': focus,
    }),
  );

  @override
  Future<SeasonPlan> deletePeriod(SeasonPlan plan, String periodId) async =>
      SeasonPlan.fromJson(
        await _rpc('delete_team_development_period', {
          'target_plan_id': plan.id,
          'expected_revision': plan.revision,
          'target_period_id': periodId,
        }),
      );

  @override
  Future<SeasonPlan> saveGoal(
    SeasonPlan plan, {
    String? goalId,
    required GoalHorizon horizon,
    String? periodId,
    required String title,
    required String description,
    DateTime? targetOn,
    required GoalState state,
  }) async => SeasonPlan.fromJson(
    await _rpc('save_team_development_goal', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'target_goal_id': goalId,
      'goal_horizon': horizon.name,
      'target_period_id': periodId,
      'goal_title': title,
      'goal_description': description,
      'goal_target_on': targetOn == null ? null : _day(targetOn),
      'goal_state': state.name,
    }),
  );

  @override
  Future<SeasonPlan> deleteGoal(SeasonPlan plan, String goalId) async =>
      SeasonPlan.fromJson(
        await _rpc('delete_team_development_goal', {
          'target_plan_id': plan.id,
          'expected_revision': plan.revision,
          'target_goal_id': goalId,
        }),
      );

  @override
  Future<SeasonPlan> savePrinciple(
    SeasonPlan plan, {
    String? principleId,
    required PrincipleArea area,
    required String title,
    required String description,
  }) async => SeasonPlan.fromJson(
    await _rpc('save_team_development_principle', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'target_principle_id': principleId,
      'principle_area': area.key,
      'principle_title': title,
      'principle_description': description,
    }),
  );

  @override
  Future<SeasonPlan> deletePrinciple(
    SeasonPlan plan,
    String principleId,
  ) async => SeasonPlan.fromJson(
    await _rpc('delete_team_development_principle', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'target_principle_id': principleId,
    }),
  );

  @override
  Future<SeasonPlan> saveKpi(
    SeasonPlan plan, {
    String? kpiId,
    required String title,
    required String unit,
    double? target,
    required bool higherIsBetter,
  }) async => SeasonPlan.fromJson(
    await _rpc('save_team_development_kpi', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'target_kpi_id': kpiId,
      'kpi_title': title,
      'kpi_unit': unit,
      'kpi_target': target,
      'higher_better': higherIsBetter,
    }),
  );

  @override
  Future<SeasonPlan> deleteKpi(SeasonPlan plan, String kpiId) async =>
      SeasonPlan.fromJson(
        await _rpc('delete_team_development_kpi', {
          'target_plan_id': plan.id,
          'expected_revision': plan.revision,
          'target_kpi_id': kpiId,
        }),
      );

  @override
  Future<SeasonPlan> addCheckin(
    SeasonPlan plan, {
    String? goalId,
    String? kpiId,
    required DateTime checkedOn,
    CheckinStatus? status,
    double? value,
    required String note,
  }) async => SeasonPlan.fromJson(
    await _rpc('add_team_development_checkin', {
      'target_plan_id': plan.id,
      'target_goal_id': goalId,
      'target_kpi_id': kpiId,
      'checked': _day(checkedOn),
      'checkin_status': status?.key,
      'checkin_value': value,
      'checkin_note': note,
    }),
  );

  @override
  Future<SeasonPlan> deleteCheckin(SeasonPlan plan, String checkinId) async =>
      SeasonPlan.fromJson(
        await _rpc('delete_team_development_checkin', {
          'target_plan_id': plan.id,
          'target_checkin_id': checkinId,
        }),
      );

  @override
  Future<SeasonPlan> setSharing(SeasonPlan plan, PlanSharing sharing) async =>
      SeasonPlan.fromJson(
        await _rpc('set_team_development_sharing', {
          'target_plan_id': plan.id,
          'expected_revision': plan.revision,
          'vision': sharing.vision,
          'periods': sharing.periods,
          'principles': sharing.principles,
          'goals': sharing.goals,
        }),
      );

  @override
  Future<SeasonPlan> addGoalLink(
    SeasonPlan plan, {
    required String goalId,
    required String title,
    required String url,
    required bool visible,
  }) async => SeasonPlan.fromJson(
    await _rpc('add_team_development_goal_link', {
      'target_plan_id': plan.id,
      'target_goal_id': goalId,
      'link_title': title,
      'link_url': url,
      'show_players': visible,
    }),
  );

  @override
  Future<SeasonPlan> changeGoalLink(
    SeasonPlan plan,
    String linkId, {
    required bool? visible,
  }) async => SeasonPlan.fromJson(
    await _rpc('change_team_development_goal_link', {
      'target_plan_id': plan.id,
      'target_link_id': linkId,
      'show_players': visible,
    }),
  );

  @override
  Future<SharedTeamPlan?> getShared(String teamId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'get_shared_team_development',
          params: {'target_team_id': teamId},
        )
        .timeout(const Duration(seconds: 15));
    return value is Map<String, dynamic>
        ? SharedTeamPlan.fromJson(value)
        : null;
  }
}

/// The suggestion from the team's plan for an event's preparation, for the
/// services that prepare events; null when there is none to give.
Future<TeamPlanSuggestion?> loadTeamPlanSuggestion(
  SupabaseClient client,
  String eventId,
) async {
  final value = await client
      .schema('api')
      .rpc<Object?>(
        'get_team_plan_suggestion',
        params: {'target_event_id': eventId},
      )
      .timeout(const Duration(seconds: 15));
  if (value is! Map<String, dynamic>) return null;
  final suggestion = TeamPlanSuggestion.fromJson(value);
  return suggestion.isEmpty ? null : suggestion;
}
