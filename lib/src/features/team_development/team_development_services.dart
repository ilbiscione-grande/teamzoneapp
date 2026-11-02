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
    'overlapping_block',
    'outside_season',
    'outside_period',
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
    'overlapping_block' => 'Datumen krockar med ett annat block.',
    'outside_period' =>
      'Ett block måste ligga inom sin period, och perioden måste rymma sina block.',
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

  /// [plan] takes the principles and key figures (not their values) of
  /// the team's season [fromPlanId], keeping what it has.
  Future<SeasonPlan> copySeason(
    SeasonPlan plan, {
    required String fromPlanId,
    required bool principles,
    required bool kpis,
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

  /// A new block in [periodId] when [blockId] is null, with the plan's
  /// principles in focus in the order given.
  Future<SeasonPlan> saveBlock(
    SeasonPlan plan, {
    String? blockId,
    required String periodId,
    required String name,
    required DateTime startsOn,
    required DateTime endsOn,
    required String focus,
    required List<String> principleIds,
  });
  Future<SeasonPlan> deleteBlock(SeasonPlan plan, String blockId);

  /// A new goal when [goalId] is null.
  Future<SeasonPlan> saveGoal(
    SeasonPlan plan, {
    String? goalId,
    required GoalHorizon horizon,
    String? periodId,
    String? blockId,
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
    String? source,
  });
  Future<SeasonPlan> deleteKpi(SeasonPlan plan, String kpiId);

  /// A block's exercises: chosen, and the library's that train it.
  Future<BlockExercises> blockExercises(SeasonPlan plan, String blockId);

  /// Chooses an exercise for a block: a library item ([sharedItemId]) or
  /// the leaders' own ([title], [description]).
  Future<BlockExercises> addBlockExercise(
    SeasonPlan plan,
    String blockId, {
    String? sharedItemId,
    String title = '',
    String description = '',
  });
  Future<BlockExercises> deleteBlockExercise(
    SeasonPlan plan,
    String exerciseId,
  );

  /// The club's or TeamZone's library ([source] club or teamzone).
  Future<List<BlockExercise>> listLibrary(String source, {String search = ''});

  /// The players' load up to [day] (today when none), with the signals.
  Future<TeamLoad> load(SeasonPlan plan, {DateTime? day});

  /// The team's values for the signals; null turns one off.
  Future<TeamLoad> saveLoadSettings(SeasonPlan plan, LoadSettings settings);

  /// Turns the effort notification after trainings on or off for the team.
  Future<TeamLoad> setEffortPush(SeasonPlan plan, bool on);

  /// The team's players with their injury registration and injuries
  /// (step 9), for the leaders.
  Future<TeamInjuries> injuries(SeasonPlan plan);

  /// Registers an injury ([injuryId] null) or changes one.
  Future<TeamInjuries> saveInjury(
    SeasonPlan plan, {
    String? injuryId,
    required String personId,
    required DateTime startedOn,
    required String what,
    String note = '',
    DateTime? backOn,
  });
  Future<TeamInjuries> deleteInjury(SeasonPlan plan, String injuryId);

  /// Turns a player's registration off (deleting the injuries) or on, and
  /// gives or withdraws the club's consent under 15; null leaves either.
  Future<TeamInjuries> setInjuryRegistration(
    SeasonPlan plan,
    String personId, {
    bool? turnOff,
    bool? clubConsent,
  });

  /// The player's own and their children's injuries in a team, without
  /// the leaders' notes.
  Future<TeamInjuries> myInjuries(String teamId);

  /// The player's or a guardian's consent under 15.
  Future<TeamInjuries> setInjuryConsent(
    String teamId,
    String personId,
    bool give,
  );

  /// A key figure's value for a played match, set by hand in place of the
  /// counted one; no [value] shows the counted one again.
  Future<SeasonPlan> setKpiMatchValue(
    SeasonPlan plan, {
    required String kpiId,
    required String eventId,
    double? value,
    String note = '',
  });

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
  Future<SeasonPlan> copySeason(
    SeasonPlan plan, {
    required String fromPlanId,
    required bool principles,
    required bool kpis,
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
  Future<SeasonPlan> saveBlock(
    SeasonPlan plan, {
    String? blockId,
    required String periodId,
    required String name,
    required DateTime startsOn,
    required DateTime endsOn,
    required String focus,
    required List<String> principleIds,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> deleteBlock(SeasonPlan plan, String blockId) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> saveGoal(
    SeasonPlan plan, {
    String? goalId,
    required GoalHorizon horizon,
    String? periodId,
    String? blockId,
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
    String? source,
  }) => Future.error(_error);
  @override
  Future<SeasonPlan> deleteKpi(SeasonPlan plan, String kpiId) =>
      Future.error(_error);
  @override
  Future<SeasonPlan> setKpiMatchValue(
    SeasonPlan plan, {
    required String kpiId,
    required String eventId,
    double? value,
    String note = '',
  }) => Future.error(_error);
  @override
  Future<BlockExercises> blockExercises(SeasonPlan plan, String blockId) =>
      Future.error(_error);
  @override
  Future<BlockExercises> addBlockExercise(
    SeasonPlan plan,
    String blockId, {
    String? sharedItemId,
    String title = '',
    String description = '',
  }) => Future.error(_error);
  @override
  Future<BlockExercises> deleteBlockExercise(
    SeasonPlan plan,
    String exerciseId,
  ) => Future.error(_error);
  @override
  Future<List<BlockExercise>> listLibrary(
    String source, {
    String search = '',
  }) => Future.error(_error);
  @override
  Future<TeamLoad> load(SeasonPlan plan, {DateTime? day}) =>
      Future.error(_error);
  @override
  Future<TeamLoad> saveLoadSettings(SeasonPlan plan, LoadSettings settings) =>
      Future.error(_error);
  @override
  Future<TeamLoad> setEffortPush(SeasonPlan plan, bool on) =>
      Future.error(_error);
  @override
  Future<TeamInjuries> injuries(SeasonPlan plan) => Future.error(_error);
  @override
  Future<TeamInjuries> saveInjury(
    SeasonPlan plan, {
    String? injuryId,
    required String personId,
    required DateTime startedOn,
    required String what,
    String note = '',
    DateTime? backOn,
  }) => Future.error(_error);
  @override
  Future<TeamInjuries> deleteInjury(SeasonPlan plan, String injuryId) =>
      Future.error(_error);
  @override
  Future<TeamInjuries> setInjuryRegistration(
    SeasonPlan plan,
    String personId, {
    bool? turnOff,
    bool? clubConsent,
  }) => Future.error(_error);
  @override
  Future<TeamInjuries> myInjuries(String teamId) async => const TeamInjuries();
  @override
  Future<TeamInjuries> setInjuryConsent(
    String teamId,
    String personId,
    bool give,
  ) => Future.error(_error);
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
  Future<SeasonPlan> copySeason(
    SeasonPlan plan, {
    required String fromPlanId,
    required bool principles,
    required bool kpis,
  }) async => SeasonPlan.fromJson(
    await _rpc('copy_team_development_season', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'source_plan_id': fromPlanId,
      'copy_principles': principles,
      'copy_kpis': kpis,
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
  Future<SeasonPlan> saveBlock(
    SeasonPlan plan, {
    String? blockId,
    required String periodId,
    required String name,
    required DateTime startsOn,
    required DateTime endsOn,
    required String focus,
    required List<String> principleIds,
  }) async => SeasonPlan.fromJson(
    await _rpc('save_team_development_block', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'target_block_id': blockId,
      'target_period_id': periodId,
      'block_name': name,
      'starts': _day(startsOn),
      'ends': _day(endsOn),
      'block_focus': focus,
      'principle_ids': principleIds,
    }),
  );

  @override
  Future<SeasonPlan> deleteBlock(SeasonPlan plan, String blockId) async =>
      SeasonPlan.fromJson(
        await _rpc('delete_team_development_block', {
          'target_plan_id': plan.id,
          'expected_revision': plan.revision,
          'target_block_id': blockId,
        }),
      );

  @override
  Future<SeasonPlan> saveGoal(
    SeasonPlan plan, {
    String? goalId,
    required GoalHorizon horizon,
    String? periodId,
    String? blockId,
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
      'target_block_id': blockId,
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
    String? source,
  }) async => SeasonPlan.fromJson(
    await _rpc('save_team_development_kpi', {
      'target_plan_id': plan.id,
      'expected_revision': plan.revision,
      'target_kpi_id': kpiId,
      'kpi_title': title,
      'kpi_unit': unit,
      'kpi_target': target,
      'higher_better': higherIsBetter,
      'kpi_source': source ?? '',
    }),
  );

  @override
  Future<BlockExercises> blockExercises(
    SeasonPlan plan,
    String blockId,
  ) async => BlockExercises.fromJson(
    await _rpc('get_team_development_block_exercises', {
      'target_plan_id': plan.id,
      'target_block_id': blockId,
    }),
  );

  @override
  Future<BlockExercises> addBlockExercise(
    SeasonPlan plan,
    String blockId, {
    String? sharedItemId,
    String title = '',
    String description = '',
  }) async => BlockExercises.fromJson(
    await _rpc('add_team_development_block_exercise', {
      'target_plan_id': plan.id,
      'target_block_id': blockId,
      'target_shared_item_id': sharedItemId,
      'own_title': title,
      'own_description': description,
    }),
  );

  @override
  Future<BlockExercises> deleteBlockExercise(
    SeasonPlan plan,
    String exerciseId,
  ) async => BlockExercises.fromJson(
    await _rpc('delete_team_development_block_exercise', {
      'target_plan_id': plan.id,
      'target_exercise_id': exerciseId,
    }),
  );

  @override
  Future<List<BlockExercise>> listLibrary(
    String source, {
    String search = '',
  }) async {
    final rows = await _client
        .schema('api')
        .rpc<Object?>(
          'list_training_passes',
          params: {'pass_source': source, 'search_text': search},
        );
    return [
      for (final row in (rows as List? ?? const []).whereType<Map>())
        BlockExercise.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<TeamLoad> load(SeasonPlan plan, {DateTime? day}) async =>
      TeamLoad.fromJson(
        await _rpc('get_team_development_load', {
          'target_plan_id': plan.id,
          'target_day': day == null ? null : _day(day),
        }),
      );

  @override
  Future<TeamLoad> saveLoadSettings(
    SeasonPlan plan,
    LoadSettings settings,
  ) async => TeamLoad.fromJson(
    await _rpc('set_team_development_load_settings', {
      'target_plan_id': plan.id,
      'load_increase': settings.loadIncreasePercent,
      'attendance_min': settings.attendanceMinPercent,
      'match_minutes': settings.matchMinutesMax,
    }),
  );

  @override
  Future<TeamLoad> setEffortPush(SeasonPlan plan, bool on) async =>
      TeamLoad.fromJson(
        await _rpc('set_team_development_effort_push', {
          'target_plan_id': plan.id,
          'turn_on': on,
        }),
      );

  @override
  Future<TeamInjuries> injuries(SeasonPlan plan) async => TeamInjuries.fromJson(
    await _rpc('get_team_development_injuries', {'target_plan_id': plan.id}),
  );

  @override
  Future<TeamInjuries> saveInjury(
    SeasonPlan plan, {
    String? injuryId,
    required String personId,
    required DateTime startedOn,
    required String what,
    String note = '',
    DateTime? backOn,
  }) async => TeamInjuries.fromJson(
    await _rpc('save_team_development_injury', {
      'target_plan_id': plan.id,
      'target_injury_id': injuryId,
      'target_person_id': personId,
      'new_started_on': _day(startedOn),
      'new_what': what,
      'new_note': note,
      'new_back_on': backOn == null ? null : _day(backOn),
    }),
  );

  @override
  Future<TeamInjuries> deleteInjury(SeasonPlan plan, String injuryId) async =>
      TeamInjuries.fromJson(
        await _rpc('delete_team_development_injury', {
          'target_plan_id': plan.id,
          'target_injury_id': injuryId,
        }),
      );

  @override
  Future<TeamInjuries> setInjuryRegistration(
    SeasonPlan plan,
    String personId, {
    bool? turnOff,
    bool? clubConsent,
  }) async => TeamInjuries.fromJson(
    await _rpc('set_team_development_injury_registration', {
      'target_plan_id': plan.id,
      'target_person_id': personId,
      'turn_off': turnOff,
      'club_consent': clubConsent,
    }),
  );

  @override
  Future<TeamInjuries> myInjuries(String teamId) async => TeamInjuries.fromJson(
    await _rpc('get_my_injuries', {'target_team_id': teamId}),
  );

  @override
  Future<TeamInjuries> setInjuryConsent(
    String teamId,
    String personId,
    bool give,
  ) async => TeamInjuries.fromJson(
    await _rpc('set_injury_consent', {
      'target_team_id': teamId,
      'target_person_id': personId,
      'give': give,
    }),
  );

  @override
  Future<SeasonPlan> setKpiMatchValue(
    SeasonPlan plan, {
    required String kpiId,
    required String eventId,
    double? value,
    String note = '',
  }) async => SeasonPlan.fromJson(
    await _rpc('set_team_development_kpi_match_value', {
      'target_plan_id': plan.id,
      'target_kpi_id': kpiId,
      'target_event_id': eventId,
      'kpi_value': value,
      'value_note': note,
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
          'blocks': sharing.blocks,
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
